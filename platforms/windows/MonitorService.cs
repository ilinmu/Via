namespace Via.Windows;

public sealed class MonitorService : IDisposable
{
    private const int PermissionAuthorized = 1;
    private const int MaxConsecutiveFailures = 5;
    private static readonly TimeSpan RetryBaseDelay = TimeSpan.FromSeconds(2);
    private static readonly TimeSpan RetryMaxDelay = TimeSpan.FromSeconds(30);
    private static readonly TimeSpan HealthyRunThreshold = TimeSpan.FromMinutes(1);

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
        Task? previous;
        lock (_gate)
        {
            if (_disposed || _running)
            {
                return;
            }
            previous = _loop;
        }

        // A stop/start toggle can arrive while the cancelled worker is still
        // finishing a native call. Let it exit instead of silently refusing to
        // start a new loop; cancellation-aware waits keep this bounded.
        if (previous is { IsCompleted: false })
        {
            try
            {
                previous.Wait(TimeSpan.FromSeconds(3));
            }
            catch (Exception exception) when (
                exception is AggregateException or ObjectDisposedException)
            {
                // Start will retry only if the old loop has actually finished.
            }
        }

        lock (_gate)
        {
            if (_disposed || _running || _loop is { IsCompleted: false })
            {
                return;
            }

            _settings.Normalize();
            WlanApi.EnsureNotifications();
            _policy?.Dispose();
            _policy = null;
            _cts?.Dispose();
            _cts = new CancellationTokenSource();
            _running = true;
            _lastMessage = L10n.T("monitor_started");

            var token = _cts.Token;
            // The worker creates and owns its policy engine so a failed loop
            // can be restarted with a fresh engine without racing the UI.
            _loop = Task.Run(() => RunAsync(token), token);
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
        lock (_gate)
        {
            if (_disposed)
            {
                return;
            }
        }

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
        Task? loop;
        CancellationTokenSource? cts;
        lock (_gate)
        {
            if (_disposed)
            {
                return;
            }

            _disposed = true;
            _running = false;
            _cts?.Cancel();
            loop = _loop;
            cts = _cts;
        }

        var completed = true;
        try
        {
            completed = loop?.Wait(TimeSpan.FromSeconds(5)) ?? true;
        }
        catch (Exception exception) when (
            exception is AggregateException or ObjectDisposedException)
        {
            // Shutdown should never be blocked by a slow adapter.
        }

        if (!completed)
        {
            // The worker may still be in a native call. Leaving its policy,
            // CTS and semaphore alive is safer than disposing objects it is
            // using; the process is exiting and will reclaim them.
            return;
        }

        PolicyEngine? policy;
        lock (_gate)
        {
            policy = _policy;
            _policy = null;
            if (ReferenceEquals(_cts, cts))
            {
                _cts = null;
            }
        }
        policy?.Dispose();
        cts?.Dispose();
        _wake.Dispose();
    }

    private async Task RunAsync(CancellationToken token)
    {
        var consecutiveFailures = 0;
        var retryDelay = RetryBaseDelay;

        try
        {
            while (!token.IsCancellationRequested)
            {
                PolicyEngine? policy = null;
                var attemptStarted = DateTime.UtcNow;
                try
                {
                    var settings = CurrentSettings();
                    policy = new PolicyEngine(settings.SsidP, settings.SsidB);
                    lock (_gate)
                    {
                        _policy = policy;
                    }
                    await RunPolicyLoopAsync(policy, token);
                    return;
                }
                catch (OperationCanceledException) when (token.IsCancellationRequested)
                {
                    // Normal stop.
                    return;
                }
                catch (Exception exception)
                {
                    if (_disposed || token.IsCancellationRequested)
                    {
                        return;
                    }

                    if (DateTime.UtcNow - attemptStarted >= HealthyRunThreshold)
                    {
                        consecutiveFailures = 0;
                        retryDelay = RetryBaseDelay;
                    }
                    consecutiveFailures++;

                    if (consecutiveFailures >= MaxConsecutiveFailures)
                    {
                        ReportFatal(exception);
                        return;
                    }

                    ReportRestarting(exception, retryDelay);
                    try
                    {
                        await Task.Delay(retryDelay, token);
                    }
                    catch (OperationCanceledException)
                    {
                        return;
                    }
                    retryDelay = TimeSpan.FromSeconds(Math.Min(
                        RetryMaxDelay.TotalSeconds,
                        retryDelay.TotalSeconds * 2));
                }
                finally
                {
                    lock (_gate)
                    {
                        if (ReferenceEquals(_policy, policy))
                        {
                            _policy = null;
                        }
                    }
                    policy?.Dispose();
                }
            }
        }
        finally
        {
            lock (_gate)
            {
                _running = false;
            }
        }
    }

    private async Task RunPolicyLoopAsync(PolicyEngine policy, CancellationToken token)
    {
        var current = _wifi.GetCurrentSsid();
        Execute(policy, policy.Start(PermissionAuthorized, current).Actions, token);
        if (token.IsCancellationRequested)
        {
            return;
        }
        if (!policy.Snapshot().Running)
        {
            Report(policy);
            return;
        }
        Report(policy);
        var previous = current;

        while (!token.IsCancellationRequested)
        {
            var settings = CurrentSettings();
            var interval = Compat.Clamp(settings.CheckInterval, 5, 3600);
            var delay = Task.Delay(TimeSpan.FromSeconds(interval), token);
            var wake = _wake.WaitAsync(token);
            await Task.WhenAny(delay, wake);

            if (token.IsCancellationRequested)
            {
                break;
            }

            current = _wifi.GetCurrentSsid();
            var transitions = _wifi.TakeTransitions();
            PolicyResult result;
            if (transitions.Length > 0)
            {
                // Deliver the oldest real transitions first so a fast
                // P → disconnected → B sequence is not compressed.
                foreach (var transition in transitions.Take(8))
                {
                    var observed = policy.ObservedChange(transition.Previous, transition.Current);
                    Execute(policy, observed.Actions, token);
                    if (!policy.Snapshot().Running)
                    {
                        break;
                    }
                }
                result = policy.CheckBegin(PermissionAuthorized, current);
            }
            else
            {
                result = string.Equals(previous, current, StringComparison.Ordinal)
                    ? policy.CheckBegin(PermissionAuthorized, current)
                    : policy.ObservedChange(previous, current);
            }
            previous = current;

            if (policy.Snapshot().Running)
            {
                Execute(policy, result.Actions, token);
            }
            if (token.IsCancellationRequested)
            {
                break;
            }
            Report(policy);

            if (!policy.Snapshot().Running)
            {
                break;
            }
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
                    if (!IsManualOverride(action.Reason))
                    {
                        SetMessage(StopText(action.Reason));
                        break;
                    }

                    // A single stale cached scan can still list a lost P. Delay
                    // the classification and confirm it before persisting a stop.
                    if (token.WaitHandle.WaitOne(TimeSpan.FromSeconds(2)))
                    {
                        token.ThrowIfCancellationRequested();
                    }
                    var settings = CurrentSettings();
                    var confirmation = _wifi.IsVisible(settings.SsidP, token);
                    SetMessage(confirmation == true
                        ? StopText(action.Reason)
                        : L10n.T("monitor_started"));
                    if (confirmation != true)
                    {
                        var restarted = policy.Start(PermissionAuthorized, _wifi.GetCurrentSsid());
                        Execute(policy, restarted.Actions, token);
                    }
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
                    // A fresh check is enough to re-evaluate P/B; the outer loop
                    // schedules the next one after these actions complete.
                    break;
            }
        }
    }

    private void ExecuteScan(
        PolicyEngine policy,
        PolicyAction action,
        CancellationToken token)
    {
        var settings = CurrentSettings();
        var purpose = (PolicyScanPurpose)action.Purpose;
        var target = purpose switch
        {
            PolicyScanPurpose.PriorityCheck => settings.SsidP,
            PolicyScanPurpose.PriorityClassification => settings.SsidP,
            PolicyScanPurpose.BackupCheck => settings.SsidB,
            PolicyScanPurpose.BackupFailover => settings.SsidB,
            PolicyScanPurpose.BackupRecovery => settings.SsidB,
            _ => ""
        };

        var found = _wifi.IsVisible(target, token);
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

        var settings = CurrentSettings();
        var account = string.Equals(ssid, settings.SsidP, StringComparison.Ordinal)
            ? "passwordP"
            : "passwordB";
        var password = _credentials.Load(account);
        var generation = policy.AssociationStarted(ssid);
        var connected = _wifi.Connect(ssid, password, token);

        if (!connected)
        {
            SetMessage($"{L10n.T("connect_failed")}: {ssid}");
        }

        Execute(
            policy,
            policy.AssociationResult(ssid, generation, connected ? 0 : 2).Actions,
            token);
    }

    private void ReportRestarting(Exception exception, TimeSpan retryDelay)
    {
        var message = string.Format(
            L10n.T("monitor_restarting_format"),
            exception.Message,
            Math.Round(retryDelay.TotalSeconds));
        SetMessage(message);
        StatusChanged?.Invoke(new MonitorStatus(
            SafeCurrentSsid(),
            WifiRole.None,
            true,
            message,
            null,
            true));
    }

    private void ReportFatal(Exception exception)
    {
        var message = string.Format(L10n.T("monitor_failed_format"), exception.Message);
        SetMessage(message);
        StatusChanged?.Invoke(new MonitorStatus(
            SafeCurrentSsid(),
            WifiRole.None,
            false,
            message,
            null));
    }

    private void Report(PolicyEngine policy)
    {
        var snapshot = policy.Snapshot();
        var settings = CurrentSettings();
        StatusChanged?.Invoke(new MonitorStatus(
            snapshot.CurrentSsid,
            (WifiRole)snapshot.Role,
            snapshot.Running,
            _lastMessage,
            snapshot.Running
                ? DateTimeOffset.Now.AddSeconds(Compat.Clamp(settings.CheckInterval, 5, 3600))
                : null));
    }

    private AppSettings CurrentSettings()
    {
        lock (_gate)
        {
            return _settings.Clone();
        }
    }

    private string? SafeCurrentSsid()
    {
        try
        {
            return _wifi.GetCurrentSsid();
        }
        catch
        {
            return null;
        }
    }

    private void SetMessage(string message)
    {
        _lastMessage = message;
        Log?.Invoke(message);
    }

    private static bool IsManualOverride(int reasonCode) =>
        (PolicyStopReason)reasonCode is PolicyStopReason.ManualOverrideBackup
            or PolicyStopReason.ManualOverrideUnmanaged;

    private static string LogText(int eventCode)
    {
        var key = ((PolicyLogEvent)eventCode) switch
        {
            PolicyLogEvent.Started => "monitor_started",
            PolicyLogEvent.Stopped => "monitor_stopped",
            PolicyLogEvent.PriorityConnected => "role_priority",
            PolicyLogEvent.AutomaticFailover => "role_backup",
            PolicyLogEvent.PriorityVisibleUnknown => "scan_empty_unknown",
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
