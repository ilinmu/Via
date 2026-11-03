using System.Reflection;
using System.Windows;
using System.Windows.Controls;

namespace AutoWifi.Windows;

public partial class MainWindow : Window
{
    private readonly CredentialStore _credentials = new();
    private readonly WifiService _wifi = new();
    private readonly MonitorService _monitor;

    private AppSettings _settings = new();
    private TrayService? _tray;
    private bool _loading = true;
    private bool _syncingUi;
    private bool _allowClose;

    public MainWindow()
    {
        InitializeComponent();

        _monitor = new MonitorService(_credentials);
        _monitor.StatusChanged += OnMonitorStatus;
        _monitor.Log += OnMonitorLog;

        _settings = SettingsStore.Load();
        L10n.Language = _settings.Language;
        LoadSettingsIntoUi();
        ApplyLanguage();
        _loading = false;

        if (_settings.Running)
        {
            _monitor.Configure(_settings);
            _monitor.Start();
        }
    }

    public void SetTray(TrayService tray)
    {
        _tray = tray;
    }

    /// <summary>Opens the setup wizard on the first launch after installation.</summary>
    public void ShowFirstRunSetupIfNeeded()
    {
        if (!_settings.SetupCompleted)
        {
            ShowSetup();
        }
    }

    private void ShowSetup()
    {
        var wizard = new SetupWindow(_settings) { Owner = this };
        wizard.ShowDialog();

        // The wizard writes its own copy of the settings; reload before using
        // them here.
        _loading = true;
        _settings = SettingsStore.Load();
        LoadSettingsIntoUi();
        ApplyLanguage();
        _loading = false;

        if (wizard.StartRequested)
        {
            _settings.Running = true;
            SettingsStore.Save(_settings);
            _monitor.Configure(_settings);
            _monitor.Start();
            _syncingUi = true;
            AutoSwitchCheckBox.IsChecked = true;
            _syncingUi = false;
        }
    }

    public void ShowFromTray()
    {
        Show();
        WindowState = WindowState.Normal;
        Activate();
    }

    public void RequestQuit()
    {
        _allowClose = true;
        _monitor.Dispose();
        _tray?.Dispose();
        System.Windows.Application.Current.Shutdown();
    }

    private void LoadSettingsIntoUi()
    {
        PrioritySsidBox.Text = _settings.SsidP;
        BackupSsidBox.Text = _settings.SsidB;
        PriorityPasswordBox.Password = _credentials.Load("passwordP") ?? "";
        BackupPasswordBox.Password = _credentials.Load("passwordB") ?? "";
        IntervalBox.Text = _settings.CheckInterval.ToString();
        LaunchAtLoginCheckBox.IsChecked = StartupManager.IsEnabled();
        AutoSwitchCheckBox.IsChecked = _settings.Running;

        LanguageCombo.Items.Clear();
        LanguageCombo.Items.Add("中文");
        LanguageCombo.Items.Add("English");
        LanguageCombo.SelectedIndex = _settings.Language == "en" ? 1 : 0;

        VersionValue.Text = Assembly.GetExecutingAssembly().GetName().Version?.ToString()
            ?? "1.0.0";
    }

    private void ApplyLanguage()
    {
        Title = L10n.T("app_title");
        TitleText.Text = L10n.T("app_title");
        SubtitleText.Text = L10n.T("app_subtitle");
        StatusTab.Header = L10n.T("tab_status");
        NetworksTab.Header = L10n.T("tab_networks");
        SettingsTab.Header = L10n.T("tab_settings");

        CurrentSsidLabel.Text = L10n.T("current_network");
        AutoSwitchCheckBox.Content = L10n.T("auto_switch");
        AutoSwitchHint.Text = L10n.T("auto_switch_hint");
        NextCheckLabel.Text = L10n.T("next_check");
        ScanButton.Content = L10n.T("scan_networks");
        RefreshButton.Content = L10n.T("refresh_status");

        NetworksDescription.Text = L10n.T("networks_description");
        PriorityLabel.Text = L10n.T("priority_network");
        BackupLabel.Text = L10n.T("backup_network");
        ShowPasswordsCheckBox.Content = L10n.T("show_passwords");
        ScanHint.Text = L10n.T("scan_hint");
        ScanNetworksButton.Content = L10n.T("scan_networks");
        SaveButton.Content = L10n.T("save_changes");
        NetworkHint.Text = L10n.T("password_optional");

        GeneralLabel.Text = L10n.T("settings_general");
        LanguageLabel.Text = L10n.T("language");
        IntervalLabel.Text = L10n.T("interval");
        SecondsLabel.Text = L10n.T("seconds");
        LaunchAtLoginCheckBox.Content = L10n.T("launch_at_login");
        LaunchAtLoginHint.Text = L10n.T("launch_at_login_hint");
        AboutLabel.Text = L10n.T("about");
        VersionLabel.Text = L10n.T("version");
        PrivacyText.Text = L10n.T("privacy_note");
        QuitButton.Content = L10n.T("quit_app");
        RerunSetupButton.Content = L10n.T("rerun_setup");

        RoleValue.Text = $"{L10n.T("role")}: {RoleText(WifiRole.None)}";
        LastMessageText.Text = L10n.T("windows_limit_hint");
    }

    private void AutoSwitch_Changed(object sender, RoutedEventArgs e)
    {
        if (_loading || _syncingUi)
        {
            return;
        }

        if (AutoSwitchCheckBox.IsChecked == true)
        {
            if (!TrySaveSettings())
            {
                _syncingUi = true;
                AutoSwitchCheckBox.IsChecked = false;
                _syncingUi = false;
                return;
            }

            _settings.Running = true;
            SettingsStore.Save(_settings);
            _monitor.Configure(_settings);
            _monitor.Start();
        }
        else
        {
            _monitor.Stop();
            _settings.Running = false;
            SettingsStore.Save(_settings);
        }
    }

    private async void ScanButton_Click(object sender, RoutedEventArgs e)
    {
        var previous = ScanButton.Content;
        ScanButton.IsEnabled = false;
        ScanButton.Content = L10n.T("scanning");
        try
        {
            var networks = await Task.Run(() => _wifi.Scan());
            LastMessageText.Text = networks.Count == 0
                ? L10n.T("no_networks")
                : string.Join(", ", networks);
        }
        finally
        {
            ScanButton.Content = previous;
            ScanButton.IsEnabled = true;
        }
    }

    private void RefreshButton_Click(object sender, RoutedEventArgs e)
    {
        if (_monitor.IsRunning)
        {
            _monitor.Refresh();
        }
        else
        {
            LastMessageText.Text = L10n.T("monitor_stopped");
        }
    }

    private async void ScanNetworksButton_Click(object sender, RoutedEventArgs e)
    {
        ScanNetworksButton.IsEnabled = false;
        ScanNetworksButton.Content = L10n.T("scanning");
        try
        {
            var networks = await Task.Run(() => _wifi.Scan());
            // Both SSID fields are dropdowns of the last scan; the typed text
            // is kept so a manual entry is not overwritten.
            PrioritySsidBox.ItemsSource = networks;
            BackupSsidBox.ItemsSource = networks;
            ScanStatusText.Text = networks.Count == 0
                ? L10n.T("no_networks")
                : string.Format(L10n.T("networks_found_format"), networks.Count);
            ValidationText.Text = "";
        }
        finally
        {
            ScanNetworksButton.Content = L10n.T("scan_networks");
            ScanNetworksButton.IsEnabled = true;
        }
    }

    private void RerunSetupButton_Click(object sender, RoutedEventArgs e)
    {
        ShowSetup();
    }

    private void SaveButton_Click(object sender, RoutedEventArgs e)
    {
        TrySaveSettings();
    }

    private void ShowPasswords_Changed(object sender, RoutedEventArgs e)
    {
        var character = ShowPasswordsCheckBox.IsChecked == true ? '\0' : '●';
        PriorityPasswordBox.PasswordChar = character;
        BackupPasswordBox.PasswordChar = character;
    }

    private void LanguageCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_loading || LanguageCombo.SelectedIndex < 0)
        {
            return;
        }

        L10n.Language = LanguageCombo.SelectedIndex == 1 ? "en" : "zh";
        _settings.Language = L10n.Language;
        SettingsStore.Save(_settings);
        ApplyLanguage();
        _tray?.RefreshLanguage();
    }

    private void LaunchAtLogin_Changed(object sender, RoutedEventArgs e)
    {
        if (_loading)
        {
            return;
        }

        try
        {
            var enabled = LaunchAtLoginCheckBox.IsChecked == true;
            StartupManager.SetEnabled(enabled);
            _settings.LaunchAtLogin = enabled;
            SettingsStore.Save(_settings);
        }
        catch (Exception exception)
        {
            ValidationText.Text = exception.Message;
        }
    }

    private void QuitButton_Click(object sender, RoutedEventArgs e)
    {
        RequestQuit();
    }

    private bool TrySaveSettings()
    {
        var ssidP = PrioritySsidBox.Text.Trim();
        var ssidB = BackupSsidBox.Text.Trim();

        if (ssidP.Length == 0)
        {
            ValidationText.Text = L10n.T("missing_primary");
            return false;
        }

        if (ssidB.Length == 0)
        {
            ValidationText.Text = L10n.T("missing_backup");
            return false;
        }

        if (string.Equals(ssidP, ssidB, StringComparison.OrdinalIgnoreCase))
        {
            ValidationText.Text = L10n.T("same_network");
            return false;
        }

        var interval = int.TryParse(IntervalBox.Text.Trim(), out var parsed)
            ? parsed
            : _settings.CheckInterval;

        _settings.SsidP = ssidP;
        _settings.SsidB = ssidB;
        _settings.CheckInterval = Math.Clamp(interval, 5, 3600);
        _settings.Language = LanguageCombo.SelectedIndex == 1 ? "en" : "zh";
        _settings.LaunchAtLogin = LaunchAtLoginCheckBox.IsChecked == true;

        try
        {
            _credentials.Save("passwordP", PriorityPasswordBox.Password);
            _credentials.Save("passwordB", BackupPasswordBox.Password);
            SettingsStore.Save(_settings);
            StartupManager.SetEnabled(_settings.LaunchAtLogin);
        }
        catch (Exception exception)
        {
            ValidationText.Text = exception.Message;
            return false;
        }

        IntervalBox.Text = _settings.CheckInterval.ToString();
        ValidationText.Text = L10n.T("saved");
        _monitor.Configure(_settings);
        return true;
    }

    private void OnMonitorStatus(MonitorStatus status)
    {
        Dispatcher.BeginInvoke(() =>
        {
            CurrentSsidValue.Text = string.IsNullOrWhiteSpace(status.CurrentSsid)
                ? L10n.T("not_connected")
                : status.CurrentSsid;
            RoleValue.Text = $"{L10n.T("role")}: {RoleText(status.Role)}";
            NextCheckValue.Text = status.NextCheck?.ToString("HH:mm:ss") ?? "—";
            LastMessageText.Text = status.Message;
            if (_settings.Running != status.Running)
            {
                _settings.Running = status.Running;
                SettingsStore.Save(_settings);
            }
            _syncingUi = true;
            AutoSwitchCheckBox.IsChecked = status.Running;
            _syncingUi = false;
        });
    }

    private void OnMonitorLog(string message)
    {
        Dispatcher.BeginInvoke(() => LastMessageText.Text = message);
    }

    private static string RoleText(WifiRole role)
    {
        return role switch
        {
            WifiRole.Priority => L10n.T("role_priority"),
            WifiRole.Backup => L10n.T("role_backup"),
            WifiRole.Other => L10n.T("role_other"),
            _ => L10n.T("role_none")
        };
    }

    private void Window_Closing(object? sender, System.ComponentModel.CancelEventArgs e)
    {
        if (_allowClose)
        {
            return;
        }

        e.Cancel = true;
        Hide();
    }
}
