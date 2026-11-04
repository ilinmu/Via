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

        var result = engine.ScanResult(found: false);

        var action = Assert.Single(result.Actions);
        Assert.Equal(PolicyActionKind.Scan, action.Kind);
        Assert.Equal((int)PolicyScanPurpose.BackupCheck, action.Purpose);
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
