package wifi

import (
	"context"
	"errors"
	"io"
	"sync"
	"testing"
	"time"

	"via/internal/policy"
	"via/internal/store"
)

type fakeAdapter struct {
	mu           sync.Mutex
	perm         policy.Permission
	currentSSID  string
	scanQueue    [][]Network
	scanErr      error
	connectCalls []string
	connectErr   error
	connectFn    func(ssid string) error
	keepSSID     bool
	advisory     bool
	advisoryCalls []string
	onChange     func(string)
}

func (f *fakeAdapter) Name() string { return "fake" }
func (f *fakeAdapter) CurrentSSID(_ context.Context) (string, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.currentSSID, nil
}
func (f *fakeAdapter) Permission(_ context.Context) policy.Permission {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.perm
}
func (f *fakeAdapter) RequestPermission() error      { return nil }
func (f *fakeAdapter) OpenPermissionSettings() error { return nil }
func (f *fakeAdapter) Scan(_ context.Context) ([]Network, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.scanErr != nil {
		return nil, f.scanErr
	}
	if len(f.scanQueue) == 0 {
		return nil, nil
	}
	if len(f.scanQueue) == 1 {
		return f.scanQueue[0], nil
	}
	out := f.scanQueue[0]
	f.scanQueue = f.scanQueue[1:]
	return out, nil
}
func (f *fakeAdapter) Connect(_ context.Context, ssid, _ string) error {
	f.mu.Lock()
	f.connectCalls = append(f.connectCalls, ssid)
	fn := f.connectFn
	connErr := f.connectErr
	keepSSID := f.keepSSID
	f.mu.Unlock()
	if fn != nil {
		return fn(ssid)
	}
	if connErr != nil {
		return connErr
	}
	if !keepSSID {
		f.mu.Lock()
		f.currentSSID = ssid
		f.mu.Unlock()
	}
	return nil
}
func (f *fakeAdapter) SubscribeChanges(onChange func(string)) (io.Closer, error) {
	f.mu.Lock()
	f.onChange = onChange
	f.mu.Unlock()
	return nopCloser{}, nil
}
func (f *fakeAdapter) SubscribePermissionChanges(_ func(policy.Permission)) (io.Closer, error) {
	return nopCloser{}, nil
}
func (f *fakeAdapter) IsAdvisory() bool { return f.advisory }
func (f *fakeAdapter) ApplyAdvisory(_, _, _, _, prefer string) error {
	f.mu.Lock()
	f.advisoryCalls = append(f.advisoryCalls, prefer)
	f.mu.Unlock()
	return nil
}
func (f *fakeAdapter) UpdateNotification(_ bool, _, _ string) {}

func fastTimings() TimingOptions {
	return TimingOptions{
		SettleDelay:          0,
		RescanInterval:       0,
		RescanAttempts:       3,
		ManualVerifyDelay:    15 * time.Millisecond,
		ManualVerifyInterval: 0,
		ManualVerifyAttempts: 2,
		AssociationTimeout:   200 * time.Millisecond,
		Cooldown:             5 * time.Second,
		ProgrammaticWindow:   5 * time.Second,
	}
}

func TestMonitorFailoverAndPrimaryRecovery(t *testing.T) {
	dir := t.TempDir()
	sec := store.NewMemSecretStore()
	_ = sec.Set(store.SecretKeyPriority, "passP")
	_ = sec.Set(store.SecretKeyBackup, "passB")

	fa := &fakeAdapter{
		perm:        policy.PermissionAuthorized,
		currentSSID: "OtherNet",
		scanQueue: [][]Network{
			{{SSID: "B", RSSI: -55, Secured: true}}, // P not visible
			{{SSID: "B", RSSI: -55, Secured: true}}, // B visible -> connect B
		},
	}
	cfg := store.Settings{SSIDP: "P", SSIDB: "B", CheckIntervalSec: 60}
	m := NewMonitor(fa, sec, cfg, dir, fastTimings())
	defer m.Close()

	m.Start()
	st := m.State()
	if !st.Running || st.CurrentSSID != "B" || st.Role != policy.RoleBackup {
		t.Fatalf("expected connected to backup B, got %+v", st)
	}

	// Now P returns on next check.
	fa.mu.Lock()
	fa.scanQueue = [][]Network{{{SSID: "P", RSSI: -45, Secured: true}}}
	fa.mu.Unlock()
	m.CheckNow()
	st = m.State()
	if st.CurrentSSID != "P" || st.Role != policy.RolePriority {
		t.Fatalf("expected recovered to P, got %+v", st)
	}
}

func TestMonitorEmptyScanNeverCausesFalseFailover(t *testing.T) {
	fa := &fakeAdapter{
		perm:        policy.PermissionAuthorized,
		currentSSID: "Other",
		scanErr:     errors.New("throttled"),
	}
	cfg := store.Settings{SSIDP: "P", SSIDB: "B", CheckIntervalSec: 60}
	m := NewMonitor(fa, store.NewMemSecretStore(), cfg, "", fastTimings())
	defer m.Close()

	m.Start()
	if len(fa.connectCalls) != 0 {
		t.Fatalf("unexpected connect on scan failure: %v", fa.connectCalls)
	}
}

func TestMonitorStaleCacheRescanAndManualOverrideRecovery(t *testing.T) {
	fa := &fakeAdapter{
		perm:        policy.PermissionAuthorized,
		currentSSID: "P",
		// First scan still shows cached P (stale), second & third show P gone.
		scanQueue: [][]Network{
			{{SSID: "P", RSSI: -60}, {SSID: "B", RSSI: -65}},
			{{SSID: "B", RSSI: -65}},
			{{SSID: "B", RSSI: -65}},
		},
	}
	cfg := store.Settings{SSIDP: "P", SSIDB: "B", CheckIntervalSec: 60}
	m := NewMonitor(fa, store.NewMemSecretStore(), cfg, "", fastTimings())
	defer m.Close()

	m.Start()
	fa.mu.Lock()
	fa.currentSSID = "B"
	fa.mu.Unlock()
	m.HandleObservedSSIDChange("B")

	st := m.State()
	if !st.Running {
		t.Fatalf("expected stale cache on 1st rescan NOT to trigger manual stop: %+v", st)
	}
}

func TestMonitorFalsePositiveManualStopAutoResumes(t *testing.T) {
	fa := &fakeAdapter{
		perm:        policy.PermissionAuthorized,
		currentSSID: "P",
		// All 3 immediate scans show P (manual stop triggers), then delayed verification finds P gone!
		scanQueue: [][]Network{
			{{SSID: "P", RSSI: -60}, {SSID: "Coffee", RSSI: -50}},
			{{SSID: "P", RSSI: -60}, {SSID: "Coffee", RSSI: -50}},
			{{SSID: "P", RSSI: -60}, {SSID: "Coffee", RSSI: -50}},
			{{SSID: "Coffee", RSSI: -50}}, // verify 1: P gone
			{{SSID: "Coffee", RSSI: -50}}, // verify 2: P gone -> auto-resume
			{{SSID: "B", RSSI: -65}},      // after resume CheckBegin scans P (gone) & B (found)
			{{SSID: "B", RSSI: -65}},
		},
	}
	cfg := store.Settings{SSIDP: "P", SSIDB: "B", CheckIntervalSec: 60}
	m := NewMonitor(fa, store.NewMemSecretStore(), cfg, "", fastTimings())
	defer m.Close()

	m.Start()
	fa.mu.Lock()
	fa.currentSSID = "Coffee"
	fa.mu.Unlock()
	m.HandleObservedSSIDChange("Coffee")

	if m.State().Running {
		t.Fatal("expected initial manual override stop when all 3 scans saw P")
	}

	deadline := time.Now().Add(500 * time.Millisecond)
	for time.Now().Before(deadline) {
		if m.State().Running {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	if !m.State().Running {
		t.Fatal("expected delayed verification to auto-resume after P disappeared")
	}
}

func TestMonitorConnectDoesNotFakeSuccessWhenRadioDoesNotSwitch(t *testing.T) {
	fa := &fakeAdapter{
		perm:        policy.PermissionAuthorized,
		currentSSID: "OtherNet",
		keepSSID:    true,
		scanQueue: [][]Network{
			{{SSID: "B", RSSI: -55, Secured: true}},
			{{SSID: "B", RSSI: -55, Secured: true}},
		},
	}
	cfg := store.Settings{SSIDP: "P", SSIDB: "B", CheckIntervalSec: 60}
	m := NewMonitor(fa, store.NewMemSecretStore(), cfg, "", fastTimings())
	defer m.Close()

	m.Start()
	st := m.State()
	if st.Role == policy.RoleBackup || st.CurrentSSID == "B" {
		t.Fatalf("expected honest SSID OtherNet when radio refused to switch, got %+v", st)
	}
	if err := m.ConnectNow(context.Background(), store.SlotBackup); err == nil {
		t.Fatal("expected ConnectNow error when OS stayed on OtherNet")
	}
}

func TestMonitorStartRefusesWhenUnauthorized(t *testing.T) {
	fa := &fakeAdapter{
		perm:        policy.PermissionDenied,
		currentSSID: "",
	}
	cfg := store.Settings{SSIDP: "P", SSIDB: "B", CheckIntervalSec: 60}
	m := NewMonitor(fa, store.NewMemSecretStore(), cfg, "", fastTimings())
	defer m.Close()

	m.Start()
	if m.State().Running {
		t.Fatal("expected Monitor not to run while permission denied")
	}
}

func TestMonitorFailedPriorityConnectDoesNotTriggerManualOverrideAndStopClearsError(t *testing.T) {
	fa := &fakeAdapter{
		perm:        policy.PermissionAuthorized,
		currentSSID: "B",
		scanQueue: [][]Network{
			{{SSID: "P", RSSI: -45}, {SSID: "B", RSSI: -60}},
		},
	}
	fa.connectFn = func(ssid string) error {
		if fa.onChange != nil {
			fa.onChange("")
			fa.onChange("B")
		}
		return errors.New("Wi-Fi driver busy while connecting to " + ssid + " (tmpErr)")
	}
	cfg := store.Settings{SSIDP: "P", SSIDB: "B", CheckIntervalSec: 60}
	m := NewMonitor(fa, store.NewMemSecretStore(), cfg, "", fastTimings())
	defer m.Close()

	m.Init(context.Background())
	m.Start()
	time.Sleep(40 * time.Millisecond)

	st := m.State()
	if !st.Running {
		t.Fatalf("expected Monitor to stay running after failed P connect, got %+v", st)
	}
	if st.HasStopReason {
		t.Fatalf("expected no stop reason after failed P connect, got %v", st.StopReason)
	}
	if st.LastError == "" {
		t.Fatal("expected LastError to record failed P connect")
	}

	m.Stop()
	st = m.State()
	if st.Running {
		t.Fatal("expected Monitor to stop cleanly")
	}
	if st.LastError != "" {
		t.Fatalf("expected explicit Stop to clear LastError, got %q", st.LastError)
	}
}
