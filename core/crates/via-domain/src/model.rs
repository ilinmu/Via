//! Platform-neutral value types for the Wi-Fi switching policy.
//!
//! Nothing in this module touches a clock, a radio, or a platform API. Native
//! shells translate their own events into these values and execute the
//! returned [`Action`]s.

/// The two managed networks. `P` is preferred; `B` is the fallback.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Config {
    pub ssid_p: String,
    pub ssid_b: String,
}

impl Config {
    pub fn new(ssid_p: impl Into<String>, ssid_b: impl Into<String>) -> Self {
        Self {
            ssid_p: ssid_p.into(),
            ssid_b: ssid_b.into(),
        }
    }

    pub fn is_complete(&self) -> bool {
        !self.ssid_p.is_empty() && !self.ssid_b.is_empty()
    }
}

/// Location / Wi-Fi permission state as the policy cares about it.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Permission {
    Unknown,
    Authorized,
    Denied,
}

/// Which configured slot an SSID belongs to.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Role {
    None,
    Priority,
    Backup,
    Other,
}

/// Why the native shell is being asked to scan.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ScanPurpose {
    /// Check for P during the regular monitoring tick.
    PriorityCheck,
    /// Check for B after P was not found.
    BackupCheck,
    /// Scan P only to classify an observed SSID change.
    PriorityClassification,
    /// Scan B before an automatic failover.
    BackupFailover,
    /// Scan the currently configured B for recovery.
    BackupRecovery,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum StopReason {
    NotConfigured,
    ManualOverrideBackup,
    ManualOverrideUnmanaged,
}

/// Semantic log events. Native shells own the localized wording.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum LogEvent {
    Started,
    Stopped,
    PriorityConnected,
    PriorityVisibleWaiting,
    NetworkDisconnectedWaiting,
    AutomaticFailover,
    PriorityLostConnectingBackup,
    BackupConnectedPNotFound,
    NeitherFound,
    BackupNotFound,
    BackupNotFoundWaiting,
    PreviousBackupReconnect,
    SystemJoinedBackup,
    TreatingAsFallback,
    CooldownSkipped,
    AssociationSuccess,
    AssociationTimeout,
    AssociationFailure,
    AssociationLateSuccess,
    AssociationLateFailure,
    PermissionRequired,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AssociationOutcome {
    Success,
    Timeout,
    Failure,
}

/// A decision produced by the policy. The native shell is responsible for
/// executing it and feeding the result back into the engine.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Action {
    Scan(ScanPurpose),
    Associate {
        ssid: String,
        role: Role,
    },
    /// Run the regular check again as soon as the current call returns.
    CheckNow,
    Stop(StopReason),
    WaitForPermission,
    Log(LogEvent),
    RefreshStatus,
}

/// State the UI needs after a policy step.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Snapshot {
    pub running: bool,
    pub role: Role,
    pub permission: Permission,
    pub current_ssid: Option<String>,
    pub is_associating: bool,
    pub cooldown_until_ms: Option<u64>,
    pub cooldown_target: Option<String>,
}
