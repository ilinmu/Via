using System.Drawing;
using System.Windows.Forms;

namespace AutoWifi.Windows;

public sealed class TrayService : IDisposable
{
    private readonly NotifyIcon _icon;
    private readonly ToolStripMenuItem _openItem;
    private readonly ToolStripMenuItem _quitItem;

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
            Icon = SystemIcons.Application,
            Text = "Auto-Wifi",
            Visible = true,
            ContextMenuStrip = menu
        };
        _icon.DoubleClick += (_, _) => open();
    }

    public void RefreshLanguage()
    {
        _openItem.Text = L10n.T("open_app");
        _quitItem.Text = L10n.T("quit_app");
    }

    public void Dispose()
    {
        _icon.Visible = false;
        _icon.Dispose();
    }
}
