using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace ImageReview;

internal sealed record AIDestination(string Name, string? ProcessName, string NewChat, string? Recent = null);

internal static class AIHandoff
{
    internal static Dictionary<string, AIDestination> Discover()
    {
        bool claude = HandlesProtocol("claude", "Claude");
        var targets = new Dictionary<string, AIDestination>
        {
            ["claude"] = claude ? new("Claude（チャット）", "claude", "claude://claude.ai/new?surface=chat")
                : new("Claude（チャット）", null, "https://claude.ai/new"),
            ["chatgpt"] = HandlesProtocol("codex", "ChatGPT")
                ? new("ChatGPT", "Codex", "codex://threads/new")
                : new("ChatGPT", null, "https://chatgpt.com/")
        };
        if (claude) targets["claudeCode"] = new("Claude Code", "claude", "claude://code/new", "claude://code/continue?session=last");
        return targets;
    }

    private static bool HandlesProtocol(string scheme, string app)
    {
        var name = new StringBuilder(256);
        uint length = (uint)name.Capacity;
        // ASSOCF_IS_PROTOCOL / ASSOCSTR_FRIENDLYAPPNAME。MSIX 経由の登録にも対応する。
        return AssocQueryString(0x1000, 4, scheme, null, name, ref length) == 0
            && name.ToString().Equals(app, StringComparison.OrdinalIgnoreCase);
    }

    public static async Task<string> SendAsync(AIDestination target, bool fresh, string image)
    {
        CopyImage(image);
        uint clipboard = GetClipboardSequenceNumber();
        string manual = $"画像をコピーしました。{target.Name} の入力欄で Ctrl+V を押してください。";
        nint previous = target.ProcessName is null ? 0 : FindWindow(target.ProcessName);
        string? route = fresh ? target.NewChat : target.Recent;
        if (route != null)
        {
            try { Process.Start(new ProcessStartInfo(route) { UseShellExecute = true })?.Dispose(); }
            catch (Win32Exception) { return $"送り先を開けませんでした。{manual}"; }
        }
        else if (previous != 0)
        {
            if (IsIconic(previous)) ShowWindowAsync(previous, 9); // SW_RESTORE
            if (!SetForegroundWindow(previous)) return manual;
        }
        else return manual;

        if (target.ProcessName == null) return manual;
        var timer = Stopwatch.StartNew();
        while (timer.Elapsed < TimeSpan.FromSeconds(8))
        {
            nint window = GetForegroundWindow();
            if (window != 0 && IsTarget(window, target.ProcessName))
            {
                await Task.Delay(previous == 0 ? 2200 : 750);
                if (GetClipboardSequenceNumber() != clipboard) return "クリップボードが変更されました。もう一度「AIに送る」を押してください。";
                if (GetForegroundWindow() != window) return manual;
                SendKeys.SendWait("^v");
                return $"{target.Name} で貼り付けを実行しました。入力欄を確認してください。";
            }
            await Task.Delay(100);
        }
        return manual;
    }

    internal static void CopyImage(string image)
    {
        const string prefix = "data:image/png;base64,";
        if (!image.StartsWith(prefix, StringComparison.Ordinal)) throw new InvalidDataException("PNG 画像を読み込めません。");
        using var png = new MemoryStream(Convert.FromBase64String(image[prefix.Length..]));
        using var bitmap = new Bitmap(png);
        png.Position = 0;
        var data = new DataObject();
        data.SetData("PNG", false, png);
        data.SetImage(bitmap);
        Clipboard.SetDataObject(data, true, 8, 50);
    }

    private static nint FindWindow(string processName)
    {
        // Z 順に調べ、直前まで使っていた可視ウィンドウを優先する。
        for (nint window = GetTopWindow(0); window != 0; window = GetWindow(window, 2))
            if (IsWindowVisible(window) && IsTarget(window, processName)) return window;
        return 0;
    }

    private static bool IsTarget(nint window, string name)
    {
        GetWindowThreadProcessId(window, out uint pid);
        if (pid == 0) return false;
        try
        {
            using var process = Process.GetProcessById((int)pid);
            return process.ProcessName.Equals(name, StringComparison.OrdinalIgnoreCase);
        }
        catch (ArgumentException) { return false; } // ウィンドウが列挙中に閉じた。
        catch (InvalidOperationException) { return false; }
    }

    [DllImport("shlwapi.dll", CharSet = CharSet.Unicode)]
    private static extern int AssocQueryString(uint flags, uint kind, string assoc, string? extra, StringBuilder result, ref uint length);
    [DllImport("user32.dll")] private static extern uint GetClipboardSequenceNumber();
    [DllImport("user32.dll")] private static extern nint GetForegroundWindow();
    [DllImport("user32.dll")] private static extern nint GetTopWindow(nint parent);
    [DllImport("user32.dll")] private static extern nint GetWindow(nint window, uint command);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(nint window);
    [DllImport("user32.dll")] private static extern bool IsIconic(nint window);
    [DllImport("user32.dll")] private static extern bool ShowWindowAsync(nint window, int command);
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(nint window);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(nint window, out uint pid);
}
