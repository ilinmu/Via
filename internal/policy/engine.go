package policy

const (
	DefaultAssociationTimeoutMs uint64 = 15_000
	DefaultCooldownMs           uint64 = 90_000
	DefaultProgrammaticWindowMs uint64 = 15_000
	// ProgrammaticGraceMs bounds how long a timed-out association's intent stays
	// attributable to Via if the OS finishes associating late.
	ProgrammaticGraceMs uint64 = 60_000
)

type configSnapshot struct {
	ssidP string
	ssidB string
}

type classificationContext int

const (
	classBackupChange classificationContext = iota
	classDisconnectFromPriority
	classUnmanagedChange
)

type pendingKind int

const (
	pendingNone pendingKind = iota
	pendingScan
	pendingClassification
	pendingFailover
	pendingRecovery
)

type pendingState struct {
	kind     pendingKind
	purpose  ScanPurpose
	config   configSnapshot
	classCtx classificationContext
}

type intent struct {
	ssid       string
	generation uint64
	deadlineMs uint64
}

type cooldownState struct {
	target  *string
	untilMs uint64
}

// Engine is Via's deterministic Wi-Fi failover and recovery state machine.
// Engine is not thread-safe on its own; callers serialize calls around it.
type Engine struct {
	config                      Config
	running                     bool
	permission                  Permission
	generation                  uint64
	isAssociating               bool
	currentSSID                 *string
	trackedBackupSSID           string
	previousBackupSSID          *string
	hasLastProgrammaticBackupAt bool
	lastProgrammaticBackupAtMs  uint64
	activeProgrammatic          *intent
	cooldown                    *cooldownState
	pending                     pendingState
	associationTimeoutMs        uint64
	cooldownMs                  uint64
	programmaticWindowMs        uint64
}

// New creates a policy Engine with production timings.
func New(cfg Config) *Engine {
	return NewWithTimings(cfg, DefaultAssociationTimeoutMs, DefaultCooldownMs, DefaultProgrammaticWindowMs)
}

// NewWithTimings creates a policy Engine with custom timings for platform
// adapters or deterministic tests.
func NewWithTimings(cfg Config, associationTimeoutMs, cooldownMs, programmaticWindowMs uint64) *Engine {
	return &Engine{
		config:               cfg,
		trackedBackupSSID:    cfg.SSIDB,
		permission:           PermissionUnknown,
		associationTimeoutMs: associationTimeoutMs,
		cooldownMs:           cooldownMs,
		programmaticWindowMs: programmaticWindowMs,
	}
}

// SetPersistedCooldown restores a persisted cooldown if it has not yet expired.
func (e *Engine) SetPersistedCooldown(target *string, untilMs *uint64, nowMs uint64) {
	if untilMs != nil && *untilMs > nowMs {
		var tgtCopy *string
		if target != nil {
			s := *target
			tgtCopy = &s
		}
		e.cooldown = &cooldownState{
			target:  tgtCopy,
			untilMs: *untilMs,
		}
		return
	}
	e.cooldown = nil
}

// SetConfig updates the configured Primary and Backup SSIDs.
func (e *Engine) SetConfig(ssidP, ssidB string) {
	e.config = Config{SSIDP: ssidP, SSIDB: ssidB}
	e.syncConfig()
}

// Start begins a monitoring session with the given permission and current SSID.
func (e *Engine) Start(nowMs uint64, perm Permission, currentSSID *string) []Action {
	e.permission = perm
	e.currentSSID = cloneStringPtr(currentSSID)
	e.syncConfig()

	if !e.config.IsComplete() {
		e.running = false
		return []Action{{Kind: ActionStop, Reason: StopNotConfigured}}
	}

	e.generation++
	e.isAssociating = false
	e.pending = pendingState{kind: pendingNone}
	e.activeProgrammatic = nil
	e.hasLastProgrammaticBackupAt = false
	e.cooldown = nil
	e.running = true

	if perm != PermissionAuthorized {
		return []Action{{Kind: ActionWaitForPermission}}
	}

	return e.CheckBegin(nowMs, perm, currentSSID)
}

// Stop halts monitoring and invalidates any in-flight generation.
func (e *Engine) Stop() []Action {
	e.enterStopped()
	return nil
}

// CheckBegin begins one periodic monitoring evaluation.
func (e *Engine) CheckBegin(_ uint64, perm Permission, currentSSID *string) []Action {
	if !e.running {
		return nil
	}

	// Any regular check supersedes an older pending scan/classification chain.
	e.pending = pendingState{kind: pendingNone}
	e.permission = perm
	e.currentSSID = cloneStringPtr(currentSSID)

	if perm != PermissionAuthorized {
		return []Action{{Kind: ActionWaitForPermission}}
	}
	if e.isAssociating {
		return nil
	}

	e.syncConfig()
	if !e.config.IsComplete() {
		e.running = false
		return []Action{{Kind: ActionStop, Reason: StopNotConfigured}}
	}

	if e.currentSSID != nil && *e.currentSSID == e.config.SSIDP {
		e.cooldown = nil
		return []Action{{Kind: ActionRefreshStatus}}
	}

	e.pending = pendingState{
		kind:    pendingScan,
		purpose: ScanPriorityCheck,
		config:  e.configSnapshot(),
	}
	return []Action{{Kind: ActionScan, Purpose: ScanPriorityCheck}}
}

// ScanResult feeds back the result of ActionScan(ScanPriorityCheck / ScanBackupCheck).
// Passing nil indicates visibility could not be reliably determined (e.g. scan throttled).
func (e *Engine) ScanResult(found *bool, nowMs uint64) []Action {
	pend := e.pending
	e.pending = pendingState{kind: pendingNone}
	if pend.kind != pendingScan {
		// Preserve newer pending work triggered by an intervening event.
		e.pending = pend
		return nil
	}

	if found == nil {
		return []Action{
			{Kind: ActionLog, Event: LogPriorityVisibleUnknown},
			{Kind: ActionRefreshStatus},
		}
	}

	if !e.configMatches(pend.config) {
		return []Action{{Kind: ActionCheckNow}}
	}

	switch pend.purpose {
	case ScanPriorityCheck:
		if *found {
			ssid := e.config.SSIDP
			if e.CooldownActiveFor(ssid, nowMs) {
				return []Action{{Kind: ActionLog, Event: LogCooldownSkipped}}
			}
			return []Action{{Kind: ActionAssociate, SSID: ssid, Role: RolePriority}}
		}
		e.pending = pendingState{
			kind:    pendingScan,
			purpose: ScanBackupCheck,
			config:  e.configSnapshot(),
		}
		return []Action{{Kind: ActionScan, Purpose: ScanBackupCheck}}

	case ScanBackupCheck:
		currentIsBackup := e.currentSSID != nil && *e.currentSSID == e.config.SSIDB
		if *found && !currentIsBackup {
			ssid := e.config.SSIDB
			if e.CooldownActiveFor(ssid, nowMs) {
				return []Action{{Kind: ActionLog, Event: LogCooldownSkipped}}
			}
			return []Action{{Kind: ActionAssociate, SSID: ssid, Role: RoleBackup}}
		}
		if *found && currentIsBackup {
			return []Action{{Kind: ActionLog, Event: LogBackupConnectedPNotFound}}
		}
		return []Action{{Kind: ActionLog, Event: LogNeitherFound}}
	}

	return nil
}

// ClassificationResult feeds back whether P is still visible after an SSID transition.
func (e *Engine) ClassificationResult(priorityVisible *bool, _ uint64) []Action {
	pend := e.pending
	e.pending = pendingState{kind: pendingNone}
	if pend.kind != pendingClassification {
		e.pending = pend
		return nil
	}

	if priorityVisible == nil {
		return []Action{
			{Kind: ActionLog, Event: LogPriorityVisibleUnknown},
			{Kind: ActionRefreshStatus},
		}
	}

	switch pend.classCtx {
	case classBackupChange:
		if *priorityVisible {
			e.enterStopped()
			return []Action{
				{Kind: ActionStop, Reason: StopManualOverrideBackup},
				{Kind: ActionRefreshStatus},
			}
		}
		return []Action{
			{Kind: ActionLog, Event: LogSystemJoinedBackup},
			{Kind: ActionCheckNow},
		}

	case classDisconnectFromPriority:
		if *priorityVisible {
			return []Action{
				{Kind: ActionLog, Event: LogPriorityVisibleWaiting},
				{Kind: ActionRefreshStatus},
			}
		}
		e.pending = pendingState{kind: pendingFailover}
		return []Action{
			{Kind: ActionLog, Event: LogPriorityLostConnectingBackup},
			{Kind: ActionScan, Purpose: ScanBackupFailover},
		}

	case classUnmanagedChange:
		if *priorityVisible {
			e.enterStopped()
			return []Action{
				{Kind: ActionStop, Reason: StopManualOverrideUnmanaged},
				{Kind: ActionRefreshStatus},
			}
		}
		e.pending = pendingState{kind: pendingRecovery}
		return []Action{
			{Kind: ActionLog, Event: LogTreatingAsFallback},
			{Kind: ActionScan, Purpose: ScanBackupRecovery},
		}
	}

	return nil
}

// BackupScanResult feeds back visibility of B during failover or recovery.
func (e *Engine) BackupScanResult(found *bool, nowMs uint64) []Action {
	pend := e.pending
	e.pending = pendingState{kind: pendingNone}
	if pend.kind != pendingFailover && pend.kind != pendingRecovery {
		e.pending = pend
		return nil
	}

	if found == nil {
		return []Action{
			{Kind: ActionLog, Event: LogPriorityVisibleUnknown},
			{Kind: ActionRefreshStatus},
		}
	}

	switch pend.kind {
	case pendingFailover:
		if !*found {
			return []Action{
				{Kind: ActionLog, Event: LogBackupNotFound},
				{Kind: ActionRefreshStatus},
			}
		}
		ssid := e.config.SSIDB
		if e.CooldownActiveFor(ssid, nowMs) {
			return []Action{{Kind: ActionLog, Event: LogCooldownSkipped}}
		}
		return []Action{{Kind: ActionAssociate, SSID: ssid, Role: RoleBackup}}

	case pendingRecovery:
		if e.currentSSID != nil && *e.currentSSID == e.config.SSIDB {
			return []Action{{Kind: ActionLog, Event: LogBackupConnectedPNotFound}}
		}
		if !*found {
			return []Action{{Kind: ActionLog, Event: LogBackupNotFoundWaiting}}
		}
		ssid := e.config.SSIDB
		if e.CooldownActiveFor(ssid, nowMs) {
			return []Action{{Kind: ActionLog, Event: LogCooldownSkipped}}
		}
		return []Action{{Kind: ActionAssociate, SSID: ssid, Role: RoleBackup}}
	}

	return nil
}

// AssociationStarted records an in-flight OS association and returns the generation token.
func (e *Engine) AssociationStarted(ssid string, nowMs uint64) uint64 {
	e.generation++
	gen := e.generation
	e.isAssociating = true
	e.activeProgrammatic = nil

	if ssid == e.config.SSIDB {
		e.hasLastProgrammaticBackupAt = true
		e.lastProgrammaticBackupAtMs = nowMs
		e.activeProgrammatic = &intent{
			ssid:       ssid,
			generation: gen,
			deadlineMs: nowMs + e.associationTimeoutMs + ProgrammaticGraceMs,
		}
	}
	return gen
}

// AssociationResult processes completion of an in-flight OS association.
func (e *Engine) AssociationResult(ssid string, generation uint64, outcome AssociationOutcome, nowMs uint64) []Action {
	if generation != e.generation {
		return nil
	}
	e.isAssociating = false

	switch outcome {
	case OutcomeSuccess:
		e.activeProgrammatic = nil
		e.currentSSID = cloneString(ssid)
		if ssid == e.config.SSIDP {
			e.hasLastProgrammaticBackupAt = false
		} else if ssid == e.config.SSIDB {
			e.hasLastProgrammaticBackupAt = true
			e.lastProgrammaticBackupAtMs = nowMs
		}
		e.cooldown = nil
		return []Action{
			{Kind: ActionLog, Event: LogAssociationSuccess},
			{Kind: ActionRefreshStatus},
		}

	case OutcomeTimeout:
		if ssid == e.config.SSIDB {
			e.hasLastProgrammaticBackupAt = false
		} else {
			e.activeProgrammatic = nil
		}
		tgt := ssid
		e.cooldown = &cooldownState{
			target:  &tgt,
			untilMs: nowMs + e.cooldownMs,
		}
		return []Action{
			{Kind: ActionLog, Event: LogAssociationTimeout},
			{Kind: ActionRefreshStatus},
		}

	case OutcomeFailure:
		e.activeProgrammatic = nil
		if ssid == e.config.SSIDB {
			e.hasLastProgrammaticBackupAt = false
		}
		tgt := ssid
		e.cooldown = &cooldownState{
			target:  &tgt,
			untilMs: nowMs + e.cooldownMs,
		}
		return []Action{
			{Kind: ActionLog, Event: LogAssociationFailure},
			{Kind: ActionRefreshStatus},
		}

	case OutcomeAdvisoryEnded:
		e.activeProgrammatic = nil
		e.hasLastProgrammaticBackupAt = false
		return []Action{{Kind: ActionRefreshStatus}}
	}

	return nil
}

// LateAssociationResult handles a timed-out association completing within grace.
func (e *Engine) LateAssociationResult(ssid string, generation uint64, succeeded bool, nowMs uint64) []Action {
	if generation != e.generation {
		return nil
	}
	if e.activeProgrammatic == nil || e.activeProgrammatic.ssid != ssid || e.activeProgrammatic.generation != generation {
		return nil
	}

	e.activeProgrammatic = nil

	if succeeded {
		e.currentSSID = cloneString(ssid)
		if ssid == e.config.SSIDB {
			e.hasLastProgrammaticBackupAt = true
			e.lastProgrammaticBackupAtMs = nowMs
		}
		e.cooldown = nil
		return []Action{
			{Kind: ActionLog, Event: LogAssociationLateSuccess},
			{Kind: ActionRefreshStatus},
		}
	}

	return []Action{{Kind: ActionLog, Event: LogAssociationLateFailure}}
}

// ObservedChange classifies an OS-observed SSID change.
func (e *Engine) ObservedChange(previousSSID, newSSID *string, nowMs uint64) []Action {
	if !e.running {
		return nil
	}
	e.syncConfig()

	if !stringPtrEqual(previousSSID, newSSID) {
		e.pending = pendingState{kind: pendingNone}
	}
	e.currentSSID = cloneStringPtr(newSSID)
	return e.classifyObservedChange(previousSSID, newSSID, nowMs)
}

func (e *Engine) classifyObservedChange(previousSSID, newSSID *string, nowMs uint64) []Action {
	if newSSID != nil && *newSSID == e.config.SSIDP {
		e.currentSSID = cloneString(*newSSID)
		return []Action{
			{Kind: ActionLog, Event: LogPriorityConnected},
			{Kind: ActionRefreshStatus},
		}
	}

	if newSSID == nil {
		wasPriority := previousSSID != nil && *previousSSID == e.config.SSIDP
		e.currentSSID = nil
		if wasPriority {
			e.pending = pendingState{
				kind:     pendingClassification,
				classCtx: classDisconnectFromPriority,
			}
			return []Action{{Kind: ActionScan, Purpose: ScanPriorityClassification}}
		}
		return []Action{{Kind: ActionLog, Event: LogNetworkDisconnectedWaiting}}
	}

	ssid := *newSSID
	e.currentSSID = cloneString(ssid)
	isBackup := ssid == e.config.SSIDB
	isPreviousBackup := e.previousBackupSSID != nil && *e.previousBackupSSID == ssid

	if isBackup {
		if e.recentProgrammaticBackup(nowMs) {
			return []Action{
				{Kind: ActionLog, Event: LogAutomaticFailover},
				{Kind: ActionCheckNow},
			}
		}
		e.pending = pendingState{
			kind:     pendingClassification,
			classCtx: classBackupChange,
		}
		return []Action{{Kind: ActionScan, Purpose: ScanPriorityClassification}}
	}

	if isPreviousBackup && ssid != e.config.SSIDB {
		e.pending = pendingState{kind: pendingRecovery}
		return []Action{
			{Kind: ActionLog, Event: LogPreviousBackupReconnect},
			{Kind: ActionScan, Purpose: ScanBackupRecovery},
		}
	}

	e.pending = pendingState{
		kind:     pendingClassification,
		classCtx: classUnmanagedChange,
	}
	return []Action{{Kind: ActionScan, Purpose: ScanPriorityClassification}}
}

// RoleFor maps an optional SSID to its configured Role.
func (e *Engine) RoleFor(ssid *string) Role {
	if ssid == nil || *ssid == "" {
		return RoleNone
	}
	switch *ssid {
	case e.config.SSIDP:
		return RolePriority
	case e.config.SSIDB:
		return RoleBackup
	default:
		return RoleOther
	}
}

// CooldownActiveFor reports whether cooldown currently blocks associating to ssid.
func (e *Engine) CooldownActiveFor(ssid string, nowMs uint64) bool {
	if e.cooldown == nil || e.cooldown.untilMs <= nowMs {
		return false
	}
	if e.cooldown.target == nil {
		return true
	}
	return *e.cooldown.target == ssid
}

// IsRecentProgrammaticBackup reports whether Via recently switched to backup.
func (e *Engine) IsRecentProgrammaticBackup(nowMs uint64) bool {
	return e.recentProgrammaticBackup(nowMs)
}

// IsCurrentGeneration reports whether generation matches the engine's current epoch.
func (e *Engine) IsCurrentGeneration(generation uint64) bool {
	return generation == e.generation
}

// Snapshot returns an immutable summary of current policy state.
func (e *Engine) Snapshot() Snapshot {
	snap := Snapshot{
		Running:       e.running,
		Role:          e.RoleFor(e.currentSSID),
		Permission:    e.permission,
		IsAssociating: e.isAssociating,
	}
	if e.currentSSID != nil {
		snap.CurrentSSID = *e.currentSSID
		snap.HasCurrentSSID = true
	}
	if e.cooldown != nil {
		until := e.cooldown.untilMs
		snap.CooldownUntilMs = &until
		if e.cooldown.target != nil {
			tgt := *e.cooldown.target
			snap.CooldownTarget = &tgt
		}
	}
	return snap
}

func (e *Engine) recentProgrammaticBackup(nowMs uint64) bool {
	if e.activeProgrammatic != nil &&
		e.activeProgrammatic.ssid == e.config.SSIDB &&
		e.activeProgrammatic.generation == e.generation &&
		nowMs <= e.activeProgrammatic.deadlineMs {
		return true
	}
	if e.hasLastProgrammaticBackupAt && nowMs >= e.lastProgrammaticBackupAtMs {
		return (nowMs - e.lastProgrammaticBackupAtMs) <= e.programmaticWindowMs
	}
	return false
}

func (e *Engine) enterStopped() {
	e.running = false
	e.generation++
	e.isAssociating = false
	e.pending = pendingState{kind: pendingNone}
	e.activeProgrammatic = nil
	e.hasLastProgrammaticBackupAt = false
}

func (e *Engine) syncConfig() {
	if e.trackedBackupSSID != e.config.SSIDB {
		if e.trackedBackupSSID != "" {
			prev := e.trackedBackupSSID
			e.previousBackupSSID = &prev
		}
		e.trackedBackupSSID = e.config.SSIDB
	}
}

func (e *Engine) configSnapshot() configSnapshot {
	return configSnapshot{ssidP: e.config.SSIDP, ssidB: e.config.SSIDB}
}

func (e *Engine) configMatches(other configSnapshot) bool {
	return e.config.SSIDP == other.ssidP && e.config.SSIDB == other.ssidB
}

func cloneStringPtr(s *string) *string {
	if s == nil {
		return nil
	}
	v := *s
	return &v
}

func cloneString(s string) *string {
	return &s
}

func stringPtrEqual(a, b *string) bool {
	if a == nil && b == nil {
		return true
	}
	if a == nil || b == nil {
		return false
	}
	return *a == *b
}
