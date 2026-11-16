using Microsoft.Win32;
using System.Runtime.InteropServices;
using System.Drawing.Imaging;

namespace ImageReview;

internal sealed record ReviewInput(string Name, string Mime, Func<Stream> Open)
{
    internal static readonly Dictionary<string, string> Formats = new(StringComparer.OrdinalIgnoreCase)
    {
        [".png"] = "image/png", [".jpg"] = "image/jpeg", [".jpeg"] = "image/jpeg",
        [".gif"] = "image/gif", [".webp"] = "image/webp", [".bmp"] = "image/bmp",
        [".pdf"] = "application/pdf", [".json"] = "application/json"
    };

    public static ReviewInput? FromFile(string path) =>
        Formats.TryGetValue(Path.GetExtension(path), out var mime)
            ? new(Path.GetFileName(path), mime, () => File.OpenRead(path)) : null;

    public static ReviewInput FromCapture(Bitmap image)
    {
        var png = new MemoryStream();
        image.Save(png, ImageFormat.Png);
        png.Position = 0;
        return new($"スクリーンショット {DateTime.Now:yyyy-MM-dd HH.mm.ss.fff}.png", "image/png", () => png);
    }
}

internal static class Explorer
{
    public static void Register()
    {
        try
        {
            using var classes = Registry.CurrentUser.CreateSubKey(@"Software\Classes");
            WriteAssociations(classes, Application.ExecutablePath);
            SHChangeNotify(0x08000000, 0, IntPtr.Zero, IntPtr.Zero); // SHCNE_ASSOCCHANGED
            MessageBox.Show("エクスプローラーの「プログラムから開く」で ImageReview を選べます。", "ImageReview");
        }
        catch (Exception ex) { MessageBox.Show($"登録できませんでした。\n{ex.Message}", "ImageReview"); }
    }

    internal static void WriteAssociations(RegistryKey classes, string executable)
    {
        const string progId = "ImageReview.Document";
        using var document = classes.CreateSubKey(progId);
        document.SetValue("", "ImageReview");
        using var app = classes.CreateSubKey(@"Applications\ImageReview.exe");
        app.SetValue("FriendlyAppName", "ImageReview");
        string command = $"\"{executable}\" \"%1\"";
        foreach (var key in new[] { document, app })
        {
            using var open = key.CreateSubKey(@"shell\open\command");
            open.SetValue("", command);
        }
        using var supported = app.CreateSubKey("SupportedTypes");
        foreach (var ext in ReviewInput.Formats.Keys)
        {
            supported.SetValue(ext, "");
            using var choices = classes.CreateSubKey(ext + @"\OpenWithProgids");
            choices.SetValue(progId, Array.Empty<byte>(), RegistryValueKind.None);
        }
    }

    [DllImport("shell32.dll")]
    private static extern void SHChangeNotify(int eventId, uint flags, IntPtr item1, IntPtr item2);
}
