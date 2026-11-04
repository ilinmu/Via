namespace Via.Windows;

public sealed class MonitorService : IDisposable
{
    private const int PermissionAuthorized = 1;

    private readonly object _gate = new();
    private readonly CredentialStore _credentials;
    private readonly WifiService _wifi = new();
    private readonly SemaphoreSlim _wake = new(0, 1);

    private AppSettings _settings = new();
    private PolicyEngine? _policy;
    private CancellationTokenSource? _cts;
    private Task? _loop;
    private bool _running;
    private bool _disposed;
    private string _lastMessage = "";

    public MonitorService(CredentialStore credentials)
    {
        _credentials = credentials;
    }

    public bool IsRunning
    {
        get
        {
            lock (_gate)
            {
                return _running;
            }
        }
    }

    public event Action<MonitorStatus>? StatusChanged;
    public event Action<string>? Log;

    public void Configure(AppSettings settings)
    {
        lock (_gate)
        {
            _settings = settings.Clone();
            _settings.Normalize();
            _policy?.SetConfig(_settings.SsidP, _settings.SsidB);
        }
    }

    public void Start()
    {
        lock (_gate)
        {
            if (_disposed || _running || _loop is { IsCompleted: false })
            {
                return;
            }

            _settings.Normalize();
            _policy?.Dispose();
            _policy = new PolicyEngine(_settings.SsidP, _settings.SsidB);
            _cts = new CancellationTokenSource();
            _running = true;
            _lastMessage = L10n.T("monitor_started");

            var policy = _policy!;
            var token = _cts.Token;
            _loop = Task.Run(() => RunAsync(policy, token), token);
            Report(policy);
        }
    }

    public void Stop()
    {
        lock (_gate)
        {
            if (!_running)
            {
                return;
            }

            _running = false;
            _cts?.Cancel();
        }

        StatusChanged?.Invoke(new MonitorStatus(
            null,
            WifiRole.None,
            false,
            L10n.T("monitor_stopped"),
            null));
    }

    public void Refresh()
    {
        try
        {
            if (_wake.CurrentCount == 0)
            {
                _wake.Release();
            }
        }
        catch (ObjectDisposedException)
        {
            // Shutdown raced with a refresh click.
        }
    }

    public void Dispose()
    {
        lock (_gate)
        {
            if (_disposed)
            {
                return;
            }

            _disposed = true;
            _running = false;
            _cts?.Cancel();
        }

        try
        {
            _loop?.Wait(TimeSpan.FromSeconds(5));
        }
        catch
        {
            // Shutdown should never be blocked by a slow adapter.
        }

        _policy?.Dispose();
        _policy = null;
        _cts?.Dispose();
        _cts = null;
        _wake.Dispose();
    }

    private async Task RunAsync(PolicyEngine policy, CancellationToken token)
    {
        try
        {
            var current = _wifi.GetCurrentSsid();
            Execute(policy, policy.Start(PermissionAuthorized, current).Actions, token);
            var previous = current;

            while (!token.IsCancellationRequested)
            {
                var interval = Compat.Clamp(_settings.CheckInterval, 5, 3600);
                var delay = Task.Delay(TimeSpan.FromSeconds(interval), token);
                var wake = _wake.WaitAsync(token);
                await Task.WhenAny(delay, wake);

                if (token.IsCancellationRequested)
                {
                    break;
                }

                current = _wifi.GetCurrentSsid();
                var result = string.Equals(previous, current, StringComparison.Ordinal)
                    ? policy.CheckBegin(PermissionAuthorized, current)
                    : policy.ObservedChange(previous, current);
                previous = current;

                Execute(policy, result.Actions, token);
                Report(policy);

                if (!policy.Snapshot().Running)
                {
                    break;
                }
            }
        }
        catch (OperationCanceledException)
        {
            // Normal stop.
        }
        catch (Exception exception)
        {
            SetMessage(exception.Message);
        }
        finally
        {
            lock (_gate)
            {
                _running = false;
            }

            StatusChanged?.Invoke(new MonitorStatus(
                null,
                WifiRole.None,
                false,
                _lastMessage,
                null));
        }
    }

    private void Execute(
        PolicyEngine policy,
        IReadOnlyList<PolicyAction> actions,
        CancellationToken token)
    {
        foreach (var action in actions)
        {
            token.ThrowIfCancellationRequested();

            switch (action.Kind)
            {
                case PolicyActionKind.Scan:
                    ExecuteScan(policy, action, token);
                    break;

                case PolicyActionKind.Associate:
                    ExecuteAssociate(policy, action, token);
                    break;

                case PolicyActionKind.Stop:
                    SetMessage(StopText(action.Reason));
                    break;

                case PolicyActionKind.WaitForPermission:
                    SetMessage(L10n.T("waiting"));
                    break;

                case PolicyActionKind.Log:
                    SetMessage(LogText(action.Reason));
                    break;

                case PolicyActionKind.RefreshStatus:
                    Report(policy);
                    break;

                case PolicyActionKind.CheckNow:
                    break;
            }
        }
    }

    private void ExecuteScan(
        PolicyEngine policy,
        PolicyAction action,
        CancellationToken token)
    {
        var purpose = (PolicyScanPurpose)action.Purpose;
        var target = purpose switch
        {
            PolicyScanPurpose.PriorityCheck => _settings.SsidP,
            PolicyScanPurpose.PriorityClassification => _settings.SsidP,
            PolicyScanPurpose.BackupCheck => _settings.SsidB,
            PolicyScanPurpose.BackupFailover => _settings.SsidB,
            PolicyScanPurpose.BackupRecovery => _settings.SsidB,
            _ => ""
        };

        var found = _wifi.IsVisible(target);
        var next = purpose switch
        {
            PolicyScanPurpose.PriorityClassification => policy.ClassificationResult(found).Actions,
            PolicyScanPurpose.BackupFailover or PolicyScanPurpose.BackupRecovery =>
                policy.BackupScanResult(found).Actions,
            _ => policy.ScanResult(found).Actions
        };

        Execute(policy, next, token);
    }

    private void ExecuteAssociate(
        PolicyEngine policy,
        PolicyAction action,
        CancellationToken token)
    {
        var ssid = action.Ssid ?? "";
        if (string.IsNullOrWhiteSpace(ssid))
        {
            return;
        }

        var account = string.Equals(ssid, _settings.SsidP, StringComparison.Ordinal)
            ? "passwordP"
            : "passwordB";
        var password = _credentials.Load(account);
        var generation = policy.AssociationStarted(ssid);
        var connected = _wifi.Connect(ssid, password);

        if (!connected)
        {
            SetMessage($"{L10n.T("connect_failed")}: {ssid}");
        }

        Execute(
            policy,
            policy.AssociationResult(ssid, generation, connected ? 0 : 2).Actions,
            token);
    }

    private void Report(PolicyEngine policy)
    {
        var snapshot = policy.Snapshot();
        StatusChanged?.Invoke(new MonitorStatus(
            snapshot.CurrentSsid,
            (WifiRole)snapshot.Role,
            snapshot.Running,
            _lastMessage,
            snapshot.Running
                ? DateTimeOffset.Now.AddSeconds(Compat.Clamp(_settings.CheckInterval, 5, 3600))
                : null));
    }

    private void SetMessage(string message)
    {
        _lastMessage = message;
        Log?.Invoke(message);
    }

    private static string LogText(int eventCode)
    {
        var key = ((PolicyLogEvent)eventCode) switch
        {
            PolicyLogEvent.Started => "monitor_started",
            PolicyLogEvent.Stopped => "monitor_stopped",
            PolicyLogEvent.PriorityConnected => "role_priority",
            PolicyLogEvent.AutomaticFailover => "role_backup",
            _ => null
        };

        return key is null ? $"policy event {eventCode}" : L10n.T(key);
    }

    private static string StopText(int reasonCode)
    {
        return ((PolicyStopReason)reasonCode) switch
        {
            PolicyStopReason.NotConfigured => L10n.T("missing_primary"),
            PolicyStopReason.ManualOverrideBackup => L10n.T("monitor_stopped"),
            PolicyStopReason.ManualOverrideUnmanaged => L10n.T("monitor_stopped"),
            _ => L10n.T("monitor_stopped")
        };
    }
}
