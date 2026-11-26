// Package policy implements Via's deterministic Wi-Fi switching state machine
// and domain model. Nothing in this package touches a clock, OS framework, or
// credential store; callers supply timestamps (nowMs) and execute returned Actions.
package policy

// Config holds the two managed network SSIDs. SSIDP is preferred; SSIDB is fallback.
type Config struct {
	SSIDP string
	SSIDB string
}

// IsComplete reports whether both primary and backup SSIDs are non-empty.
func (c Config) IsComplete() bool {
	return c.SSIDP != "" && c.SSIDB != ""
}

// Permission represents OS location/Wi-Fi permission status relevant to policy.
type Permission int

const (
	PermissionUnknown Permission = iota
	PermissionAuthorized
	PermissionDenied
)

func (p Permission) String() string {
	switch p {
	case PermissionAuthorized:
		return "authorized"
	case PermissionDenied:
		return "denied"
	default:
		return "unknown"
	}
}

// Role identifies which configured slot an SSID belongs to.
type Role int

const (
	RoleNone Role = iota
	RolePriority
	RoleBackup
	RoleOther
)

func (r Role) String() string {
	switch r {
	case RolePriority:
		return "priority"
	case RoleBackup:
		return "backup"
	case RoleOther:
		return "other"
	default:
		return "none"
	}
}

// ScanPurpose explains why the platform adapter is being asked to scan.
type ScanPurpose int

const (
	ScanPriorityCheck ScanPurpose = iota
	ScanBackupCheck
	ScanPriorityClassification
	ScanBackupFailover
	ScanBackupRecovery
)

// StopReason identifies why the policy stopped automatic switching.
type StopReason int

const (
	StopNotConfigured StopReason = iota
	StopManualOverrideBackup
	StopManualOverrideUnmanaged
)

// LogEvent represents a semantic diagnostic/status event.
type LogEvent int

const (
	LogStarted LogEvent = iota
	LogStopped
	LogPriorityConnected
	LogPriorityVisibleWaiting
	LogNetworkDisconnectedWaiting
	LogAutomaticFailover
	LogPriorityLostConnectingBackup
	LogBackupConnectedPNotFound
	LogNeitherFound
	LogBackupNotFound
	LogBackupNotFoundWaiting
	LogPreviousBackupReconnect
	LogSystemJoinedBackup
	LogTreatingAsFallback
	LogCooldownSkipped
	LogAssociationSuccess
	LogAssociationTimeout
	LogAssociationFailure
	LogAssociationLateSuccess
	LogAssociationLateFailure
	LogPermissionRequired
	LogPriorityVisibleUnknown
)

// AssociationOutcome reports the result of an OS association request.
type AssociationOutcome int

const (
	OutcomeSuccess AssociationOutcome = iota
	OutcomeTimeout
	OutcomeFailure
	OutcomeAdvisoryEnded
)

// ActionKind identifies the command an OS shell must perform after a policy step.
type ActionKind int

const (
	ActionScan ActionKind = iota
	ActionAssociate
	ActionCheckNow
	ActionStop
	ActionWaitForPermission
	ActionLog
	ActionRefreshStatus
)

// Action is a decision produced by Engine for the host shell to execute.
type Action struct {
	Kind    ActionKind
	Purpose ScanPurpose
	SSID    string
	Role    Role
	Reason  StopReason
	Event   LogEvent
}

// Snapshot captures observable policy state for UI and diagnostics.
type Snapshot struct {
	Running         bool
	Role            Role
	Permission      Permission
	CurrentSSID     string
	HasCurrentSSID  bool
	IsAssociating   bool
	CooldownUntilMs *uint64
	CooldownTarget  *string
}
