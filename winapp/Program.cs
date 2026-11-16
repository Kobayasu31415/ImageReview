using Microsoft.VisualBasic.ApplicationServices;
using System.Runtime.InteropServices;

namespace ImageReview;

internal static class Program
{
    [STAThread]
    private static void Main(string[] args)
    {
        ApplicationConfiguration.Initialize();
        // 後から起動したプロセスの作業ディレクトリを基準に解決する。
        var paths = args.Select(Path.GetFullPath).ToArray();
        new DesktopApp().Run(paths);
    }
}

internal sealed class DesktopApp : WindowsFormsApplicationBase
{
    public DesktopApp() => IsSingleInstance = true;

    protected override void OnCreateMainForm() => MainForm = new TrayHost(CommandLineArgs.ToArray());

    protected override void OnStartupNextInstance(StartupNextInstanceEventArgs e)
    {
        e.BringToForeground = false;
        ((TrayHost)MainForm!).OpenFiles(e.CommandLine.ToArray());
        base.OnStartupNextInstance(e);
    }
}

internal sealed class TrayHost : Form
{
    private readonly NotifyIcon tray;
    private readonly ContextMenuStrip menu = new();
    private readonly List<int> registered = [];
    private bool selecting;
    private bool quitting;

    public TrayHost(string[] paths)
    {
        ShowInTaskbar = false;
        menu.Items.Add("新規ウィンドウ", null, (_, _) => OpenReview(null));
        menu.Items.Add("エクスプローラーの「プログラムから開く」に登録", null, (_, _) => Explorer.Register());
        menu.Items.Add(new ToolStripSeparator());
        var names = new[] { "画面全体を撮影", "範囲を選択して撮影", "ウィンドウを選択して撮影" };
        var conflicts = new List<string>();
        for (int i = 0; i < names.Length; i++)
        {
            int id = i + 7;
            var item = (ToolStripMenuItem)menu.Items.Add(names[i], null, async (_, _) =>
            {
                // 通知領域のメニューが消えてからデスクトップを撮る。
                await Task.Delay(250);
                CaptureScreen(id);
            });
            var shortcut = $"Ctrl+Shift+{id}";
            if (RegisterHotKey(Handle, id, 0x4000 | 0x0002 | 0x0004, (uint)(Keys.D0 + id)))
            {
                registered.Add(id);
                item.ShortcutKeyDisplayString = shortcut;
            }
            else conflicts.Add(shortcut);
        }
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("ImageReview を終了", null, async (_, _) => await QuitAsync());
        tray = new NotifyIcon { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath),
            Text = "ImageReview", ContextMenuStrip = menu, Visible = true };
        tray.DoubleClick += (_, _) => OpenReview(null);
        BeginInvoke(() =>
        {
            OpenFiles(paths);
            if (conflicts.Count > 0)
                tray.ShowBalloonTip(5000, "撮影ショートカットを登録できませんでした",
                    string.Join("、", conflicts) + " は使用中です。通知領域のメニューからも撮影できます。", ToolTipIcon.Warning);
        });
    }

    protected override void SetVisibleCore(bool value) => base.SetVisibleCore(false);

    public void OpenFiles(string[] paths)
    {
        if (paths.Length == 0) OpenReview(null);
        foreach (var path in paths)
        {
            if (File.Exists(path) && ReviewInput.FromFile(path) is { } input) OpenReview(input);
            else MessageBox.Show($"画像・PDF・ノートを開けませんでした。\n{path}", "ImageReview");
        }
    }

    private void OpenReview(ReviewInput? input)
    {
        var window = new ReviewWindow(input);
        window.Show();
        window.Activate();
    }

    private void CaptureScreen(int id)
    {
        if (selecting || quitting || IsDisposed) return;
        selecting = true;
        try
        {
            using var image = ScreenCapture.Take(id);
            if (image != null) OpenReview(ReviewInput.FromCapture(image));
        }
        catch (Exception ex) { MessageBox.Show($"撮影できませんでした。\n{ex.Message}", "ImageReview"); }
        finally { selecting = false; }
    }

    protected override void WndProc(ref Message message)
    {
        const int WM_HOTKEY = 0x0312;
        if (message.Msg == WM_HOTKEY && registered.Contains(message.WParam.ToInt32()))
        {
            int id = message.WParam.ToInt32();
            BeginInvoke(() => CaptureScreen(id));
        }
        base.WndProc(ref message);
    }

    private async Task QuitAsync()
    {
        if (quitting) return;
        quitting = true;
        try
        {
            foreach (var window in Application.OpenForms.OfType<ReviewWindow>().ToArray())
                if (!await window.TryCloseAsync()) return;
            Close();
        }
        finally { quitting = false; }
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            if (IsHandleCreated) foreach (int id in registered) UnregisterHotKey(Handle, id);
            tray.Dispose();
            menu.Dispose();
        }
        base.Dispose(disposing);
    }

    [DllImport("user32.dll")]
    private static extern bool RegisterHotKey(IntPtr hwnd, int id, uint modifiers, uint key);
    [DllImport("user32.dll")]
    private static extern bool UnregisterHotKey(IntPtr hwnd, int id);
}
