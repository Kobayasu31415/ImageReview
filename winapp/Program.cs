using Microsoft.VisualBasic.ApplicationServices;
using System.Runtime.InteropServices;

// WindowsFormsApplicationBase は Guid がないと、ビルドごとに異なる MVID で常駐プロセスを識別する。
[assembly: Guid("5954725a-e622-47ee-9974-0af1086bcfd4")]

namespace ImageReview;

internal static class Program
{
    [STAThread]
    private static void Main(string[] args)
    {
        ApplicationConfiguration.Initialize();
        new DesktopApp().Run(Cli.Normalize(args));
    }
}

internal static class Cli
{
    // Windows 起動時は、編集ウィンドウを開かずに常駐だけする。
    public const string Background = "--background";

    // ファイルは、後から起動したプロセスの作業ディレクトリを基準に解決する。
    public static string[] Normalize(IEnumerable<string> args) =>
        args.Select(arg => IsFlag(arg) ? arg : Path.GetFullPath(arg)).ToArray();

    public static string[] Paths(IEnumerable<string> args) => args.Where(arg => !IsFlag(arg)).ToArray();

    public static bool IsBackground(IEnumerable<string> args) =>
        args.Any(arg => string.Equals(arg, Background, StringComparison.OrdinalIgnoreCase));

    private static bool IsFlag(string arg) => arg.StartsWith("--", StringComparison.Ordinal);
}

internal sealed class DesktopApp : WindowsFormsApplicationBase
{
    public DesktopApp() => IsSingleInstance = true;

    protected override void OnCreateMainForm() => MainForm = new TrayHost(CommandLineArgs.ToArray());

    protected override void OnStartupNextInstance(StartupNextInstanceEventArgs e)
    {
        e.BringToForeground = false;
        ((TrayHost)MainForm!).OpenFiles(Cli.Paths(e.CommandLine));
        base.OnStartupNextInstance(e);
    }
}

internal sealed class TrayHost : Form
{
    private readonly NotifyIcon tray;
    private readonly ContextMenuStrip menu = new();
    private readonly List<int> registered = [];
    private readonly Dictionary<int, ToolStripMenuItem> pendingShortcuts = [];
    private readonly System.Windows.Forms.Timer retryShortcuts = new() { Interval = 3000 };
    private bool selecting;
    private bool quitting;

    public TrayHost(string[] args)
    {
        var paths = Cli.Paths(args);
        bool background = Cli.IsBackground(args);
        Startup.RefreshPath();
        ShowInTaskbar = false;
        menu.Items.Add("新規ウィンドウ", null, (_, _) => OpenReview(null));
        menu.Items.Add("エクスプローラーの「プログラムから開く」に登録", null, (_, _) => Explorer.Register());
        var startup = new ToolStripMenuItem("Windows 起動時に開く") { Checked = Startup.IsEnabled() };
        startup.Click += (_, _) =>
        {
            if (Startup.SetEnabled(!startup.Checked)) startup.Checked = !startup.Checked;
        };
        menu.Items.Add(startup);
        menu.Items.Add(new ToolStripSeparator());
        var names = new[] { "画面全体を撮影", "範囲を選択して撮影", "ウィンドウを選択して撮影" };
        for (int i = 0; i < names.Length; i++)
        {
            int id = i + 7;
            var item = (ToolStripMenuItem)menu.Items.Add(names[i], null, async (_, _) =>
            {
                // 通知領域のメニューが消えてからデスクトップを撮る。
                await Task.Delay(250);
                CaptureScreen(id);
            });
            pendingShortcuts.Add(id, item);
        }
        retryShortcuts.Tick += (_, _) => RegisterAvailableShortcuts();
        RegisterAvailableShortcuts();
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("ImageReview を終了", null, async (_, _) => await QuitAsync());
        tray = new NotifyIcon { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath),
            Text = "ImageReview", ContextMenuStrip = menu, Visible = true };
        tray.DoubleClick += (_, _) => OpenReview(null);
        BeginInvoke(() =>
        {
            if (!background || paths.Length > 0) OpenFiles(paths);
            if (pendingShortcuts.Count > 0)
                tray.ShowBalloonTip(5000, "撮影ショートカットを登録できませんでした",
                    string.Join("、", pendingShortcuts.Keys.Select(id => $"Ctrl+Shift+{id}"))
                    + " は使用中です。空くと自動で登録します。", ToolTipIcon.Warning);
        });
    }

    private void RegisterAvailableShortcuts()
    {
        foreach (var (id, item) in pendingShortcuts.ToArray())
        {
            if (!RegisterHotKey(Handle, id, 0x4000 | 0x0002 | 0x0004, (uint)(Keys.D0 + id))) continue;
            registered.Add(id);
            item.ShortcutKeyDisplayString = $"Ctrl+Shift+{id}";
            pendingShortcuts.Remove(id);
        }
        retryShortcuts.Enabled = pendingShortcuts.Count > 0;
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
            retryShortcuts.Dispose();
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
