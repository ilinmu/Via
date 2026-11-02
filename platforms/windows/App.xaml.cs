using System.Threading;
using System.Windows;

namespace AutoWifi.Windows;

public partial class App : Application
{
    private Mutex? _mutex;
    private TrayService? _tray;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

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
