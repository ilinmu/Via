using Xunit;

namespace Via.Windows.Tests;

public sealed class PolicyEngineTests
{
    private const int Authorized = 1;

    [Fact]
    public void StartingOnPriorityRefreshesStatus()
    {
        using var engine = new PolicyEngine("NetworkP", "NetworkB");

        var result = engine.Start(Authorized, "NetworkP");

        Assert.Equal(
            new[] { PolicyActionKind.RefreshStatus },
            result.Actions.Select(a => a.Kind));
        Assert.True(result.Snapshot.Running);
        Assert.Equal("NetworkP", result.Snapshot.CurrentSsid);
        Assert.Equal((int)WifiRole.Priority, result.Snapshot.Role);
        Assert.Equal(Authorized, result.Snapshot.Permission);
    }

    [Fact]
    public void StartingAwayFromPriorityScansForIt()
    {
        using var engine = new PolicyEngine("NetworkP", "NetworkB");

        var result = engine.Start(Authorized, "SomeOtherNetwork");

        var action = Assert.Single(result.Actions);
        Assert.Equal(PolicyActionKind.Scan, action.Kind);
        Assert.Equal((int)PolicyScanPurpose.PriorityCheck, action.Purpose);
        Assert.True(result.Snapshot.Running);
    }

    [Fact]
    public void MissingConfigurationStopsMonitoring()
    {
        using var engine = new PolicyEngine("NetworkP", "");

        var result = engine.Start(Authorized, "NetworkP");

        var action = Assert.Single(result.Actions);
        Assert.Equal(PolicyActionKind.Stop, action.Kind);
        Assert.Equal((int)PolicyStopReason.NotConfigured, action.Reason);
        Assert.False(result.Snapshot.Running);
    }

    [Fact]
    public void StopClearsRunningState()
    {
        using var engine = new PolicyEngine("NetworkP", "NetworkB");
        _ = engine.Start(Authorized, "NetworkP");

        var result = engine.Stop();

        Assert.Empty(result.Actions);
        Assert.False(result.Snapshot.Running);
    }

    [Fact]
    public void ScanResultForMissingPriorityRequestsBackupScan()
    {
        using var engine = new PolicyEngine("NetworkP", "NetworkB");
        _ = engine.Start(Authorized, "SomeOtherNetwork");

        var result = engine.ScanResult(found: (bool?)false);

        var action = Assert.Single(result.Actions);
        Assert.Equal(PolicyActionKind.Scan, action.Kind);
        Assert.Equal((int)PolicyScanPurpose.BackupCheck, action.Purpose);
    }

    [Fact]
    public void ObservedChangeSupersedesAnInFlightScan()
    {
        using var engine = new PolicyEngine("NetworkP", "NetworkB");
        _ = engine.Start(Authorized, "SomeOtherNetwork");

        var observed = engine.ObservedChange("NetworkP", "NetworkB");
        var stale = engine.ScanResult(found: true);

        Assert.Equal(
            new[] { PolicyActionKind.Scan },
            observed.Actions.Select(a => a.Kind));
        Assert.Equal(
            (int)PolicyScanPurpose.PriorityClassification,
            observed.Actions[0].Purpose);
        Assert.Empty(stale.Actions);
        var classification = engine.ClassificationResult(priorityVisible: false);
        Assert.Contains(
            classification.Actions,
            a => a.Kind == PolicyActionKind.CheckNow);
    }

    [Fact]
    public void UnknownScanKeepsMonitoringWithoutAnotherAction()
    {
        using var engine = new PolicyEngine("NetworkP", "NetworkB");
        _ = engine.Start(Authorized, "NetworkP");
        _ = engine.ObservedChange("NetworkP", null);

        var result = engine.ScanResult(found: null);

        var action = Assert.Single(result.Actions);
        Assert.Equal(PolicyActionKind.Log, action.Kind);
        Assert.Equal((int)PolicyLogEvent.PriorityVisibleUnknown, action.Reason);
        Assert.True(result.Snapshot.Running);
    }

    [Fact]
    public void AdvisoryAssociationEndsWithoutCooldown()
    {
        using var engine = new PolicyEngine("NetworkP", "NetworkB");
        _ = engine.Start(Authorized, "NetworkP");
        var generation = engine.AssociationStarted("NetworkP");

        var result = engine.AssociationResult("NetworkP", generation, outcome: 3);

        Assert.False(result.Snapshot.IsAssociating);
        Assert.Equal(0, result.Snapshot.CooldownUntilMs);
        Assert.True(result.Snapshot.Running);
    }

    [Fact]
    public void SetConfigUpdatesAcceptance()
    {
        using var engine = new PolicyEngine("OldP", "OldB");
        _ = engine.Start(Authorized, "NetworkP");

        engine.SetConfig("NetworkP", "NetworkB");
        var result = engine.CheckBegin(Authorized, "NetworkP");

        var action = Assert.Single(result.Actions);
        Assert.Equal(PolicyActionKind.RefreshStatus, action.Kind);
    }
}
