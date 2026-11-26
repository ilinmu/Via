package policy

import (
	"reflect"
	"testing"
)

func strPtr(s string) *string { return &s }
func boolPtr(b bool) *bool   { return &b }
func u64Ptr(v uint64) *uint64 {
	return &v
}

func newTestEngine() *Engine {
	return NewWithTimings(Config{SSIDP: "P", SSIDB: "B"}, 1_000, 90_000, 15_000)
}

func pAssociate() Action { return Action{Kind: ActionAssociate, SSID: "P", Role: RolePriority} }
func bAssociate() Action { return Action{Kind: ActionAssociate, SSID: "B", Role: RoleBackup} }

func assertActions(t *testing.T, got, want []Action) {
	t.Helper()
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("actions mismatch:\n got:  %#v\n want: %#v", got, want)
	}
}

func TestMissingConfigurationStopsMonitoring(t *testing.T) {
	e := New(Config{})
	assertActions(t, e.Start(0, PermissionAuthorized, nil), []Action{{Kind: ActionStop, Reason: StopNotConfigured}})
	if e.Snapshot().Running {
		t.Fatal("expected engine not to run")
	}
}

func TestStartingOnPriorityOnlyRefreshes(t *testing.T) {
	e := newTestEngine()
	assertActions(t, e.Start(0, PermissionAuthorized, strPtr("P")), []Action{{Kind: ActionRefreshStatus}})
	snap := e.Snapshot()
	if !snap.Running || snap.Role != RolePriority {
		t.Fatalf("unexpected snapshot: %+v", snap)
	}
}

func TestPermissionDeniedKeepsSessionWaiting(t *testing.T) {
	e := newTestEngine()
	assertActions(t, e.Start(0, PermissionDenied, nil), []Action{{Kind: ActionWaitForPermission}})
	snap := e.Snapshot()
	if !snap.Running || snap.Permission != PermissionDenied {
		t.Fatalf("unexpected snapshot: %+v", snap)
	}
}

func TestRegularCheckScansPriorityThenAssociates(t *testing.T) {
	e := newTestEngine()
	assertActions(t, e.Start(0, PermissionAuthorized, strPtr("X")), []Action{{Kind: ActionScan, Purpose: ScanPriorityCheck}})
	assertActions(t, e.ScanResult(boolPtr(true), 10), []Action{pAssociate()})
}

func TestRegularCheckFallsBackToBackup(t *testing.T) {
	e := newTestEngine()
	e.Start(0, PermissionAuthorized, strPtr("X"))
	assertActions(t, e.ScanResult(boolPtr(false), 10), []Action{{Kind: ActionScan, Purpose: ScanBackupCheck}})
	assertActions(t, e.ScanResult(boolPtr(true), 20), []Action{bAssociate()})
}

func TestRegularCheckLogsWhenNeitherNetworkIsVisible(t *testing.T) {
	e := newTestEngine()
	e.Start(0, PermissionAuthorized, strPtr("X"))
	e.ScanResult(boolPtr(false), 10)
	assertActions(t, e.ScanResult(boolPtr(false), 20), []Action{{Kind: ActionLog, Event: LogNeitherFound}})
}

func TestCooldownForBackupDoesNotBlockPriority(t *testing.T) {
	e := newTestEngine()
	e.Start(0, PermissionAuthorized, strPtr("B"))
	e.SetPersistedCooldown(strPtr("B"), u64Ptr(100_000), 0)

	assertActions(t, e.CheckBegin(10, PermissionAuthorized, strPtr("B")), []Action{{Kind: ActionScan, Purpose: ScanPriorityCheck}})
	assertActions(t, e.ScanResult(boolPtr(true), 20), []Action{pAssociate()})
}

func TestAssociationTimeoutAppliesCooldownForSameTarget(t *testing.T) {
	e := newTestEngine()
	e.Start(0, PermissionAuthorized, nil)
	e.ScanResult(boolPtr(true), 10)
	gen := e.AssociationStarted("P", 20)

	assertActions(t, e.AssociationResult("P", gen, OutcomeTimeout, 30), []Action{
		{Kind: ActionLog, Event: LogAssociationTimeout},
		{Kind: ActionRefreshStatus},
	})
	if !e.CooldownActiveFor("P", 40) {
		t.Fatal("expected cooldown active for P")
	}
	if e.CooldownActiveFor("B", 40) {
		t.Fatal("expected cooldown NOT active for B")
	}

	e.CheckBegin(50, PermissionAuthorized, nil)
	assertActions(t, e.ScanResult(boolPtr(true), 60), []Action{{Kind: ActionLog, Event: LogCooldownSkipped}})
}

func TestManualSwitchToBackupWhilePriorityVisibleStops(t *testing.T) {
	e := newTestEngine()
	e.Start(0, PermissionAuthorized, strPtr("P"))

	assertActions(t, e.ObservedChange(strPtr("P"), strPtr("B"), 10), []Action{{Kind: ActionScan, Purpose: ScanPriorityClassification}})
	assertActions(t, e.ClassificationResult(boolPtr(true), 20), []Action{
		{Kind: ActionStop, Reason: StopManualOverrideBackup},
		{Kind: ActionRefreshStatus},
	})
	if e.Snapshot().Running {
		t.Fatal("expected stopped after manual switch to backup")
	}
}

func TestProgrammaticBackupChangeKeepsMonitoring(t *testing.T) {
	e := newTestEngine()
	e.Start(0, PermissionAuthorized, strPtr("X"))
	e.ScanResult(boolPtr(false), 10)
	e.ScanResult(boolPtr(true), 20)
	gen := e.AssociationStarted("B", 30)

	assertActions(t, e.ObservedChange(strPtr("X"), strPtr("B"), 40), []Action{
		{Kind: ActionLog, Event: LogAutomaticFailover},
		{Kind: ActionCheckNow},
	})
	e.AssociationResult("B", gen, OutcomeSuccess, 50)
	snap := e.Snapshot()
	if !snap.Running || snap.Role != RoleBackup {
		t.Fatalf("unexpected snapshot: %+v", snap)
	}
}

func TestDisconnectFromPriorityWaitsWhenPriorityIsStillVisible(t *testing.T) {
	e := newTestEngine()
	e.Start(0, PermissionAuthorized, strPtr("P"))

	assertActions(t, e.ObservedChange(strPtr("P"), nil, 10), []Action{{Kind: ActionScan, Purpose: ScanPriorityClassification}})
	assertActions(t, e.ClassificationResult(boolPtr(true), 20), []Action{
		{Kind: ActionLog, Event: LogPriorityVisibleWaiting},
		{Kind: ActionRefreshStatus},
	})
}

func TestDisconnectFromPriorityFailsOverWhenPriorityIsGone(t *testing.T) {
	e := newTestEngine()
	e.Start(0, PermissionAuthorized, strPtr("P"))

	e.ObservedChange(strPtr("P"), nil, 10)
	assertActions(t, e.ClassificationResult(boolPtr(false), 20), []Action{
		{Kind: ActionLog, Event: LogPriorityLostConnectingBackup},
		{Kind: ActionScan, Purpose: ScanBackupFailover},
	})
	assertActions(t, e.BackupScanResult(boolPtr(true), 30), []Action{bAssociate()})
}

func TestUnmanagedNetworkWhilePriorityVisibleStops(t *testing.T) {
	e := newTestEngine()
	e.Start(0, PermissionAuthorized, strPtr("P"))

	assertActions(t, e.ObservedChange(strPtr("P"), strPtr("CoffeeShop"), 10), []Action{{Kind: ActionScan, Purpose: ScanPriorityClassification}})
	assertActions(t, e.ClassificationResult(boolPtr(true), 20), []Action{
		{Kind: ActionStop, Reason: StopManualOverrideUnmanaged},
		{Kind: ActionRefreshStatus},
	})
	if e.Snapshot().Running {
		t.Fatal("expected stopped after manual unmanaged switch")
	}
}

func TestUnmanagedNetworkWithoutPriorityRecoversBackup(t *testing.T) {
	e := newTestEngine()
	e.Start(0, PermissionAuthorized, strPtr("P"))

	e.ObservedChange(strPtr("P"), strPtr("CoffeeShop"), 10)
	assertActions(t, e.ClassificationResult(boolPtr(false), 20), []Action{
		{Kind: ActionLog, Event: LogTreatingAsFallback},
		{Kind: ActionScan, Purpose: ScanBackupRecovery},
	})
	assertActions(t, e.BackupScanResult(boolPtr(true), 30), []Action{bAssociate()})
}

func TestUnknownScanDoesNotFailOverOrStop(t *testing.T) {
	e := newTestEngine()
	e.Start(0, PermissionAuthorized, strPtr("P"))

	assertActions(t, e.ObservedChange(strPtr("P"), nil, 10), []Action{{Kind: ActionScan, Purpose: ScanPriorityClassification}})
	assertActions(t, e.ClassificationResult(nil, 20), []Action{
		{Kind: ActionLog, Event: LogPriorityVisibleUnknown},
		{Kind: ActionRefreshStatus},
	})
	if !e.Snapshot().Running {
		t.Fatal("expected running after unknown scan")
	}
}

func TestRegularCheckSupersedesStaleClassificationAndBackupResults(t *testing.T) {
	e := newTestEngine()
	e.Start(0, PermissionAuthorized, strPtr("P"))

	assertActions(t, e.ObservedChange(strPtr("P"), nil, 10), []Action{{Kind: ActionScan, Purpose: ScanPriorityClassification}})
	assertActions(t, e.CheckBegin(20, PermissionAuthorized, strPtr("X")), []Action{{Kind: ActionScan, Purpose: ScanPriorityCheck}})
	assertActions(t, e.ClassificationResult(boolPtr(false), 30), nil)
	assertActions(t, e.BackupScanResult(boolPtr(true), 40), nil)
	assertActions(t, e.ScanResult(boolPtr(true), 50), []Action{pAssociate()})
}

func TestUnknownScanAfterFailingOverKeepsMonitoring(t *testing.T) {
	e := newTestEngine()
	e.Start(0, PermissionAuthorized, strPtr("P"))
	e.ObservedChange(strPtr("P"), nil, 10)
	e.ClassificationResult(boolPtr(false), 20)
	assertActions(t, e.BackupScanResult(nil, 30), []Action{
		{Kind: ActionLog, Event: LogPriorityVisibleUnknown},
		{Kind: ActionRefreshStatus},
	})
	if !e.Snapshot().Running {
		t.Fatal("expected running")
	}
}

func TestObservedChangeWhileScanningClassifiesNewConnection(t *testing.T) {
	e := newTestEngine()
	e.Start(0, PermissionAuthorized, strPtr("X"))
	assertActions(t, e.CheckBegin(10, PermissionAuthorized, strPtr("X")), []Action{{Kind: ActionScan, Purpose: ScanPriorityCheck}})

	assertActions(t, e.ObservedChange(strPtr("P"), strPtr("B"), 20), []Action{{Kind: ActionScan, Purpose: ScanPriorityClassification}})
	assertActions(t, e.ScanResult(boolPtr(true), 30), nil)
	assertActions(t, e.ClassificationResult(boolPtr(false), 40), []Action{
		{Kind: ActionLog, Event: LogSystemJoinedBackup},
		{Kind: ActionCheckNow},
	})
	if !e.Snapshot().Running {
		t.Fatal("expected running")
	}
}

func TestObservedTransitionToPrioritySupersedesStaleScan(t *testing.T) {
	e := newTestEngine()
	e.Start(0, PermissionAuthorized, strPtr("X"))

	assertActions(t, e.ObservedChange(strPtr("B"), strPtr("P"), 10), []Action{
		{Kind: ActionLog, Event: LogPriorityConnected},
		{Kind: ActionRefreshStatus},
	})
	assertActions(t, e.ScanResult(boolPtr(true), 20), nil)
}

func TestRegularCheckOnPrioritySupersedesStaleScan(t *testing.T) {
	e := newTestEngine()
	e.Start(0, PermissionAuthorized, strPtr("X"))

	assertActions(t, e.CheckBegin(10, PermissionAuthorized, strPtr("P")), []Action{{Kind: ActionRefreshStatus}})
	assertActions(t, e.ScanResult(boolPtr(true), 20), nil)
}

func TestAdvisoryAssociationEndsWithoutCooldown(t *testing.T) {
	e := newTestEngine()
	e.Start(0, PermissionAuthorized, nil)
	e.ScanResult(boolPtr(true), 10)
	gen := e.AssociationStarted("P", 20)
	assertActions(t, e.AssociationResult("P", gen, OutcomeAdvisoryEnded, 30), []Action{{Kind: ActionRefreshStatus}})
	if e.CooldownActiveFor("P", 40) {
		t.Fatal("advisory association should not trigger cooldown")
	}
	if e.Snapshot().IsAssociating || !e.Snapshot().Running {
		t.Fatalf("unexpected snapshot: %+v", e.Snapshot())
	}
}

func TestConfigurationChangeDuringScanNeverUsesStaleTarget(t *testing.T) {
	e := newTestEngine()
	e.Start(0, PermissionAuthorized, nil)
	e.SetConfig("P2", "B")

	assertActions(t, e.ScanResult(boolPtr(true), 10), []Action{{Kind: ActionCheckNow}})

	e.CheckBegin(20, PermissionAuthorized, nil)
	assertActions(t, e.ScanResult(boolPtr(true), 30), []Action{{Kind: ActionAssociate, SSID: "P2", Role: RolePriority}})
}

func TestSwitchingToPreviousBackupReconnectsCurrentBackup(t *testing.T) {
	e := newTestEngine()
	e.Start(0, PermissionAuthorized, strPtr("P"))
	e.SetConfig("P", "B2")

	assertActions(t, e.ObservedChange(strPtr("P"), strPtr("B"), 10), []Action{
		{Kind: ActionLog, Event: LogPreviousBackupReconnect},
		{Kind: ActionScan, Purpose: ScanBackupRecovery},
	})
	assertActions(t, e.BackupScanResult(boolPtr(true), 20), []Action{{Kind: ActionAssociate, SSID: "B2", Role: RoleBackup}})
}

func TestLateAssociationSuccessClearsCooldownAndKeepsMonitoring(t *testing.T) {
	e := newTestEngine()
	e.Start(0, PermissionAuthorized, strPtr("X"))
	e.ScanResult(boolPtr(false), 10)
	e.ScanResult(boolPtr(true), 20)
	gen := e.AssociationStarted("B", 30)

	e.AssociationResult("B", gen, OutcomeTimeout, 40)
	if !e.CooldownActiveFor("B", 50) {
		t.Fatal("expected cooldown active for B")
	}

	assertActions(t, e.LateAssociationResult("B", gen, true, 60), []Action{
		{Kind: ActionLog, Event: LogAssociationLateSuccess},
		{Kind: ActionRefreshStatus},
	})
	if e.CooldownActiveFor("B", 70) {
		t.Fatal("expected cooldown cleared")
	}
	snap := e.Snapshot()
	if snap.Role != RoleBackup || !snap.Running {
		t.Fatalf("unexpected snapshot: %+v", snap)
	}
}

func TestStopInvalidatesInFlightAssociation(t *testing.T) {
	e := newTestEngine()
	e.Start(0, PermissionAuthorized, strPtr("P"))
	gen := e.AssociationStarted("P", 10)
	e.Stop()

	assertActions(t, e.AssociationResult("P", gen, OutcomeSuccess, 20), nil)
	if e.Snapshot().Running {
		t.Fatal("expected stopped")
	}
}

func TestRolesFollowConfiguredSlots(t *testing.T) {
	e := newTestEngine()
	if e.RoleFor(strPtr("P")) != RolePriority {
		t.Fatal("expected priority")
	}
	if e.RoleFor(strPtr("B")) != RoleBackup {
		t.Fatal("expected backup")
	}
	if e.RoleFor(strPtr("Other")) != RoleOther {
		t.Fatal("expected other")
	}
	if e.RoleFor(nil) != RoleNone {
		t.Fatal("expected none")
	}
}
