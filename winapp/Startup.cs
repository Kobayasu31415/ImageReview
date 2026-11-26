using Microsoft.Win32;

namespace ImageReview;

// サインイン時の起動は、タスク スケジューラのログオン トリガーで行う。
// Run キーの項目はスタートアップ管理ツールや設定で無効にされることがあり、
// 電池で動いているときに実行されない既定も避けたい。
internal static class Startup
{
    private const string TaskName = "ImageReview";
    private const string LegacyRunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";

    public static bool IsEnabled() => RegisteredPath() != null;

    // 起動のたびに、登録先を今の実行ファイルに合わせる。
    // 1.2 の Run キーで登録していた場合は、ここでタスクへ移す。
    public static void Sync()
    {
        try
        {
            if (HasLegacyRunValue())
            {
                Register();
                RemoveLegacyRunValue();
            }
            else if (RegisteredPath() is { } path
                && !string.Equals(path, Application.ExecutablePath, StringComparison.OrdinalIgnoreCase))
                Register();
        }
        catch { /* 起動のたびに試すので、ここでは知らせない。 */ }
    }

    public static bool SetEnabled(bool enabled)
    {
        try
        {
            if (enabled) Register();
            else Unregister();
            RemoveLegacyRunValue();
            return true;
        }
        catch (Exception ex)
        {
            MessageBox.Show($"Windows 起動時の設定を変えられませんでした。\n{ex.Message}", "ImageReview");
            return false;
        }
    }

    private static dynamic Service()
    {
        dynamic service = Activator.CreateInstance(Type.GetTypeFromProgID("Schedule.Service")!)!;
        service.Connect();
        return service;
    }

    private static string? RegisteredPath()
    {
        try
        {
            dynamic task = Service().GetFolder("\\").GetTask(TaskName);
            foreach (dynamic action in task.Definition.Actions)
                if (action.Type == 0) return (string)action.Path;
            return null;
        }
        catch { return null; } // 未登録のときは COM が例外を返す。
    }

    private static void Register()
    {
        dynamic service = Service();
        dynamic definition = service.NewTask(0);
        definition.RegistrationInfo.Author = "ImageReview";
        definition.RegistrationInfo.Description = "サインインしたときに ImageReview を常駐させます。";
        definition.Settings.DisallowStartIfOnBatteries = false; // 電池で動いていても起動する。
        definition.Settings.StopIfGoingOnBatteries = false;
        definition.Settings.ExecutionTimeLimit = "PT0S";        // 常駐するので時間で止めない。
        definition.Settings.StartWhenAvailable = true;
        dynamic trigger = definition.Triggers.Create(9);        // TASK_TRIGGER_LOGON
        trigger.UserId = Environment.UserDomainName + "\\" + Environment.UserName;
        dynamic action = definition.Actions.Create(0);          // TASK_ACTION_EXEC
        action.Path = Application.ExecutablePath;
        action.Arguments = Cli.Background;
        action.WorkingDirectory = Path.GetDirectoryName(Application.ExecutablePath);
        // TASK_CREATE_OR_UPDATE, TASK_LOGON_INTERACTIVE_TOKEN
        service.GetFolder("\\").RegisterTaskDefinition(TaskName, definition, 6, null, null, 3, null);
    }

    private static void Unregister()
    {
        try { Service().GetFolder("\\").DeleteTask(TaskName, 0); }
        catch { /* もともと無ければそれでよい。 */ }
    }

    private static bool HasLegacyRunValue()
    {
        using var run = Registry.CurrentUser.OpenSubKey(LegacyRunKey);
        return run?.GetValue(TaskName) is string value && value.Length > 0;
    }

    // 1.2 までの登録先。タスクと二重に起動しないよう、設定を変えるときに消す。
    private static void RemoveLegacyRunValue()
    {
        try
        {
            using var run = Registry.CurrentUser.OpenSubKey(LegacyRunKey, writable: true);
            run?.DeleteValue(TaskName, false);
        }
        catch { }
    }
}
