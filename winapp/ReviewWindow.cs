using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;
using System.Text.Json;

namespace ImageReview;

internal sealed class ReviewWindow : Form
{
    private const string Host = "imagereview.example";
    private const string Entry = "https://" + Host + "/index.html";
    private readonly WebView2 browser = new() { Dock = DockStyle.Fill };
    private ReviewInput? pending;
    private bool ready;
    private bool checkingClose;
    private bool approvedClose;

    public ReviewWindow(ReviewInput? input)
    {
        pending = input;
        Text = "ImageReview";
        Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath);
        Size = new Size(1280, 860);
        MinimumSize = new Size(640, 480);
        Controls.Add(browser);
    }

    protected override async void OnShown(EventArgs e)
    {
        base.OnShown(e);
        try
        {
            var assets = Path.Combine(AppContext.BaseDirectory, "web");
            if (!File.Exists(Path.Combine(assets, "index.html")))
                throw new FileNotFoundException("ImageReview.exe と同じ場所に web フォルダーが必要です。");
            var profile = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "ImageReview", "WebView2");
            browser.CreationProperties = new CoreWebView2CreationProperties { UserDataFolder = profile };
            await browser.EnsureCoreWebView2Async();
            if (IsDisposed) return;
            var core = browser.CoreWebView2;
            core.SetVirtualHostNameToFolderMapping(Host, assets, CoreWebView2HostResourceAccessKind.Deny);
            core.NavigationStarting += (_, args) => args.Cancel = args.Uri != Entry;
            core.NewWindowRequested += (_, args) => args.Handled = true;
            core.DocumentTitleChanged += (_, _) => Text = core.DocumentTitle;
            core.NavigationCompleted += EditorLoaded;
            core.Navigate(Entry);
        }
        catch (Exception ex) { ShowStartupError(ex.Message); }
    }

    private void ShowStartupError(string details)
    {
        if (IsDisposed) return;
        MessageBox.Show(this, $"編集画面を起動できませんでした。\n{details}", "ImageReview");
        approvedClose = true;
        Close();
    }

    private async void EditorLoaded(object? sender, CoreWebView2NavigationCompletedEventArgs e)
    {
        if (IsDisposed) return;
        if (!e.IsSuccess)
        {
            if (!ready) ShowStartupError(e.WebErrorStatus.ToString());
            return;
        }
        try
        {
            if (await browser.ExecuteScriptAsync("Boolean(window.imageReview)") != "true")
                throw new InvalidOperationException("編集画面のファイルを確認してください。");
            ready = true;
            if (pending is not { } file) return;
            pending = null;
            await OpenInputAsync(file);
        }
        catch (Exception ex) { ShowStartupError(ex.Message); }
    }

    private async Task OpenInputAsync(ReviewInput input)
    {
        try
        {
            using var source = input.Open();
            if (source.Length == 0) throw new InvalidDataException("ファイルが空です。");
            var core = browser.CoreWebView2;
            using var shared = core.Environment.CreateSharedBuffer((ulong)source.Length);
            using (var destination = shared.OpenStream()) await source.CopyToAsync(destination);
            if (IsDisposed) return;
            await browser.ExecuteScriptAsync("""
                window.chrome.webview.addEventListener('sharedbufferreceived', event => {
                    const bytes = event.getBuffer();
                    try {
                        const {name, type} = event.additionalData;
                        const file = new File([bytes], name, {type});
                        void window.imageReview.open(file, type === 'application/json');
                    } finally {
                        window.chrome.webview.releaseBuffer(bytes);
                    }
                }, {once: true});
                """);
            if (IsDisposed) return;
            core.PostSharedBufferToScript(shared, CoreWebView2SharedBufferAccess.ReadOnly,
                JsonSerializer.Serialize(new { name = input.Name, type = input.Mime }));
        }
        catch (Exception ex)
        {
            if (!IsDisposed) MessageBox.Show(this, $"ファイルを開けませんでした。\n{ex.Message}", "ImageReview");
        }
    }

    internal async Task<bool> TryCloseAsync()
    {
        if (IsDisposed) return true;
        if (checkingClose) return false;
        checkingClose = true;
        try
        {
            bool confirm = ready;
            if (ready)
            {
                try { confirm = await browser.ExecuteScriptAsync("window.imageReview.isDirty()") != "false"; }
                catch (Exception) { /* 読み取れない場合も、閉じる前に確認する。 */ }
            }
            if (confirm && MessageBox.Show(this, "未保存の変更があります。保存せずに閉じますか？", "ImageReview",
                MessageBoxButtons.YesNo, MessageBoxIcon.Question, MessageBoxDefaultButton.Button2) != DialogResult.Yes) return false;
            approvedClose = true;
            Close();
            return true;
        }
        finally { checkingClose = false; }
    }

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        if (!approvedClose && ready)
        {
            e.Cancel = true;
            BeginInvoke(async () => await TryCloseAsync());
        }
        base.OnFormClosing(e);
    }
}
