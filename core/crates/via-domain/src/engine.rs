//! The switching policy as a deterministic state machine.
//!
//! All time is supplied by the caller (`now_ms`) so tests and every platform
//! shell observe the same behavior. The engine never scans, associates, reads
//! a clock, or touches a password. It returns [`Action`] values that the
//! native layer executes.

use crate::model::{
    Action, AssociationOutcome, Config, LogEvent, Permission, Role, ScanPurpose, Snapshot,
    StopReason,
};

const DEFAULT_ASSOCIATION_TIMEOUT_MS: u64 = 15_000;
const DEFAULT_COOLDOWN_MS: u64 = 90_000;
const DEFAULT_PROGRAMMATIC_WINDOW_MS: u64 = 15_000;
/// A timed-out association may still complete at the CoreWLAN layer. Keep its
/// intent alive for this bounded extra period so a late SSID event is still
/// attributed to the app.
const PROGRAMMATIC_GRACE_MS: u64 = 60_000;

#[derive(Clone, Debug)]
struct ConfigAtScan {
    ssid_p: String,
    ssid_b: String,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum ClassificationContext {
    /// The system landed on the configured backup network.
    BackupChange,
    /// The previous network was P and the radio is now disconnected.
    DisconnectFromPriority,
    /// The system landed on a network outside the configuration.
    UnmanagedChange,
}

#[derive(Clone, Debug)]
enum Pending {
    None,
    Scan {
        purpose: ScanPurpose,
        config: ConfigAtScan,
    },
    Classification(ClassificationContext),
    Failover,
    Recovery,
}

#[derive(Clone, Debug)]
struct Intent {
    ssid: String,
    generation: u64,
    deadline_ms: u64,
}

#[derive(Clone, Debug)]
struct Cooldown {
    target: Option<String>,
    until_ms: u64,
}

pub struct Engine {
    config: Config,
    running: bool,
    permission: Permission,
    generation: u64,
    is_associating: bool,
    current_ssid: Option<String>,
    tracked_backup_ssid: String,
    previous_backup_ssid: Option<String>,
    last_programmatic_backup_at_ms: Option<u64>,
    active_programmatic: Option<Intent>,
    cooldown: Option<Cooldown>,
    pending: Pending,
    association_timeout_ms: u64,
    cooldown_ms: u64,
    programmatic_window_ms: u64,
}

impl Engine {
    pub fn new(config: Config) -> Self {
        Self {
            tracked_backup_ssid: config.ssid_b.clone(),
            config,
            running: false,
            permission: Permission::Unknown,
            generation: 0,
            is_associating: false,
            current_ssid: None,
            previous_backup_ssid: None,
            last_programmatic_backup_at_ms: None,
            active_programmatic: None,
            cooldown: None,
            pending: Pending::None,
            association_timeout_ms: DEFAULT_ASSOCIATION_TIMEOUT_MS,
            cooldown_ms: DEFAULT_COOLDOWN_MS,
            programmatic_window_ms: DEFAULT_PROGRAMMATIC_WINDOW_MS,
        }
    }

    /// Used by native tests and platform adapters whose OS timeout differs.
    pub fn with_timings(
        config: Config,
        association_timeout_ms: u64,
        cooldown_ms: u64,
        programmatic_window_ms: u64,
    ) -> Self {
        let mut engine = Self::new(config);
        engine.association_timeout_ms = association_timeout_ms;
        engine.cooldown_ms = cooldown_ms;
        engine.programmatic_window_ms = programmatic_window_ms;
        engine
    }

    /// Restores a cooldown persisted by a previous process. An expired value is
    /// ignored, matching the native app's behavior on launch.
    pub fn set_persisted_cooldown(
        &mut self,
        target: Option<String>,
        until_ms: Option<u64>,
        now_ms: u64,
    ) {
        self.cooldown = match until_ms {
            Some(until) if until > now_ms => Some(Cooldown {
                target,
                until_ms: until,
            }),
            _ => None,
        };
    }

    pub fn set_config(&mut self, ssid_p: impl Into<String>, ssid_b: impl Into<String>) {
        self.config = Config::new(ssid_p, ssid_b);
        self.sync_config();
    }

    /// Start a monitoring session. The native shell calls this after its own
    /// configuration and permission guards.
    pub fn start(
        &mut self,
        now_ms: u64,
        permission: Permission,
        current_ssid: Option<&str>,
    ) -> Vec<Action> {
        self.permission = permission;
        self.current_ssid = current_ssid.map(str::to_string);
        self.sync_config();

        if !self.config.is_complete() {
            self.running = false;
            return vec![Action::Stop(StopReason::NotConfigured)];
        }

        self.generation = self.generation.wrapping_add(1);
        self.is_associating = false;
        self.pending = Pending::None;
        self.active_programmatic = None;
        self.last_programmatic_backup_at_ms = None;
        self.cooldown = None;
        self.running = true;

        if permission != Permission::Authorized {
            return vec![Action::WaitForPermission];
        }

        self.check_begin(now_ms, permission, current_ssid)
    }

    pub fn stop(&mut self) -> Vec<Action> {
        self.enter_stopped();
        Vec::new()
    }

    /// Begin one regular monitoring check.
    pub fn check_begin(
        &mut self,
        _now_ms: u64,
        permission: Permission,
        current_ssid: Option<&str>,
    ) -> Vec<Action> {
        if !self.running {
            return Vec::new();
        }

        // Every regular check supersedes a scan chain started by an older
        // check, even when this one confirms we are already on P.
        self.pending = Pending::None;
        self.permission = permission;
        self.current_ssid = current_ssid.map(str::to_string);

        if permission != Permission::Authorized {
            return vec![Action::WaitForPermission];
        }
        if self.is_associating {
            return Vec::new();
        }

        self.sync_config();
        if !self.config.is_complete() {
            self.running = false;
            return vec![Action::Stop(StopReason::NotConfigured)];
        }

        if self.current_ssid.as_deref() == Some(self.config.ssid_p.as_str()) {
            self.cooldown = None;
            return vec![Action::RefreshStatus];
        }

        self.pending = Pending::Scan {
            purpose: ScanPurpose::PriorityCheck,
            config: self.config_snapshot(),
        };
        vec![Action::Scan(ScanPurpose::PriorityCheck)]
    }

    /// Feed back the result of a scan requested by [`Action::Scan`].
    pub fn scan_result(&mut self, found: Option<bool>, now_ms: u64) -> Vec<Action> {
        let pending = std::mem::replace(&mut self.pending, Pending::None);
        let (purpose, config) = match pending {
            Pending::Scan { purpose, config } => (purpose, config),
            other => {
                // A newer SSID event superseded this scan. Keep its pending
                // classification instead of letting a stale result consume it.
                self.pending = other;
                return Vec::new();
            }
        };
        let Some(found) = found else {
            return vec![
                Action::Log(LogEvent::PriorityVisibleUnknown),
                Action::RefreshStatus,
            ];
        };

        if !self.config_matches(&config) {
            // The user edited either SSID while the scan was in flight. Never
            // act on a stale target; ask the shell to run the check again.
            return vec![Action::CheckNow];
        }

        match purpose {
            ScanPurpose::PriorityCheck => {
                if found {
                    let ssid = self.config.ssid_p.clone();
                    if self.cooldown_active_for(&ssid, now_ms) {
                        return vec![Action::Log(LogEvent::CooldownSkipped)];
                    }
                    return vec![Action::Associate {
                        ssid,
                        role: Role::Priority,
                    }];
                }

                self.pending = Pending::Scan {
                    purpose: ScanPurpose::BackupCheck,
                    config: self.config_snapshot(),
                };
                vec![Action::Scan(ScanPurpose::BackupCheck)]
            }
            ScanPurpose::BackupCheck => {
                let current_is_backup =
                    self.current_ssid.as_deref() == Some(self.config.ssid_b.as_str());

                if found && !current_is_backup {
                    let ssid = self.config.ssid_b.clone();
                    if self.cooldown_active_for(&ssid, now_ms) {
                        return vec![Action::Log(LogEvent::CooldownSkipped)];
                    }
                    return vec![Action::Associate {
                        ssid,
                        role: Role::Backup,
                    }];
                }

                if found && current_is_backup {
                    return vec![Action::Log(LogEvent::BackupConnectedPNotFound)];
                }

                vec![Action::Log(LogEvent::NeitherFound)]
            }
            _ => Vec::new(),
        }
    }

    /// Feed back the classification scan requested after an SSID change.
    pub fn classification_result(
        &mut self,
        priority_visible: Option<bool>,
        _now_ms: u64,
    ) -> Vec<Action> {
        let pending = std::mem::replace(&mut self.pending, Pending::None);
        let context = match pending {
            Pending::Classification(context) => context,
            other => {
                // A newer regular check or SSID event owns the pending state.
                self.pending = other;
                return Vec::new();
            }
        };
        let Some(priority_visible) = priority_visible else {
            return vec![
                Action::Log(LogEvent::PriorityVisibleUnknown),
                Action::RefreshStatus,
            ];
        };

        match context {
            ClassificationContext::BackupChange => {
                if priority_visible {
                    self.enter_stopped();
                    vec![
                        Action::Stop(StopReason::ManualOverrideBackup),
                        Action::RefreshStatus,
                    ]
                } else {
                    vec![Action::Log(LogEvent::SystemJoinedBackup), Action::CheckNow]
                }
            }
            ClassificationContext::DisconnectFromPriority => {
                if priority_visible {
                    vec![
                        Action::Log(LogEvent::PriorityVisibleWaiting),
                        Action::RefreshStatus,
                    ]
                } else {
                    self.pending = Pending::Failover;
                    vec![
                        Action::Log(LogEvent::PriorityLostConnectingBackup),
                        Action::Scan(ScanPurpose::BackupFailover),
                    ]
                }
            }
            ClassificationContext::UnmanagedChange => {
                if priority_visible {
                    self.enter_stopped();
                    vec![
                        Action::Stop(StopReason::ManualOverrideUnmanaged),
                        Action::RefreshStatus,
                    ]
                } else {
                    self.pending = Pending::Recovery;
                    vec![
                        Action::Log(LogEvent::TreatingAsFallback),
                        Action::Scan(ScanPurpose::BackupRecovery),
                    ]
                }
            }
        }
    }

    /// Feed back a failover / recovery scan for the configured backup network.
    pub fn backup_scan_result(&mut self, found: Option<bool>, now_ms: u64) -> Vec<Action> {
        let pending = std::mem::replace(&mut self.pending, Pending::None);
        let pending = match pending {
            Pending::Failover | Pending::Recovery => pending,
            other => {
                // Preserve a newer pending operation; this stale scan result
                // must not consume it or trigger an obsolete association.
                self.pending = other;
                return Vec::new();
            }
        };
        let Some(found) = found else {
            return vec![
                Action::Log(LogEvent::PriorityVisibleUnknown),
                Action::RefreshStatus,
            ];
        };

        match pending {
            Pending::Failover => {
                if !found {
                    return vec![Action::Log(LogEvent::BackupNotFound), Action::RefreshStatus];
                }
                let ssid = self.config.ssid_b.clone();
                if self.cooldown_active_for(&ssid, now_ms) {
                    return vec![Action::Log(LogEvent::CooldownSkipped)];
                }
                vec![Action::Associate {
                    ssid,
                    role: Role::Backup,
                }]
            }
            Pending::Recovery => {
                if self.current_ssid.as_deref() == Some(self.config.ssid_b.as_str()) {
                    return vec![Action::Log(LogEvent::BackupConnectedPNotFound)];
                }
                if !found {
                    return vec![Action::Log(LogEvent::BackupNotFoundWaiting)];
                }
                let ssid = self.config.ssid_b.clone();
                if self.cooldown_active_for(&ssid, now_ms) {
                    return vec![Action::Log(LogEvent::CooldownSkipped)];
                }
                vec![Action::Associate {
                    ssid,
                    role: Role::Backup,
                }]
            }
            _ => Vec::new(),
        }
    }

    /// Called immediately before the native shell starts an association.
    /// Returns the generation the shell must pass back with the result.
    pub fn association_started(&mut self, ssid: &str, now_ms: u64) -> u64 {
        self.generation = self.generation.wrapping_add(1);
        let generation = self.generation;
        self.is_associating = true;
        self.active_programmatic = None;

        if ssid == self.config.ssid_b {
            self.last_programmatic_backup_at_ms = Some(now_ms);
            self.active_programmatic = Some(Intent {
                ssid: ssid.to_string(),
                generation,
                deadline_ms: now_ms
                    .saturating_add(self.association_timeout_ms)
                    .saturating_add(PROGRAMMATIC_GRACE_MS),
            });
        }

        generation
    }

    pub fn association_result(
        &mut self,
        ssid: &str,
        generation: u64,
        outcome: AssociationOutcome,
        now_ms: u64,
    ) -> Vec<Action> {
        if generation != self.generation {
            return Vec::new();
        }

        self.is_associating = false;

        match outcome {
            AssociationOutcome::Success => {
                self.active_programmatic = None;
                self.current_ssid = Some(ssid.to_string());
                if ssid == self.config.ssid_p {
                    self.last_programmatic_backup_at_ms = None;
                } else if ssid == self.config.ssid_b {
                    self.last_programmatic_backup_at_ms = Some(now_ms);
                }
                self.cooldown = None;
                vec![
                    Action::Log(LogEvent::AssociationSuccess),
                    Action::RefreshStatus,
                ]
            }
            AssociationOutcome::Timeout => {
                if ssid == self.config.ssid_b {
                    // Keep the intent: CoreWLAN cannot be cancelled and may
                    // still complete after the UI timeout.
                    self.last_programmatic_backup_at_ms = None;
                } else {
                    self.active_programmatic = None;
                }
                self.cooldown = Some(Cooldown {
                    target: Some(ssid.to_string()),
                    until_ms: now_ms.saturating_add(self.cooldown_ms),
                });
                vec![
                    Action::Log(LogEvent::AssociationTimeout),
                    Action::RefreshStatus,
                ]
            }
            AssociationOutcome::Failure => {
                self.active_programmatic = None;
                if ssid == self.config.ssid_b {
                    self.last_programmatic_backup_at_ms = None;
                }
                self.cooldown = Some(Cooldown {
                    target: Some(ssid.to_string()),
                    until_ms: now_ms.saturating_add(self.cooldown_ms),
                });
                vec![
                    Action::Log(LogEvent::AssociationFailure),
                    Action::RefreshStatus,
                ]
            }
            AssociationOutcome::AdvisoryEnded => {
                // System-managed suggestions can be ignored or delayed. End the
                // in-flight association without marking a failure or applying
                // a cooldown; the next regular check re-evaluates the target.
                self.active_programmatic = None;
                self.last_programmatic_backup_at_ms = None;
                vec![Action::RefreshStatus]
            }
        }
    }

    /// A timed-out association finished after the UI already moved on.
    pub fn late_association_result(
        &mut self,
        ssid: &str,
        generation: u64,
        succeeded: bool,
        now_ms: u64,
    ) -> Vec<Action> {
        if generation != self.generation {
            return Vec::new();
        }
        let matches_intent = self
            .active_programmatic
            .as_ref()
            .map(|intent| intent.ssid == ssid && intent.generation == generation)
            .unwrap_or(false);
        if !matches_intent {
            return Vec::new();
        }

        self.active_programmatic = None;

        if succeeded {
            self.current_ssid = Some(ssid.to_string());
            if ssid == self.config.ssid_b {
                self.last_programmatic_backup_at_ms = Some(now_ms);
            }
            self.cooldown = None;
            vec![
                Action::Log(LogEvent::AssociationLateSuccess),
                Action::RefreshStatus,
            ]
        } else {
            vec![Action::Log(LogEvent::AssociationLateFailure)]
        }
    }

    /// An SSID event observed by the native layer.
    pub fn observed_change(
        &mut self,
        previous_ssid: Option<&str>,
        new_ssid: Option<&str>,
        now_ms: u64,
    ) -> Vec<Action> {
        if !self.running {
            return Vec::new();
        }
        self.sync_config();

        if previous_ssid != new_ssid {
            // A real SSID transition supersedes any scan or classification that
            // started before it. Its late result belongs to stale state.
            self.pending = Pending::None;
        }
        self.current_ssid = new_ssid.map(str::to_string);
        self.classify_observed_change(previous_ssid, new_ssid, now_ms)
    }

    fn classify_observed_change(
        &mut self,
        previous_ssid: Option<&str>,
        new_ssid: Option<&str>,
        now_ms: u64,
    ) -> Vec<Action> {
        match new_ssid {
            Some(ssid) if ssid == self.config.ssid_p.as_str() => {
                self.current_ssid = Some(ssid.to_string());
                vec![
                    Action::Log(LogEvent::PriorityConnected),
                    Action::RefreshStatus,
                ]
            }
            None => {
                let was_priority = previous_ssid == Some(self.config.ssid_p.as_str());
                self.current_ssid = None;
                if was_priority {
                    self.pending =
                        Pending::Classification(ClassificationContext::DisconnectFromPriority);
                    vec![Action::Scan(ScanPurpose::PriorityClassification)]
                } else {
                    vec![Action::Log(LogEvent::NetworkDisconnectedWaiting)]
                }
            }
            Some(ssid) => {
                self.current_ssid = Some(ssid.to_string());
                let is_backup = ssid == self.config.ssid_b.as_str();
                let is_previous_backup = self.previous_backup_ssid.as_deref() == Some(ssid);
                let current_backup = self.config.ssid_b.clone();

                if is_backup {
                    if self.recent_programmatic_backup(now_ms) {
                        return vec![Action::Log(LogEvent::AutomaticFailover), Action::CheckNow];
                    }
                    self.pending = Pending::Classification(ClassificationContext::BackupChange);
                    return vec![Action::Scan(ScanPurpose::PriorityClassification)];
                }

                if is_previous_backup && ssid != current_backup.as_str() {
                    self.pending = Pending::Recovery;
                    return vec![
                        Action::Log(LogEvent::PreviousBackupReconnect),
                        Action::Scan(ScanPurpose::BackupRecovery),
                    ];
                }

                self.pending = Pending::Classification(ClassificationContext::UnmanagedChange);
                vec![Action::Scan(ScanPurpose::PriorityClassification)]
            }
        }
    }

    pub fn role_for(&self, ssid: Option<&str>) -> Role {
        match ssid {
            Some(ssid) if ssid == self.config.ssid_p => Role::Priority,
            Some(ssid) if ssid == self.config.ssid_b => Role::Backup,
            Some(_) => Role::Other,
            None => Role::None,
        }
    }

    pub fn cooldown_active_for(&self, ssid: &str, now_ms: u64) -> bool {
        match &self.cooldown {
            Some(cooldown) if cooldown.until_ms > now_ms => match &cooldown.target {
                Some(target) => target == ssid,
                // A legacy persisted cooldown had no target; keep its old
                // conservative behavior and apply it to every SSID.
                None => true,
            },
            _ => false,
        }
    }

    pub fn is_recent_programmatic_backup(&self, now_ms: u64) -> bool {
        self.recent_programmatic_backup(now_ms)
    }

    pub fn is_current_generation(&self, generation: u64) -> bool {
        generation == self.generation
    }

    pub fn snapshot(&self) -> Snapshot {
        Snapshot {
            running: self.running,
            role: self.role_for(self.current_ssid.as_deref()),
            permission: self.permission,
            current_ssid: self.current_ssid.clone(),
            is_associating: self.is_associating,
            cooldown_until_ms: self.cooldown.as_ref().map(|cooldown| cooldown.until_ms),
            cooldown_target: self
                .cooldown
                .as_ref()
                .and_then(|cooldown| cooldown.target.clone()),
        }
    }

    fn recent_programmatic_backup(&self, now_ms: u64) -> bool {
        if let Some(intent) = &self.active_programmatic {
            if intent.ssid == self.config.ssid_b
                && intent.generation == self.generation
                && now_ms <= intent.deadline_ms
            {
                return true;
            }
        }

        self.last_programmatic_backup_at_ms
            .map(|at| now_ms.saturating_sub(at) <= self.programmatic_window_ms)
            .unwrap_or(false)
    }

    fn enter_stopped(&mut self) {
        self.running = false;
        self.generation = self.generation.wrapping_add(1);
        self.is_associating = false;
        self.pending = Pending::None;
        self.active_programmatic = None;
        self.last_programmatic_backup_at_ms = None;
    }

    fn sync_config(&mut self) {
        if self.tracked_backup_ssid != self.config.ssid_b {
            if !self.tracked_backup_ssid.is_empty() {
                self.previous_backup_ssid = Some(self.tracked_backup_ssid.clone());
            }
            self.tracked_backup_ssid = self.config.ssid_b.clone();
        }
    }

    fn config_snapshot(&self) -> ConfigAtScan {
        ConfigAtScan {
            ssid_p: self.config.ssid_p.clone(),
            ssid_b: self.config.ssid_b.clone(),
        }
    }

    fn config_matches(&self, other: &ConfigAtScan) -> bool {
        self.config.ssid_p == other.ssid_p && self.config.ssid_b == other.ssid_b
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn engine() -> Engine {
        Engine::with_timings(Config::new("P", "B"), 1_000, 90_000, 15_000)
    }

    fn p_associate() -> Action {
        Action::Associate {
            ssid: "P".to_string(),
            role: Role::Priority,
        }
    }

    fn b_associate() -> Action {
        Action::Associate {
            ssid: "B".to_string(),
            role: Role::Backup,
        }
    }

    #[test]
    fn missing_configuration_stops_monitoring() {
        let mut engine = Engine::new(Config::new("", ""));
        assert_eq!(
            engine.start(0, Permission::Authorized, None),
            vec![Action::Stop(StopReason::NotConfigured)]
        );
        assert!(!engine.snapshot().running);
    }

    #[test]
    fn starting_on_priority_only_refreshes() {
        let mut engine = engine();
        assert_eq!(
            engine.start(0, Permission::Authorized, Some("P")),
            vec![Action::RefreshStatus]
        );
        assert!(engine.snapshot().running);
        assert_eq!(engine.snapshot().role, Role::Priority);
    }

    #[test]
    fn permission_denied_keeps_session_waiting() {
        let mut engine = engine();
        assert_eq!(
            engine.start(0, Permission::Denied, None),
            vec![Action::WaitForPermission]
        );
        assert!(engine.snapshot().running);
        assert_eq!(engine.snapshot().permission, Permission::Denied);
    }

    #[test]
    fn regular_check_scans_priority_then_associates() {
        let mut engine = engine();
        assert_eq!(
            engine.start(0, Permission::Authorized, Some("X")),
            vec![Action::Scan(ScanPurpose::PriorityCheck)]
        );
        assert_eq!(engine.scan_result(Some(true), 10), vec![p_associate()]);
    }

    #[test]
    fn regular_check_falls_back_to_backup() {
        let mut engine = engine();
        engine.start(0, Permission::Authorized, Some("X"));
        assert_eq!(
            engine.scan_result(Some(false), 10),
            vec![Action::Scan(ScanPurpose::BackupCheck)]
        );
        assert_eq!(engine.scan_result(Some(true), 20), vec![b_associate()]);
    }

    #[test]
    fn regular_check_logs_when_neither_network_is_visible() {
        let mut engine = engine();
        engine.start(0, Permission::Authorized, Some("X"));
        engine.scan_result(Some(false), 10);
        assert_eq!(
            engine.scan_result(Some(false), 20),
            vec![Action::Log(LogEvent::NeitherFound)]
        );
    }

    #[test]
    fn cooldown_for_backup_does_not_block_priority() {
        let mut engine = engine();
        engine.start(0, Permission::Authorized, Some("B"));
        engine.set_persisted_cooldown(Some("B".to_string()), Some(100_000), 0);

        assert_eq!(
            engine.check_begin(10, Permission::Authorized, Some("B")),
            vec![Action::Scan(ScanPurpose::PriorityCheck)]
        );
        assert_eq!(engine.scan_result(Some(true), 20), vec![p_associate()]);
    }

    #[test]
    fn association_timeout_applies_cooldown_for_same_target() {
        let mut engine = engine();
        engine.start(0, Permission::Authorized, None);
        engine.scan_result(Some(true), 10);
        let generation = engine.association_started("P", 20);
        assert_eq!(
            engine.association_result("P", generation, AssociationOutcome::Timeout, 30),
            vec![
                Action::Log(LogEvent::AssociationTimeout),
                Action::RefreshStatus
            ]
        );
        assert!(engine.cooldown_active_for("P", 40));
        assert!(!engine.cooldown_active_for("B", 40));

        engine.check_begin(50, Permission::Authorized, None);
        assert_eq!(
            engine.scan_result(Some(true), 60),
            vec![Action::Log(LogEvent::CooldownSkipped)]
        );
    }

    #[test]
    fn manual_switch_to_backup_while_priority_visible_stops() {
        let mut engine = engine();
        engine.start(0, Permission::Authorized, Some("P"));

        assert_eq!(
            engine.observed_change(Some("P"), Some("B"), 10),
            vec![Action::Scan(ScanPurpose::PriorityClassification)]
        );
        assert_eq!(
            engine.classification_result(Some(true), 20),
            vec![
                Action::Stop(StopReason::ManualOverrideBackup),
                Action::RefreshStatus
            ]
        );
        assert!(!engine.snapshot().running);
    }

    #[test]
    fn programmatic_backup_change_keeps_monitoring() {
        let mut engine = engine();
        engine.start(0, Permission::Authorized, Some("X"));
        engine.scan_result(Some(false), 10);
        engine.scan_result(Some(true), 20);
        let generation = engine.association_started("B", 30);

        assert_eq!(
            engine.observed_change(Some("X"), Some("B"), 40),
            vec![Action::Log(LogEvent::AutomaticFailover), Action::CheckNow]
        );

        engine.association_result("B", generation, AssociationOutcome::Success, 50);
        assert!(engine.snapshot().running);
        assert_eq!(engine.snapshot().role, Role::Backup);
    }

    #[test]
    fn disconnect_from_priority_waits_when_priority_is_still_visible() {
        let mut engine = engine();
        engine.start(0, Permission::Authorized, Some("P"));

        assert_eq!(
            engine.observed_change(Some("P"), None, 10),
            vec![Action::Scan(ScanPurpose::PriorityClassification)]
        );
        assert_eq!(
            engine.classification_result(Some(true), 20),
            vec![
                Action::Log(LogEvent::PriorityVisibleWaiting),
                Action::RefreshStatus
            ]
        );
    }

    #[test]
    fn disconnect_from_priority_fails_over_when_priority_is_gone() {
        let mut engine = engine();
        engine.start(0, Permission::Authorized, Some("P"));

        engine.observed_change(Some("P"), None, 10);
        assert_eq!(
            engine.classification_result(Some(false), 20),
            vec![
                Action::Log(LogEvent::PriorityLostConnectingBackup),
                Action::Scan(ScanPurpose::BackupFailover)
            ]
        );
        assert_eq!(
            engine.backup_scan_result(Some(true), 30),
            vec![b_associate()]
        );
    }

    #[test]
    fn unmanaged_network_while_priority_visible_stops() {
        let mut engine = engine();
        engine.start(0, Permission::Authorized, Some("P"));

        assert_eq!(
            engine.observed_change(Some("P"), Some("CoffeeShop"), 10),
            vec![Action::Scan(ScanPurpose::PriorityClassification)]
        );
        assert_eq!(
            engine.classification_result(Some(true), 20),
            vec![
                Action::Stop(StopReason::ManualOverrideUnmanaged),
                Action::RefreshStatus
            ]
        );
        assert!(!engine.snapshot().running);
    }

    #[test]
    fn unmanaged_network_without_priority_recovers_backup() {
        let mut engine = engine();
        engine.start(0, Permission::Authorized, Some("P"));

        engine.observed_change(Some("P"), Some("CoffeeShop"), 10);
        assert_eq!(
            engine.classification_result(Some(false), 20),
            vec![
                Action::Log(LogEvent::TreatingAsFallback),
                Action::Scan(ScanPurpose::BackupRecovery)
            ]
        );
        assert_eq!(
            engine.backup_scan_result(Some(true), 30),
            vec![b_associate()]
        );
    }

    #[test]
    fn unknown_scan_does_not_fail_over_or_stop() {
        let mut engine = engine();
        engine.start(0, Permission::Authorized, Some("P"));
        assert_eq!(
            engine.observed_change(Some("P"), None, 10),
            vec![Action::Scan(ScanPurpose::PriorityClassification)]
        );
        assert_eq!(
            engine.classification_result(None, 20),
            vec![
                Action::Log(LogEvent::PriorityVisibleUnknown),
                Action::RefreshStatus,
            ]
        );
        assert!(engine.snapshot().running);
    }

    #[test]
    fn regular_check_supersedes_stale_classification_and_backup_results() {
        let mut engine = engine();
        engine.start(0, Permission::Authorized, Some("P"));
        assert_eq!(
            engine.observed_change(Some("P"), None, 10),
            vec![Action::Scan(ScanPurpose::PriorityClassification)]
        );

        // A scheduled check replaces the in-flight classification. Results
        // from the old scan chain must not resume failover or recovery.
        assert_eq!(
            engine.check_begin(20, Permission::Authorized, Some("X")),
            vec![Action::Scan(ScanPurpose::PriorityCheck)]
        );
        assert_eq!(
            engine.classification_result(Some(false), 30),
            Vec::<Action>::new()
        );
        assert_eq!(
            engine.backup_scan_result(Some(true), 40),
            Vec::<Action>::new()
        );
        assert_eq!(engine.scan_result(Some(true), 50), vec![p_associate()]);
    }

    #[test]
    fn unknown_scan_after_failing_over_keeps_monitoring() {
        let mut engine = engine();
        engine.start(0, Permission::Authorized, Some("P"));
        engine.observed_change(Some("P"), None, 10);
        engine.classification_result(Some(false), 20);
        assert_eq!(
            engine.backup_scan_result(None, 30),
            vec![
                Action::Log(LogEvent::PriorityVisibleUnknown),
                Action::RefreshStatus,
            ]
        );
        assert!(engine.snapshot().running);
    }

    #[test]
    fn observed_change_while_scanning_classifies_the_new_connection() {
        let mut engine = engine();
        engine.start(0, Permission::Authorized, Some("X"));
        assert_eq!(
            engine.check_begin(10, Permission::Authorized, Some("X")),
            vec![Action::Scan(ScanPurpose::PriorityCheck)]
        );

        // A real P → disconnected → B transition supersedes the in-flight
        // regular scan; the stale scan result must not associate with P.
        assert_eq!(
            engine.observed_change(Some("P"), Some("B"), 20),
            vec![Action::Scan(ScanPurpose::PriorityClassification)]
        );
        assert_eq!(engine.scan_result(Some(true), 30), Vec::<Action>::new());
        assert_eq!(
            engine.classification_result(Some(false), 40),
            vec![Action::Log(LogEvent::SystemJoinedBackup), Action::CheckNow]
        );
        assert!(engine.snapshot().running);
    }

    #[test]
    fn observed_transition_to_priority_supersedes_a_stale_scan() {
        let mut engine = engine();
        engine.start(0, Permission::Authorized, Some("X"));

        assert_eq!(
            engine.observed_change(Some("B"), Some("P"), 10),
            vec![
                Action::Log(LogEvent::PriorityConnected),
                Action::RefreshStatus,
            ]
        );
        // The priority check that started before the SSID transition must not
        // act on its stale result.
        assert_eq!(engine.scan_result(Some(true), 20), Vec::<Action>::new());
    }

    #[test]
    fn regular_check_on_priority_supersedes_a_stale_scan() {
        let mut engine = engine();
        engine.start(0, Permission::Authorized, Some("X"));

        assert_eq!(
            engine.check_begin(10, Permission::Authorized, Some("P")),
            vec![Action::RefreshStatus]
        );
        assert_eq!(engine.scan_result(Some(true), 20), Vec::<Action>::new());
    }

    #[test]
    fn advisory_association_ends_without_a_cooldown() {
        let mut engine = engine();
        engine.start(0, Permission::Authorized, None);
        engine.scan_result(Some(true), 10);
        let generation = engine.association_started("P", 20);
        assert_eq!(
            engine.association_result("P", generation, AssociationOutcome::AdvisoryEnded, 30),
            vec![Action::RefreshStatus]
        );
        assert!(!engine.cooldown_active_for("P", 40));
        assert!(!engine.snapshot().is_associating);
        assert!(engine.snapshot().running);
    }

    #[test]
    fn configuration_change_during_scan_never_uses_stale_target() {
        let mut engine = engine();
        engine.start(0, Permission::Authorized, None);
        engine.set_config("P2", "B");

        assert_eq!(engine.scan_result(Some(true), 10), vec![Action::CheckNow]);

        engine.check_begin(20, Permission::Authorized, None);
        assert_eq!(
            engine.scan_result(Some(true), 30),
            vec![Action::Associate {
                ssid: "P2".to_string(),
                role: Role::Priority,
            }]
        );
    }

    #[test]
    fn switching_to_previous_backup_reconnects_current_backup() {
        let mut engine = engine();
        engine.start(0, Permission::Authorized, Some("P"));
        engine.set_config("P", "B2");

        assert_eq!(
            engine.observed_change(Some("P"), Some("B"), 10),
            vec![
                Action::Log(LogEvent::PreviousBackupReconnect),
                Action::Scan(ScanPurpose::BackupRecovery)
            ]
        );
        assert_eq!(
            engine.backup_scan_result(Some(true), 20),
            vec![Action::Associate {
                ssid: "B2".to_string(),
                role: Role::Backup,
            }]
        );
    }

    #[test]
    fn late_association_success_clears_cooldown_and_keeps_monitoring() {
        let mut engine = engine();
        engine.start(0, Permission::Authorized, Some("X"));
        engine.scan_result(Some(false), 10);
        engine.scan_result(Some(true), 20);
        let generation = engine.association_started("B", 30);

        engine.association_result("B", generation, AssociationOutcome::Timeout, 40);
        assert!(engine.cooldown_active_for("B", 50));

        assert_eq!(
            engine.late_association_result("B", generation, true, 60),
            vec![
                Action::Log(LogEvent::AssociationLateSuccess),
                Action::RefreshStatus
            ]
        );
        assert!(!engine.cooldown_active_for("B", 70));
        assert_eq!(engine.snapshot().role, Role::Backup);
        assert!(engine.snapshot().running);
    }

    #[test]
    fn stop_invalidates_in_flight_association() {
        let mut engine = engine();
        engine.start(0, Permission::Authorized, Some("P"));
        let generation = engine.association_started("P", 10);
        engine.stop();

        assert_eq!(
            engine.association_result("P", generation, AssociationOutcome::Success, 20),
            Vec::<Action>::new()
        );
        assert!(!engine.snapshot().running);
    }

    #[test]
    fn roles_follow_the_configured_slots() {
        let engine = engine();
        assert_eq!(engine.role_for(Some("P")), Role::Priority);
        assert_eq!(engine.role_for(Some("B")), Role::Backup);
        assert_eq!(engine.role_for(Some("Other")), Role::Other);
        assert_eq!(engine.role_for(None), Role::None);
    }
}
