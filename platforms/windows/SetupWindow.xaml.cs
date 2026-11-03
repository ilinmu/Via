using System.Windows;

namespace AutoWifi.Windows;

/// <summary>
/// First-run wizard. Windows needs no location permission, so the steps are
/// welcome, networks and finish.
/// </summary>
public partial class SetupWindow : Window
{
    private readonly AppSettings _settings;
    private readonly CredentialStore _credentials = new();
    private readonly WifiService _wifi = new();
    private int _step;

    /// <summary>True when the user asked to start monitoring on the last step.</summary>
    public bool StartRequested { get; private set; }

    public SetupWindow(AppSettings settings)
    {
        InitializeComponent();

        _settings = settings.Clone();
        PriorityCombo.Text = _settings.SsidP;
        BackupCombo.Text = _settings.SsidB;
        PriorityPassword.Password = _credentials.Load("passwordP") ?? "";
        BackupPassword.Password = _credentials.Load("passwordB") ?? "";

        ApplyLanguage();
        UpdateStep();
    }

    private void ApplyLanguage()
    {
        Title = L10n.T("app_title");
        WizardTitle.Text = L10n.T("app_title");
        WelcomeTitle.Text = L10n.T("wizard_welcome_title");
        WelcomeBody.Text = L10n.T("wizard_welcome_body");
        NetworksTitle.Text = L10n.T("wizard_networks_title");
        NetworksBody.Text = L10n.T("wizard_networks_body");
        PriorityLabel.Text = L10n.T("priority_network");
        BackupLabel.Text = L10n.T("backup_network");
        PasswordHint.Text = L10n.T("password_optional");
        FinishTitle.Text = L10n.T("wizard_finish_title");
        FinishBody.Text = L10n.T("wizard_finish_body");
        FinishHint.Text = L10n.T("privacy_note");
        ScanButton.Content = L10n.T("scan_networks");
        BackButton.Content = L10n.T("wizard_back");
        SkipButton.Content = L10n.T("wizard_skip");
        NextButton.Content = L10n.T("wizard_next");
        SaveOnlyButton.Content = L10n.T("wizard_save_only");
        StartButton.Content = L10n.T("wizard_start");
    }

    private void UpdateStep()
    {
        StepWelcome.Visibility = _step == 0 ? Visibility.Visible : Visibility.Collapsed;
        StepNetworks.Visibility = _step == 1 ? Visibility.Visible : Visibility.Collapsed;
        StepFinish.Visibility = _step == 2 ? Visibility.Visible : Visibility.Collapsed;

        Progress.Value = _step + 1;
        StepText.Text = string.Format(L10n.T("wizard_step_format"), _step + 1);

        BackButton.Visibility = _step > 0 ? Visibility.Visible : Visibility.Collapsed;
        SkipButton.Visibility = _step < 2 ? Visibility.Visible : Visibility.Collapsed;
        NextButton.Visibility = _step < 2 ? Visibility.Visible : Visibility.Collapsed;
        SaveOnlyButton.Visibility = _step == 2 ? Visibility.Visible : Visibility.Collapsed;
        StartButton.Visibility = _step == 2 ? Visibility.Visible : Visibility.Collapsed;

        Validation.Text = "";
        if (_step == 2)
        {
            SummaryP.Text = $"{L10n.T("priority_network")}: {PriorityCombo.Text.Trim()}";
            SummaryB.Text = $"{L10n.T("backup_network")}: {BackupCombo.Text.Trim()}";
        }
    }

    private void Back_Click(object sender, RoutedEventArgs e)
    {
        if (_step == 0)
        {
            return;
        }

        _step -= 1;
        UpdateStep();
    }

    private void Next_Click(object sender, RoutedEventArgs e)
    {
        if (_step == 1 && !ValidateNetworks())
        {
            return;
        }

        if (_step < 2)
        {
            _step += 1;
            UpdateStep();
        }
    }

    private void Skip_Click(object sender, RoutedEventArgs e)
    {
        _settings.SetupCompleted = true;
        SettingsStore.Save(_settings);
        DialogResult = false;
    }

    private void SaveOnly_Click(object sender, RoutedEventArgs e)
    {
        Commit(start: false);
    }

    private void Start_Click(object sender, RoutedEventArgs e)
    {
        Commit(start: true);
    }

    private async void ScanButton_Click(object sender, RoutedEventArgs e)
    {
        ScanButton.IsEnabled = false;
        ScanStatus.Text = L10n.T("scanning");
        try
        {
            var networks = await Task.Run(() => _wifi.Scan());
            PriorityCombo.ItemsSource = networks;
            BackupCombo.ItemsSource = networks;
            ScanStatus.Text = networks.Count == 0
                ? L10n.T("no_networks")
                : string.Format(L10n.T("networks_found_format"), networks.Count);
        }
        finally
        {
            ScanButton.Content = L10n.T("scan_networks");
            ScanButton.IsEnabled = true;
        }
    }

    private bool ValidateNetworks()
    {
        var priority = PriorityCombo.Text.Trim();
        var backup = BackupCombo.Text.Trim();

        if (priority.Length == 0)
        {
            Validation.Text = L10n.T("missing_primary");
            return false;
        }

        if (backup.Length == 0)
        {
            Validation.Text = L10n.T("missing_backup");
            return false;
        }

        if (string.Equals(priority, backup, StringComparison.OrdinalIgnoreCase))
        {
            Validation.Text = L10n.T("same_network");
            return false;
        }

        Validation.Text = "";
        return true;
    }

    private void Commit(bool start)
    {
        if (!ValidateNetworks())
        {
            return;
        }

        _settings.SsidP = PriorityCombo.Text.Trim();
        _settings.SsidB = BackupCombo.Text.Trim();
        _settings.SetupCompleted = true;
        _settings.Running = start;

        try
        {
            _credentials.Save("passwordP", PriorityPassword.Password);
            _credentials.Save("passwordB", BackupPassword.Password);
            SettingsStore.Save(_settings);
        }
        catch (Exception exception)
        {
            Validation.Text = exception.Message;
            return;
        }

        StartRequested = start;
        DialogResult = true;
    }
}
