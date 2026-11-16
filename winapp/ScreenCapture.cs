using System.Drawing.Imaging;
using System.Runtime.InteropServices;

namespace ImageReview;

internal static class ScreenCapture
{
    public static Bitmap? Take(int shortcut)
    {
        var bounds = shortcut == 7 ? Screen.FromPoint(Cursor.Position).Bounds : SystemInformation.VirtualScreen;
        using var desktop = new Bitmap(bounds.Width, bounds.Height, PixelFormat.Format32bppRgb);
        using (var graphics = Graphics.FromImage(desktop))
            graphics.CopyFromScreen(bounds.Location, Point.Empty, bounds.Size);
        if (shortcut == 7) return new Bitmap(desktop);

        using var picker = new CapturePicker(desktop, bounds, shortcut == 9 ? VisibleWindows(bounds) : null);
        return picker.ShowDialog() == DialogResult.OK
            ? desktop.Clone(picker.Selection, PixelFormat.Format32bppRgb) : null;
    }

    // 選択画面を出す前の重なり順で列挙し、背面のウィンドウと仮想デスクトップも区別する。
    private static List<Rectangle> VisibleWindows(Rectangle desktop)
    {
        List<Rectangle> windows = [];
        EnumWindows((hwnd, _) =>
        {
            if (!IsWindowVisible(hwnd) || IsIconic(hwnd) || hwnd == GetShellWindow()) return true;
            if (DwmGetWindowAttribute(hwnd, 14, out int cloaked, sizeof(int)) == 0 && cloaked != 0) return true;
            if (DwmGetWindowAttribute(hwnd, 9, out NativeRect rect, Marshal.SizeOf<NativeRect>()) != 0
                && !GetWindowRect(hwnd, out rect)) return true;
            var area = Rectangle.Intersect(desktop, Rectangle.FromLTRB(rect.Left, rect.Top, rect.Right, rect.Bottom));
            if (area.Width > 0 && area.Height > 0)
            {
                area.Offset(-desktop.X, -desktop.Y);
                windows.Add(area);
            }
            return true;
        }, IntPtr.Zero);
        return windows;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeRect { public int Left, Top, Right, Bottom; }
    private delegate bool EnumWindowProc(IntPtr hwnd, IntPtr state);
    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindowProc callback, IntPtr state);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr hwnd, out NativeRect rect);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern bool IsIconic(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern IntPtr GetShellWindow();
    [DllImport("dwmapi.dll")] private static extern int DwmGetWindowAttribute(IntPtr hwnd, int attribute, out NativeRect rect, int size);
    [DllImport("dwmapi.dll")] private static extern int DwmGetWindowAttribute(IntPtr hwnd, int attribute, out int value, int size);
}

internal sealed class CapturePicker : Form
{
    private readonly Bitmap snapshot;
    private readonly IReadOnlyList<Rectangle>? windows;
    private Point? start;
    public Rectangle Selection { get; private set; }

    public CapturePicker(Bitmap snapshot, Rectangle bounds, IReadOnlyList<Rectangle>? windows)
    {
        this.snapshot = snapshot;
        this.windows = windows;
        AutoScaleMode = AutoScaleMode.None;
        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.Manual;
        Bounds = bounds;
        ShowInTaskbar = false;
        TopMost = true;
        DoubleBuffered = true;
        Cursor = Cursors.Cross;
        Text = windows is null ? "撮影範囲を選択" : "撮影するウィンドウを選択";
        Shown += (_, _) => { Bounds = bounds; Activate(); UpdateSelection(PointToClient(Cursor.Position)); };
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        e.Graphics.DrawImageUnscaled(snapshot, Point.Empty);
        using var dim = new SolidBrush(Color.FromArgb(95, Color.Black));
        e.Graphics.FillRectangle(dim, ClientRectangle);
        if (Selection.Width <= 0 || Selection.Height <= 0) return;
        e.Graphics.DrawImage(snapshot, Selection, Selection, GraphicsUnit.Pixel);
        e.Graphics.DrawRectangle(Pens.White, Selection.X, Selection.Y, Selection.Width - 1, Selection.Height - 1);
    }

    private void UpdateSelection(Point p)
    {
        if (windows != null) Selection = windows.FirstOrDefault(rect => rect.Contains(p));
        else if (start is { } from)
        {
            var rect = Rectangle.FromLTRB(Math.Min(from.X, p.X), Math.Min(from.Y, p.Y),
                Math.Max(from.X, p.X), Math.Max(from.Y, p.Y));
            Selection = Rectangle.Intersect(ClientRectangle, rect);
        }
        Invalidate();
    }

    protected override void OnMouseDown(MouseEventArgs e)
    {
        if (e.Button == MouseButtons.Right) { DialogResult = DialogResult.Cancel; return; }
        if (e.Button != MouseButtons.Left) return;
        start = e.Location;
        Capture = true;
    }

    protected override void OnMouseMove(MouseEventArgs e) => UpdateSelection(e.Location);

    protected override void OnMouseUp(MouseEventArgs e)
    {
        if (e.Button != MouseButtons.Left || start == null) return;
        UpdateSelection(e.Location);
        start = null;
        Capture = false;
        if (Selection.Width > 0 && Selection.Height > 0) DialogResult = DialogResult.OK;
    }

    protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
    {
        if (keyData != Keys.Escape) return base.ProcessCmdKey(ref msg, keyData);
        DialogResult = DialogResult.Cancel;
        return true;
    }
}
