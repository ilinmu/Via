using System.Threading;
using System.Windows;

namespace AutoWifi.Windows;

// UseWindowsForms adds an implicit `System.Windows.Forms` using, which makes
// the unqualified `Application` name ambiguous.
public partial class App : System.Windows.Application
{
    private Mutex? _mutex;
    private TrayService? _tray;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        Theme.Apply();
        Theme.Watch();

        _mutex = new Mutex(true, "AutoWifi.Windows.SingleInstance", out var created);
        if (!created)
        {
            Shutdown();
            return;
        }

        var window = new MainWindow();
        MainWindow = window;
        _tray = new TrayService(window.ShowFromTray, window.RequestQuit);
        window.SetTray(_tray);
        window.Show();
        window.ShowFirstRunSetupIfNeeded();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _tray?.Dispose();
        if (_mutex is not null)
        {
            try
            {
                _mutex.ReleaseMutex();
            }
            catch (ApplicationException)
            {
                // The mutex was already released by a failed startup.
            }
            _mutex.Dispose();
        }
        base.OnExit(e);
    }
}
