package wifi

import (
	"context"
	"errors"
	"fmt"
	"io"
	"sync"
	"time"

	"via/internal/policy"
	"via/internal/store"
)

// TimingOptions controls settle, rescan, timeout, and manual-override windows.
type TimingOptions struct {
	SettleDelay          time.Duration
	RescanInterval       time.Duration
	RescanAttempts       int
	ManualVerifyDelay    time.Duration
	ManualVerifyInterval time.Duration
	ManualVerifyAttempts int
	AssociationTimeout   time.Duration
	Cooldown             time.Duration
	ProgrammaticWindow   time.Duration
}

// DefaultTimingOptions returns production timings aligned with Via's design.
func DefaultTimingOptions() TimingOptions {
	return TimingOptions{
		SettleDelay:          2 * time.Second,
		RescanInterval:       2 * time.Second,
		RescanAttempts:       3,
		ManualVerifyDelay:    25 * time.Second,
		ManualVerifyInterval: 3 * time.Second,
		ManualVerifyAttempts: 2,
		AssociationTimeout:   15 * time.Second,
		Cooldown:             90 * time.Second,
		ProgrammaticWindow:   15 * time.Second,
	}
}

// State is the immutable snapshot consumed by desktop, mobile, and CLI UIs.
type State struct {
	Running         bool
	Configured      bool
	Role            policy.Role
	Permission      policy.Permission
	CurrentSSID     string
	HasCurrentSSID  bool
	SSIDP           string
	SSIDB           string
	CheckInterval   int
	IsAssociating   bool
	Scanning        bool
	StopReason      policy.StopReason
	HasStopReason   bool
	NextCheckAt     time.Time
	Nearby          []Network
	LastEvent       string
	LastError       string
	AdvisoryMode    bool
	LastScanSuccess bool
}

// Monitor coordinates the deterministic policy.Engine against an OS Adapter,
// handling scan settle windows, manual-override verification, timers, and state publishing.
type Monitor struct {
	mu          sync.Mutex
	execMu      sync.Mutex // serializes state-machine actions and OS transitions
	adapter     Adapter
	secrets     store.SecretStore
	settings    store.Settings
	settingsDir string
	persist     bool
	timings     TimingOptions
	now         func() time.Time
	engine      *policy.Engine

	livePermission   policy.Permission
	liveSSID         string
	hasLiveSample    bool
	hasLastObserved  bool
	lastObservedSSID string
	nearby           []Network
	lastScan         []Network
	lastScanAt       time.Time
	scanning         bool
	stopReason       policy.StopReason
	hasStopReason    bool
	nextCheckAt      time.Time
	lastEvent        string
	lastErr          string

	watchCloser  io.Closer
	permCloser   io.Closer
	loopCancel   context.CancelFunc
	verifyCancel context.CancelFunc
	checkTrigger chan struct{}
	listeners    map[uint64]func(State)
	nextListener uint64
}

// NewMonitor creates a Monitor backed by adapter, initial settings, and secrets.
func NewMonitor(adapter Adapter, secrets store.SecretStore, initial store.Settings, settingsDir string, timings TimingOptions) *Monitor {
	initial = initial.Normalize()
	if timings.RescanAttempts <= 0 {
		timings.RescanAttempts = 1
	}
	if timings.ManualVerifyAttempts <= 0 {
		timings.ManualVerifyAttempts = 1
	}
	if timings.AssociationTimeout <= 0 {
		timings.AssociationTimeout = 15 * time.Second
	}
	eng := policy.NewWithTimings(
		policy.Config{SSIDP: initial.SSIDP, SSIDB: initial.SSIDB},
		uint64(timings.AssociationTimeout.Milliseconds()),
		uint64(timings.Cooldown.Milliseconds()),
		uint64(timings.ProgrammaticWindow.Milliseconds()),
	)
	return &Monitor{
		adapter:        adapter,
		secrets:        secrets,
		settings:       initial,
		settingsDir:    settingsDir,
		persist:        settingsDir != "",
		timings:        timings,
		now:            time.Now,
		engine:         eng,
		livePermission: policy.PermissionUnknown,
		checkTrigger:   make(chan struct{}, 4),
		listeners:      make(map[uint64]func(State)),
	}
}

func (m *Monitor) nowMs() uint64 {
	return uint64(m.now().UnixMilli())
}

// Adapter returns the underlying platform Adapter.
func (m *Monitor) Adapter() Adapter {
	return m.adapter
}

// Subscribe registers a listener notified whenever Monitor's State changes.
func (m *Monitor) Subscribe(fn func(State)) func() {
	m.mu.Lock()
	m.nextListener++
	id := m.nextListener
	m.listeners[id] = fn
	m.mu.Unlock()
	return func() {
		m.mu.Lock()
		delete(m.listeners, id)
		m.mu.Unlock()
	}
}

func (m *Monitor) emit() {
	st := m.State()
	m.mu.Lock()
	cbs := make([]func(State), 0, len(m.listeners))
	for _, fn := range m.listeners {
		cbs = append(cbs, fn)
	}
	m.mu.Unlock()
	for _, fn := range cbs {
		fn(st)
	}
	if m.adapter != nil && m.adapter.IsAdvisory() {
		title := st.CurrentSSID
		if title == "" {
			title = "Via"
		}
		m.adapter.UpdateNotification(st.Running, title, st.Role.String())
	}
}

// State builds an immutable UI snapshot of current monitoring & hardware state.
func (m *Monitor) State() State {
	m.mu.Lock()
	defer m.mu.Unlock()
	snap := m.engine.Snapshot()
	nearbyCopy := append([]Network(nil), m.nearby...)

	currentSSID := snap.CurrentSSID
	hasSSID := snap.HasCurrentSSID
	role := snap.Role
	perm := snap.Permission
	if m.hasLiveSample || !snap.Running {
		perm = m.livePermission
		currentSSID = m.liveSSID
		hasSSID = m.liveSSID != ""
		var ptr *string
		if hasSSID {
			ptr = &currentSSID
		}
		role = m.engine.RoleFor(ptr)
	}

	return State{
		Running:         snap.Running,
		Configured:      m.settings.IsConfigured(),
		Role:            role,
		Permission:      perm,
		CurrentSSID:     currentSSID,
		HasCurrentSSID:  hasSSID,
		SSIDP:           m.settings.SSIDP,
		SSIDB:           m.settings.SSIDB,
		CheckInterval:   m.settings.CheckIntervalSec,
		IsAssociating:   snap.IsAssociating,
		Scanning:        m.scanning,
		StopReason:      m.stopReason,
		HasStopReason:   m.hasStopReason,
		NextCheckAt:     m.nextCheckAt,
		Nearby:          nearbyCopy,
		LastEvent:       m.lastEvent,
		LastError:       m.lastErr,
		AdvisoryMode:    m.adapter != nil && m.adapter.IsAdvisory(),
		LastScanSuccess: !m.lastScanAt.IsZero(),
	}
}

// Settings returns a copy of current settings.
func (m *Monitor) Settings() store.Settings {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.settings
}

// Init queries initial OS state, subscribes to Wi-Fi SSID & permission change events, and resumes if enabled.
func (m *Monitor) Init(ctx context.Context) {
	m.RefreshStatus(ctx)
	if m.adapter != nil {
		if c, err := m.adapter.SubscribeChanges(func(ssid string) {
			go m.HandleObservedSSIDChange(ssid)
		}); err == nil && c != nil {
			m.mu.Lock()
			m.watchCloser = c
			m.mu.Unlock()
		}
		if pc, err := m.adapter.SubscribePermissionChanges(func(perm policy.Permission) {
			go func() {
				m.RefreshStatus(context.Background())
				if perm == policy.PermissionAuthorized {
					m.mu.Lock()
					shouldStart := m.settings.IsRunning && m.settings.IsConfigured()
					m.mu.Unlock()
					if shouldStart {
						m.Start()
					}
				} else {
					if m.State().Running {
						m.Stop()
					}
				}
			}()
		}); err == nil && pc != nil {
			m.mu.Lock()
			m.permCloser = pc
			m.mu.Unlock()
		}
	}
	m.mu.Lock()
	shouldStart := m.settings.IsRunning && m.settings.IsConfigured()
	m.mu.Unlock()
	if shouldStart {
		m.Start()
	}
}

// Close shuts down background loops and event subscriptions.
func (m *Monitor) Close() {
	m.mu.Lock()
	cancel := m.loopCancel
	m.loopCancel = nil
	vCancel := m.verifyCancel
	m.verifyCancel = nil
	wc := m.watchCloser
	m.watchCloser = nil
	pc := m.permCloser
	m.permCloser = nil
	m.mu.Unlock()
	if cancel != nil {
		cancel()
	}
	if vCancel != nil {
		vCancel()
	}
	if wc != nil {
		_ = wc.Close()
	}
	if pc != nil {
		_ = pc.Close()
	}
}

// RefreshStatus reads OS permission and current SSID without altering running state.
func (m *Monitor) RefreshStatus(ctx context.Context) {
	if m.adapter == nil {
		return
	}
	perm := m.adapter.Permission(ctx)
	ssid, err := m.adapter.CurrentSSID(ctx)

	m.mu.Lock()
	m.livePermission = perm
	m.liveSSID = ssid
	m.hasLiveSample = true
	if perm != policy.PermissionAuthorized {
		m.nearby = nil
	}
	m.engine.SetConfig(m.settings.SSIDP, m.settings.SSIDB)
	if err != nil {
		m.lastErr = err.Error()
	} else {
		m.lastErr = ""
	}
	m.mu.Unlock()
	m.emit()
}

// RequestPermission asks the OS for location/Wi-Fi authorization.
func (m *Monitor) RequestPermission() error {
	if m.adapter == nil {
		return nil
	}
	return m.adapter.RequestPermission()
}

// OpenPermissionSettings opens system privacy settings for authorization.
func (m *Monitor) OpenPermissionSettings() error {
	if m.adapter == nil {
		return nil
	}
	return m.adapter.OpenPermissionSettings()
}

// Start activates automatic switching and begins periodic + event-driven checks.
func (m *Monitor) Start() {
	m.execMu.Lock()
	defer m.execMu.Unlock()
	m.startLocked(context.Background())
}

func (m *Monitor) startLocked(ctx context.Context) {
	m.cancelVerificationLocked()

	m.mu.Lock()
	cfg := m.settings
	m.mu.Unlock()

	var perm policy.Permission
	var ssid string
	if m.adapter != nil {
		perm = m.adapter.Permission(ctx)
		ssid, _ = m.adapter.CurrentSSID(ctx)
	}

	m.mu.Lock()
	m.livePermission = perm
	m.liveSSID = ssid
	m.hasLiveSample = true
	m.lastObservedSSID = ssid
	m.hasLastObserved = true
	m.hasStopReason = false
	m.engine.SetConfig(cfg.SSIDP, cfg.SSIDB)

	if perm != policy.PermissionAuthorized {
		_ = m.engine.Stop()
		m.settings.IsRunning = false
		m.nextCheckAt = time.Time{}
		m.lastErr = "location permission required"
		m.persistSettingsLocked()
		m.mu.Unlock()
		m.emit()
		return
	}

	actions := m.engine.Start(m.nowMs(), perm, optSSIDPtr(ssid))
	snap := m.engine.Snapshot()
	if snap.Running {
		m.settings.IsRunning = true
		m.nextCheckAt = m.now().Add(time.Duration(m.settings.CheckIntervalSec) * time.Second)
	} else {
		m.settings.IsRunning = false
		m.nextCheckAt = time.Time{}
	}
	m.persistSettingsLocked()
	if snap.Running {
		m.ensureLoopLocked()
	}
	m.mu.Unlock()

	m.executeActions(ctx, actions)
	m.emit()
}

// Stop halts automatic switching.
func (m *Monitor) Stop() {
	m.execMu.Lock()
	defer m.execMu.Unlock()
	m.stopLocked(false, 0)
}

func (m *Monitor) stopLocked(hasReason bool, reason policy.StopReason) {
	m.mu.Lock()
	cancel := m.loopCancel
	m.loopCancel = nil
	if !hasReason {
		m.cancelVerificationLocked()
	}
	_ = m.engine.Stop()
	m.settings.IsRunning = false
	m.nextCheckAt = time.Time{}
	m.stopReason = reason
	m.hasStopReason = hasReason
	m.persistSettingsLocked()
	m.mu.Unlock()
	if cancel != nil {
		cancel()
	}
	m.emit()
}

// ToggleRunning switches between active guard and paused state.
func (m *Monitor) ToggleRunning() {
	if m.State().Running {
		m.Stop()
	} else {
		m.Start()
	}
}

// CheckNow triggers an immediate policy evaluation cycle.
func (m *Monitor) CheckNow() {
	m.execMu.Lock()
	defer m.execMu.Unlock()
	m.checkOnceLocked(context.Background())
}

func (m *Monitor) checkOnceLocked(ctx context.Context) {
	if m.adapter == nil {
		return
	}
	perm := m.adapter.Permission(ctx)
	ssid, err := m.adapter.CurrentSSID(ctx)

	m.mu.Lock()
	m.livePermission = perm
	m.liveSSID = ssid
	m.hasLiveSample = true
	if err != nil {
		m.lastErr = err.Error()
	} else {
		m.lastErr = ""
	}
	if !m.engine.Snapshot().Running {
		m.mu.Unlock()
		m.emit()
		return
	}
	m.lastObservedSSID = ssid
	m.hasLastObserved = true
	m.nextCheckAt = m.now().Add(time.Duration(m.settings.CheckIntervalSec) * time.Second)
	actions := m.engine.CheckBegin(m.nowMs(), perm, optSSIDPtr(ssid))
	m.mu.Unlock()

	m.executeActions(ctx, actions)
	m.emit()
}

// HandleObservedSSIDChange feeds an OS SSID transition event into the state machine.
func (m *Monitor) HandleObservedSSIDChange(newSSID string) {
	m.execMu.Lock()
	defer m.execMu.Unlock()

	m.mu.Lock()
	m.liveSSID = newSSID
	m.hasLiveSample = true
	if !m.engine.Snapshot().Running {
		m.lastObservedSSID = newSSID
		m.hasLastObserved = true
		m.mu.Unlock()
		m.emit()
		return
	}
	var prevPtr *string
	if m.hasLastObserved && m.lastObservedSSID != "" {
		p := m.lastObservedSSID
		prevPtr = &p
	}
	m.lastObservedSSID = newSSID
	m.hasLastObserved = true
	actions := m.engine.ObservedChange(prevPtr, optSSIDPtr(newSSID), m.nowMs())
	m.mu.Unlock()

	m.executeActions(context.Background(), actions)
	m.emit()
}

func (m *Monitor) executeActions(ctx context.Context, actions []policy.Action) {
	for len(actions) > 0 {
		act := actions[0]
		actions = actions[1:]

		switch act.Kind {
		case policy.ActionLog:
			m.mu.Lock()
			m.lastEvent = formatLogEvent(act.Event)
			m.mu.Unlock()

		case policy.ActionRefreshStatus:
			// Handled on emit at outer caller.

		case policy.ActionWaitForPermission:
			m.mu.Lock()
			m.lastEvent = formatLogEvent(policy.LogPermissionRequired)
			m.mu.Unlock()

		case policy.ActionStop:
			m.stopLocked(true, act.Reason)
			if act.Reason == policy.StopManualOverrideBackup || act.Reason == policy.StopManualOverrideUnmanaged {
				m.scheduleManualOverrideVerification()
			}
			return

		case policy.ActionCheckNow:
			m.checkOnceLocked(ctx)
			return

		case policy.ActionScan:
			next := m.performPolicyScan(ctx, act.Purpose)
			actions = append(next, actions...)

		case policy.ActionAssociate:
			next := m.performPolicyAssociate(ctx, act.SSID)
			actions = append(next, actions...)
		}
	}
}

func (m *Monitor) performPolicyScan(ctx context.Context, purpose policy.ScanPurpose) []policy.Action {
	m.mu.Lock()
	cfg := m.settings
	m.scanning = true
	m.mu.Unlock()
	m.emit()

	defer func() {
		m.mu.Lock()
		m.scanning = false
		m.mu.Unlock()
	}()

	switch purpose {
	case policy.ScanPriorityCheck:
		found := m.scanVisibility(ctx, cfg.SSIDP)
		m.mu.Lock()
		defer m.mu.Unlock()
		return m.engine.ScanResult(found, m.nowMs())

	case policy.ScanBackupCheck:
		found := m.scanVisibility(ctx, cfg.SSIDB)
		m.mu.Lock()
		defer m.mu.Unlock()
		return m.engine.ScanResult(found, m.nowMs())

	case policy.ScanPriorityClassification:
		vis := m.confirmPriorityVisibility(ctx, cfg.SSIDP)
		m.mu.Lock()
		defer m.mu.Unlock()
		return m.engine.ClassificationResult(vis, m.nowMs())

	case policy.ScanBackupFailover, policy.ScanBackupRecovery:
		found := m.scanVisibility(ctx, cfg.SSIDB)
		m.mu.Lock()
		defer m.mu.Unlock()
		return m.engine.BackupScanResult(found, m.nowMs())
	}
	return nil
}

// scanVisibility scans once and returns *bool (nil if scan errored or returned 0 networks).
func (m *Monitor) scanVisibility(ctx context.Context, targetSSID string) *bool {
	if m.adapter == nil || targetSSID == "" {
		return nil
	}
	nets, err := m.adapter.Scan(ctx)
	if err != nil || len(nets) == 0 {
		return nil
	}
	m.mu.Lock()
	m.nearby = nets
	m.lastScan = nets
	m.lastScanAt = m.now()
	m.mu.Unlock()

	found := false
	for _, n := range nets {
		if n.SSID == targetSSID {
			found = true
			break
		}
	}
	return &found
}

// confirmPriorityVisibility waits a brief settle window and runs multiple rescans so a
// cached OS scan right after P disappears never misclassifies loss as manual override.
func (m *Monitor) confirmPriorityVisibility(ctx context.Context, ssidP string) *bool {
	if m.timings.SettleDelay > 0 {
		select {
		case <-ctx.Done():
			return nil
		case <-time.After(m.timings.SettleDelay):
		}
	}
	anyValid := false
	for i := 0; i < m.timings.RescanAttempts; i++ {
		if i > 0 && m.timings.RescanInterval > 0 {
			select {
			case <-ctx.Done():
				return nil
			case <-time.After(m.timings.RescanInterval):
			}
		}
		vis := m.scanVisibility(ctx, ssidP)
		if vis == nil {
			continue
		}
		anyValid = true
		if !*vis {
			f := false
			return &f
		}
	}
	if !anyValid {
		return nil
	}
	t := true
	return &t
}

func (m *Monitor) scheduleManualOverrideVerification() {
	m.mu.Lock()
	m.cancelVerificationLocked()
	vCtx, cancel := context.WithCancel(context.Background())
	m.verifyCancel = cancel
	delay := m.timings.ManualVerifyDelay
	attempts := m.timings.ManualVerifyAttempts
	interval := m.timings.ManualVerifyInterval
	m.mu.Unlock()

	go func() {
		if delay > 0 {
			select {
			case <-vCtx.Done():
				return
			case <-time.After(delay):
			}
		}
		if vCtx.Err() != nil {
			return
		}
		m.execMu.Lock()
		defer m.execMu.Unlock()

		m.mu.Lock()
		running := m.engine.Snapshot().Running
		reason := m.stopReason
		hasReason := m.hasStopReason
		ssidP := m.settings.SSIDP
		m.mu.Unlock()

		if running || !hasReason || (reason != policy.StopManualOverrideBackup && reason != policy.StopManualOverrideUnmanaged) {
			return
		}

		// Re-verify whether P is genuinely still visible. If all valid scans
		// show P gone, it was a stale-cache false positive; auto-resume!
		anyValid := false
		stillVisible := false
		for i := 0; i < attempts; i++ {
			if i > 0 && interval > 0 {
				select {
				case <-vCtx.Done():
					return
				case <-time.After(interval):
				}
			}
			vis := m.scanVisibility(vCtx, ssidP)
			if vis == nil {
				continue
			}
			anyValid = true
			if *vis {
				stillVisible = true
				break
			}
		}
		if anyValid && !stillVisible && vCtx.Err() == nil {
			m.startLocked(context.Background())
		}
	}()
}

func (m *Monitor) performPolicyAssociate(ctx context.Context, ssid string) []policy.Action {
	if m.adapter == nil {
		return nil
	}

	m.mu.Lock()
	cfg := m.settings
	gen := m.engine.AssociationStarted(ssid, m.nowMs())
	advisory := m.adapter.IsAdvisory()
	timeout := m.timings.AssociationTimeout
	m.mu.Unlock()
	m.emit()

	pwdP, _ := m.secrets.Get(store.SecretKeyPriority)
	pwdB, _ := m.secrets.Get(store.SecretKeyBackup)
	targetPwd := pwdP
	if ssid == cfg.SSIDB {
		targetPwd = pwdB
	}

	if advisory {
		_ = m.adapter.ApplyAdvisory(cfg.SSIDP, pwdP, cfg.SSIDB, pwdB, ssid)
		m.mu.Lock()
		defer m.mu.Unlock()
		return m.engine.AssociationResult(ssid, gen, policy.OutcomeAdvisoryEnded, m.nowMs())
	}

	connCtx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	errCh := make(chan error, 1)
	go func() {
		errCh <- m.adapter.Connect(connCtx, ssid, targetPwd)
	}()

	var outcome policy.AssociationOutcome
	select {
	case err := <-errCh:
		if err != nil {
			outcome = policy.OutcomeFailure
			m.mu.Lock()
			m.lastErr = err.Error()
			m.mu.Unlock()
		} else {
			cur, curErr := m.adapter.CurrentSSID(ctx)
			m.mu.Lock()
			if curErr == nil {
				m.liveSSID = cur
				m.hasLiveSample = true
			}
			m.mu.Unlock()
			if cur == ssid {
				outcome = policy.OutcomeSuccess
			} else {
				outcome = policy.OutcomeFailure
				m.mu.Lock()
				m.lastErr = fmt.Sprintf("OS stayed on %q instead of %q", cur, ssid)
				m.mu.Unlock()
			}
		}
	case <-time.After(timeout):
		outcome = policy.OutcomeTimeout
		go func() {
			lateErr := <-errCh
			m.execMu.Lock()
			defer m.execMu.Unlock()
			m.mu.Lock()
			acts := m.engine.LateAssociationResult(ssid, gen, lateErr == nil, m.nowMs())
			m.mu.Unlock()
			if len(acts) > 0 {
				m.executeActions(context.Background(), acts)
				m.emit()
			}
		}()
	}

	m.mu.Lock()
	defer m.mu.Unlock()
	return m.engine.AssociationResult(ssid, gen, outcome, m.nowMs())
}

// ScanNearby triggers a manual UI scan of nearby Wi-Fi networks.
func (m *Monitor) ScanNearby(ctx context.Context) ([]Network, error) {
	if m.adapter == nil {
		return nil, nil
	}
	if perm := m.adapter.Permission(ctx); perm != policy.PermissionAuthorized {
		m.mu.Lock()
		m.livePermission = perm
		m.hasLiveSample = true
		m.nearby = nil
		m.lastErr = "location permission required"
		m.mu.Unlock()
		m.emit()
		return nil, errors.New("location permission required")
	}

	m.mu.Lock()
	m.scanning = true
	m.mu.Unlock()
	m.emit()

	nets, err := m.adapter.Scan(ctx)
	m.mu.Lock()
	m.scanning = false
	if err == nil {
		m.nearby = nets
		m.lastScan = nets
		m.lastScanAt = m.now()
		m.lastErr = ""
	} else {
		m.lastErr = err.Error()
	}
	m.mu.Unlock()
	m.emit()
	return nets, err
}

// ConnectNow initiates an explicit user-triggered switch to slot ("P" or "B").
func (m *Monitor) ConnectNow(ctx context.Context, slot string) error {
	if m.adapter == nil {
		return nil
	}
	if perm := m.adapter.Permission(ctx); perm != policy.PermissionAuthorized {
		m.mu.Lock()
		m.livePermission = perm
		m.hasLiveSample = true
		m.lastErr = "location permission required"
		m.mu.Unlock()
		m.emit()
		return errors.New("location permission required")
	}

	m.mu.Lock()
	cfg := m.settings
	m.mu.Unlock()

	ssid := cfg.SSIDP
	key := store.SecretKeyPriority
	if slot == store.SlotBackup {
		ssid = cfg.SSIDB
		key = store.SecretKeyBackup
	}
	if ssid == "" {
		return store.ErrEmptySSID
	}
	pwd, _ := m.secrets.Get(key)

	if m.adapter.IsAdvisory() {
		pwdP, _ := m.secrets.Get(store.SecretKeyPriority)
		pwdB, _ := m.secrets.Get(store.SecretKeyBackup)
		err := m.adapter.ApplyAdvisory(cfg.SSIDP, pwdP, cfg.SSIDB, pwdB, ssid)
		m.RefreshStatus(ctx)
		return err
	}
	err := m.adapter.Connect(ctx, ssid, pwd)
	m.RefreshStatus(ctx)
	if err != nil {
		m.mu.Lock()
		m.lastErr = err.Error()
		m.mu.Unlock()
		m.emit()
		return err
	}
	cur, _ := m.adapter.CurrentSSID(ctx)
	if cur != ssid {
		err = fmt.Errorf("Wi-Fi stayed on %q instead of switching to %q", cur, ssid)
		m.mu.Lock()
		m.lastErr = err.Error()
		m.mu.Unlock()
		m.emit()
		return err
	}
	return nil
}

// SaveSlot saves one slot (P or B) without overwriting the other slot's password.
func (m *Monitor) SaveSlot(slot, ssid, password string) error {
	m.execMu.Lock()
	defer m.execMu.Unlock()

	m.mu.Lock()
	s := m.settings
	dir := m.settingsDir
	m.mu.Unlock()

	if err := store.SaveSlot(dir, m.secrets, &s, slot, ssid, password); err != nil {
		return err
	}

	m.mu.Lock()
	m.settings = s
	m.engine.SetConfig(s.SSIDP, s.SSIDB)
	wasRunning := m.engine.Snapshot().Running
	m.mu.Unlock()

	if m.adapter != nil && m.adapter.IsAdvisory() && s.IsConfigured() {
		pwdP, _ := m.secrets.Get(store.SecretKeyPriority)
		pwdB, _ := m.secrets.Get(store.SecretKeyBackup)
		_ = m.adapter.ApplyAdvisory(s.SSIDP, pwdP, s.SSIDB, pwdB, "")
	}

	if wasRunning {
		m.checkOnceLocked(context.Background())
	} else {
		m.emit()
	}
	return nil
}

// SwapSlots swaps Primary and Backup SSIDs and stored passwords.
func (m *Monitor) SwapSlots() error {
	m.execMu.Lock()
	defer m.execMu.Unlock()

	m.mu.Lock()
	s := m.settings
	dir := m.settingsDir
	m.mu.Unlock()

	pwdP, pwdB, err := store.SwapSlots(dir, m.secrets, &s)
	if err != nil {
		return err
	}

	m.mu.Lock()
	m.settings = s
	m.engine.SetConfig(s.SSIDP, s.SSIDB)
	wasRunning := m.engine.Snapshot().Running
	m.mu.Unlock()

	if m.adapter != nil && m.adapter.IsAdvisory() && s.IsConfigured() {
		_ = m.adapter.ApplyAdvisory(s.SSIDP, pwdP, s.SSIDB, pwdB, "")
	}

	if wasRunning {
		m.checkOnceLocked(context.Background())
	} else {
		m.emit()
	}
	return nil
}

// SetInterval updates CheckIntervalSec (clamped 5..3600) and reschedules timer.
func (m *Monitor) SetInterval(sec int) (bool, error) {
	clamped, adjusted := store.NormalizeInterval(sec)
	m.mu.Lock()
	m.settings.CheckIntervalSec = clamped
	m.persistSettingsLocked()
	if m.engine.Snapshot().Running {
		m.nextCheckAt = m.now().Add(time.Duration(clamped) * time.Second)
	}
	running := m.engine.Snapshot().Running
	m.mu.Unlock()

	if running {
		select {
		case m.checkTrigger <- struct{}{}:
		default:
		}
	}
	m.emit()
	return adjusted, nil
}

// SetLanguage updates and persists UI language ("", "zh", "en").
func (m *Monitor) SetLanguage(lang string) {
	m.mu.Lock()
	m.settings.Language = lang
	m.persistSettingsLocked()
	m.mu.Unlock()
	m.emit()
}

// SetOnboardingDone marks onboarding completed and persists settings.
func (m *Monitor) SetOnboardingDone(done bool) {
	m.mu.Lock()
	m.settings.OnboardingDone = done
	m.persistSettingsLocked()
	m.mu.Unlock()
	m.emit()
}

// SetBootRestore updates Android boot-restore setting and persists it.
func (m *Monitor) SetBootRestore(on bool) {
	m.mu.Lock()
	m.settings.BootRestore = on
	m.persistSettingsLocked()
	m.mu.Unlock()
	m.emit()
}

// LoadPassword reads the stored password for slot ("P" or "B").
func (m *Monitor) LoadPassword(slot string) (string, error) {
	if m.secrets == nil {
		return "", nil
	}
	return m.secrets.Get(store.SecretKeyForSlot(slot))
}

func (m *Monitor) persistSettingsLocked() {
	if !m.persist {
		return
	}
	_ = store.SaveSettings(m.settingsDir, m.settings)
}

func (m *Monitor) cancelVerificationLocked() {
	if m.verifyCancel != nil {
		m.verifyCancel()
		m.verifyCancel = nil
	}
}

func (m *Monitor) ensureLoopLocked() {
	if m.loopCancel != nil {
		return
	}
	ctx, cancel := context.WithCancel(context.Background())
	m.loopCancel = cancel
	go m.runLoop(ctx)
}

func (m *Monitor) runLoop(ctx context.Context) {
	for {
		m.mu.Lock()
		interval := time.Duration(m.settings.CheckIntervalSec) * time.Second
		if interval < time.Second {
			interval = time.Second
		}
		m.mu.Unlock()

		timer := time.NewTimer(interval)
		select {
		case <-ctx.Done():
			timer.Stop()
			return
		case <-m.checkTrigger:
			timer.Stop()
			// Interval updated; loop picks up new interval cleanly.
		case <-timer.C:
			m.CheckNow()
		}
	}
}

func optSSIDPtr(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}

func formatLogEvent(ev policy.LogEvent) string {
	switch ev {
	case policy.LogPriorityConnected:
		return "Connected to Primary"
	case policy.LogPriorityVisibleWaiting:
		return "Disconnected while Primary is visible; waiting"
	case policy.LogNetworkDisconnectedWaiting:
		return "Wi-Fi disconnected; waiting"
	case policy.LogAutomaticFailover:
		return "Automatic failover to Backup"
	case policy.LogPriorityLostConnectingBackup:
		return "Primary unavailable; switching to Backup"
	case policy.LogBackupConnectedPNotFound:
		return "On Backup; Primary not visible"
	case policy.LogNeitherFound:
		return "Neither Primary nor Backup visible"
	case policy.LogBackupNotFound:
		return "Backup network not found"
	case policy.LogBackupNotFoundWaiting:
		return "Backup not visible; waiting"
	case policy.LogPreviousBackupReconnect:
		return "Previous backup observed; switching to current Backup"
	case policy.LogSystemJoinedBackup:
		return "System joined Backup while Primary unavailable"
	case policy.LogTreatingAsFallback:
		return "Primary unavailable; recovering Backup"
	case policy.LogCooldownSkipped:
		return "Cooldown active; skipping association"
	case policy.LogAssociationSuccess:
		return "Association succeeded"
	case policy.LogAssociationTimeout:
		return "Association timed out"
	case policy.LogAssociationFailure:
		return "Association failed"
	case policy.LogAssociationLateSuccess:
		return "Late association succeeded"
	case policy.LogAssociationLateFailure:
		return "Late association failed"
	case policy.LogPermissionRequired:
		return "Location/Wi-Fi permission required"
	case policy.LogPriorityVisibleUnknown:
		return "Scan unavailable; keeping current state"
	default:
		return ""
	}
}
