using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using Microsoft.Win32;

namespace Via.Windows;

public sealed class TrayService : IDisposable
{
    private readonly NotifyIcon _icon;
    private readonly ToolStripMenuItem _openItem;
    private readonly ToolStripMenuItem _quitItem;
    private readonly Dictionary<(bool Running, WifiRole Role), Icon> _iconCache = new();
    private readonly System.Windows.Threading.Dispatcher _dispatcher;
    private readonly Icon _appIcon;
    private readonly bool _ownsAppIcon;
    private string? _lastSsid;
    private WifiRole _lastRole = WifiRole.None;
    private bool _lastRunning;
    private bool _lightTaskbar;
    private bool _disposed;

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

        _dispatcher = System.Windows.Threading.Dispatcher.CurrentDispatcher;
        _appIcon = LoadAppIcon(out _ownsAppIcon);
        _icon = new NotifyIcon
        {
            Icon = _appIcon,
            Text = "Via",
            Visible = true,
            ContextMenuStrip = menu
        };
        _icon.DoubleClick += (_, _) => open();
        _lightTaskbar = UsesLightTaskbar();
        SystemEvents.UserPreferenceChanged += OnUserPreferenceChanged;
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
        UpdateStatusIcon(forceThemeCheck: false);
    }

    public void RefreshLanguage()
    {
        _openItem.Text = L10n.T("open_app");
        _quitItem.Text = L10n.T("quit_app");
        _icon.Text = Truncate(BuildTooltip(_lastSsid, _lastRole, _lastRunning));
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }
        _disposed = true;

        SystemEvents.UserPreferenceChanged -= OnUserPreferenceChanged;
        _icon.Visible = false;
        _icon.Dispose();
        foreach (var icon in _iconCache.Values)
        {
            icon.Dispose();
        }
        _iconCache.Clear();
        if (_ownsAppIcon)
        {
            _appIcon.Dispose();
        }
    }

    private void OnUserPreferenceChanged(object sender, UserPreferenceChangedEventArgs e)
    {
        if (e.Category != UserPreferenceCategory.General)
        {
            return;
        }

        // WinForms tray controls must only be touched from the UI thread.
        if (_dispatcher.CheckAccess())
        {
            RefreshTheme();
        }
        else
        {
            _dispatcher.BeginInvoke((Action)RefreshTheme);
        }
    }

    private void RefreshTheme() => UpdateStatusIcon(forceThemeCheck: true);

    private void UpdateStatusIcon(bool forceThemeCheck)
    {
        if (!_dispatcher.CheckAccess())
        {
            _dispatcher.BeginInvoke((Action)(() => UpdateStatusIcon(forceThemeCheck)));
            return;
        }
        if (_disposed)
        {
            return;
        }

        var key = (_lastRunning, _lastRole);
        if (forceThemeCheck)
        {
            var detected = UsesLightTaskbar();
            if (detected != _lightTaskbar)
            {
                _lightTaskbar = detected;
                var oldIcons = _iconCache.Values.ToArray();
                _iconCache.Clear();
                var replacement = CreateStatusIcon(key.Item1, key.Item2, detected);
                _iconCache[key] = replacement;
                // Install the new icon before disposing the one in the tray.
                _icon.Icon = replacement;
                foreach (var icon in oldIcons)
                {
                    icon.Dispose();
                }
            }
        }

        if (_iconCache.TryGetValue(key, out var cached))
        {
            if (!ReferenceEquals(_icon.Icon, cached))
            {
                _icon.Icon = cached;
            }
            return;
        }

        _iconCache[key] = CreateStatusIcon(key.Item1, key.Item2, _lightTaskbar);
        _icon.Icon = _iconCache[key];
    }

    private static string BuildTooltip(string? currentSsid, WifiRole role, bool running)
    {
        if (!running)
        {
            return $"Via: {L10n.T("status_paused")}";
        }

        if (string.IsNullOrWhiteSpace(currentSsid))
        {
            return $"Via: {L10n.T("not_connected")}";
        }

        var roleText = role switch
        {
            WifiRole.Priority => L10n.T("role_priority"),
            WifiRole.Backup => L10n.T("role_backup"),
            WifiRole.Other => L10n.T("role_other"),
            _ => L10n.T("role_none")
        };
        return $"Via: {currentSsid} · {roleText}";
    }

    private static string Truncate(string text) =>
        text.Length <= 120 ? text : text.Substring(0, 120);

    private static Icon CreateStatusIcon(bool running, WifiRole role, bool lightTaskbar)
    {
        using var bitmap = new Bitmap(32, 32, PixelFormat.Format32bppArgb);
        using (var graphics = Graphics.FromImage(bitmap))
        {
            graphics.SmoothingMode = SmoothingMode.AntiAlias;
            // Black on a light taskbar, white on a dark one, like the native
            // Windows Wi-Fi icon.
            var color = lightTaskbar ? Color.FromArgb(20, 20, 20) : Color.White;
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

    private static Icon LoadAppIcon(out bool ownsIcon)
    {
        var processPath = Compat.ProcessPath;
        if (!string.IsNullOrEmpty(processPath))
        {
            var icon = Icon.ExtractAssociatedIcon(processPath);
            if (icon != null)
            {
                ownsIcon = true;
                return icon;
            }
        }

        // SystemIcons exposes shared system resources; they are not owned here.
        ownsIcon = false;
        return SystemIcons.Application;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool DestroyIcon(IntPtr handle);
}
