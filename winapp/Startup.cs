using Microsoft.Win32;

namespace ImageReview;

internal static class Startup
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "ImageReview";

    private static string Command => $"\"{Application.ExecutablePath}\" {Cli.Background}";

    public static bool IsEnabled() => Current() != null;

    // 別の場所のビルドに入れ替えても、登録済みなら新しい実行ファイルを指し直す。
    public static void RefreshPath()
    {
        if (Current() is { } command && command != Command) Write(Command);
    }

    public static bool SetEnabled(bool enabled)
    {
        try
        {
            Write(enabled ? Command : null);
            return true;
        }
        catch (Exception ex)
        {
            MessageBox.Show($"Windows 起動時の設定を変えられませんでした。\n{ex.Message}", "ImageReview");
            return false;
        }
    }

    private static string? Current()
    {
        try
        {
            using var run = Registry.CurrentUser.OpenSubKey(RunKey);
            return run?.GetValue(ValueName) is string value && value.Length > 0 ? value : null;
        }
        catch { return null; }
    }

    private static void Write(string? command)
    {
        using var run = Registry.CurrentUser.CreateSubKey(RunKey);
        if (command == null) run.DeleteValue(ValueName, false);
        else run.SetValue(ValueName, command);
    }
}
