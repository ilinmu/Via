using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using Microsoft.Win32;

namespace AutoWifi.Windows;

public sealed class TrayService : IDisposable
{
    private readonly NotifyIcon _icon;
    private readonly ToolStripMenuItem _openItem;
    private readonly ToolStripMenuItem _quitItem;

    private Icon? _statusIcon;
    private string? _lastSsid;
    private WifiRole _lastRole = WifiRole.None;
    private bool _lastRunning;

    public TrayService(Action open, Action quit)
    {
        _openItem = new ToolStripMenuItem(L10n.T("open_app"));
        _openItem.Click += (_, _) => open();
        _quitItem = new ToolStripMenuItem(L10n.T("quit_app"));
        _quitItem.Click += (_, _) => quit();

        var menu = new ContextMenuStrip();
        menu.Items.Add(_openItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(_quitItem);

        _icon = new NotifyIcon
        {
            Icon = LoadAppIcon(),
            Text = "Auto-Wifi",
            Visible = true,
            ContextMenuStrip = menu
        };
        _icon.DoubleClick += (_, _) => open();
    }

    /// <summary>
    /// Mirrors the macOS menu bar icon: a Wi-Fi glyph, a red dot when
    /// monitoring is stopped, and P/B while connected to a managed network.
    /// </summary>
    public void UpdateStatus(string? currentSsid, WifiRole role, bool running)
    {
        _lastSsid = currentSsid;
        _lastRole = role;
        _lastRunning = running;

        _icon.Text = Truncate(BuildTooltip(currentSsid, role, running));

        var icon = CreateStatusIcon(running, role);
        var previous = _statusIcon;
        _statusIcon = icon;
        _icon.Icon = icon;
        previous?.Dispose();
    }

    public void RefreshLanguage()
    {
        _openItem.Text = L10n.T("open_app");
        _quitItem.Text = L10n.T("quit_app");
        _icon.Text = Truncate(BuildTooltip(_lastSsid, _lastRole, _lastRunning));
    }

    public void Dispose()
    {
        _icon.Visible = false;
        _icon.Dispose();
        _statusIcon?.Dispose();
    }

    private static string BuildTooltip(string? currentSsid, WifiRole role, bool running)
    {
        if (!running)
        {
            return $"Auto-Wifi: {L10n.T("status_paused")}";
        }

        if (string.IsNullOrWhiteSpace(currentSsid))
        {
            return $"Auto-Wifi: {L10n.T("not_connected")}";
        }

        var roleText = role switch
        {
            WifiRole.Priority => L10n.T("role_priority"),
            WifiRole.Backup => L10n.T("role_backup"),
            WifiRole.Other => L10n.T("role_other"),
            _ => L10n.T("role_none")
        };
        return $"Auto-Wifi: {currentSsid} · {roleText}";
    }

    private static string Truncate(string text) =>
        text.Length <= 120 ? text : text[..120];

    private static Icon CreateStatusIcon(bool running, WifiRole role)
    {
        using var bitmap = new Bitmap(32, 32, PixelFormat.Format32bppArgb);
        using (var graphics = Graphics.FromImage(bitmap))
        {
            graphics.SmoothingMode = SmoothingMode.AntiAlias;
            // Black on a light taskbar, white on a dark one, like the native
            // Windows Wi-Fi icon.
            var color = UsesLightTaskbar() ? Color.FromArgb(20, 20, 20) : Color.White;
            DrawWifi(graphics, color);

            if (!running)
            {
                using var red = new SolidBrush(Color.FromArgb(255, 59, 48));
                graphics.FillEllipse(red, 20, 19, 10, 10);
            }
            else if (role is WifiRole.Priority or WifiRole.Backup)
            {
                using var font = new Font("Segoe UI", 11f, FontStyle.Bold, GraphicsUnit.Pixel);
                using var brush = new SolidBrush(color);
                graphics.DrawString(role == WifiRole.Priority ? "P" : "B", font, brush, 18, 12);
            }
        }

        var handle = bitmap.GetHicon();
        try
        {
            using var temporary = Icon.FromHandle(handle);
            return (Icon)temporary.Clone();
        }
        finally
        {
            DestroyIcon(handle);
        }
    }

    private static void DrawWifi(Graphics graphics, Color color)
    {
        using var pen = new Pen(color, 2.6f)
        {
            StartCap = LineCap.Round,
            EndCap = LineCap.Round
        };
        const float centerX = 12f;
        const float centerY = 23f;
        graphics.DrawArc(pen, centerX - 10.5f, centerY - 10.5f, 21f, 21f, 225f, 90f);
        graphics.DrawArc(pen, centerX - 6.5f, centerY - 6.5f, 13f, 13f, 225f, 90f);
        using var dot = new SolidBrush(color);
        graphics.FillEllipse(dot, centerX - 2.2f, centerY - 2.2f, 4.4f, 4.4f);
    }

    private static bool UsesLightTaskbar()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(
                @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
            );
            return key?.GetValue("SystemUsesLightTheme") is int value && value != 0;
        }
        catch
        {
            return false;
        }
    }

    private static Icon LoadAppIcon()
    {
        var processPath = Environment.ProcessPath;
        if (!string.IsNullOrEmpty(processPath))
        {
            var icon = Icon.ExtractAssociatedIcon(processPath);
            if (icon != null)
            {
                return icon;
            }
        }

        return SystemIcons.Application;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool DestroyIcon(IntPtr handle);
}
