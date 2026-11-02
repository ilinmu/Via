//! C ABI for the shared policy core.
//!
//! The ABI is intentionally JSON-free: Swift, Kotlin and C# can call these
//! functions directly. Returned strings and action arrays are owned by the
//! engine and remain valid only until the next call on the same engine.
//!
//! All functions are single-threaded: call them from the UI/main thread that
//! owns the native monitoring loop.

use std::ffi::{CStr, CString};
use std::os::raw::c_char;

use autowifi_domain::{
    Action, AssociationOutcome, Config, Engine, LogEvent, Permission, Role, ScanPurpose, Snapshot,
    StopReason,
};

#[repr(C)]
pub struct AwAction {
    pub kind: i32,
    pub role: i32,
    pub reason: i32,
    pub purpose: i32,
    pub delay_ms: i64,
    pub ssid: *const c_char,
}

#[repr(C)]
pub struct AwSnapshot {
    pub running: i32,
    pub role: i32,
    pub permission: i32,
    pub is_associating: i32,
    pub cooldown_until_ms: i64,
    pub current_ssid: *const c_char,
    pub cooldown_target: *const c_char,
}

#[repr(C)]
pub struct AwResult {
    pub count: i32,
    pub actions: *const AwAction,
    pub snapshot: AwSnapshot,
}

pub struct AwEngine {
    inner: Engine,
    actions: Vec<AwAction>,
    strings: Vec<CString>,
    current_ssid: Option<CString>,
    cooldown_target: Option<CString>,
}

impl AwEngine {
    fn new(config: Config) -> Self {
        Self {
            inner: Engine::new(config),
            actions: Vec::new(),
            strings: Vec::new(),
            current_ssid: None,
            cooldown_target: None,
        }
    }
}

fn role_code(role: Role) -> i32 {
    match role {
        Role::None => 0,
        Role::Priority => 1,
        Role::Backup => 2,
        Role::Other => 3,
    }
}

fn permission_code(permission: Permission) -> i32 {
    match permission {
        Permission::Unknown => 0,
        Permission::Authorized => 1,
        Permission::Denied => 2,
    }
}

fn permission_from_code(code: i32) -> Permission {
    match code {
        1 => Permission::Authorized,
        2 => Permission::Denied,
        _ => Permission::Unknown,
    }
}

fn scan_code(purpose: ScanPurpose) -> i32 {
    match purpose {
        ScanPurpose::PriorityCheck => 1,
        ScanPurpose::BackupCheck => 2,
        ScanPurpose::PriorityClassification => 3,
        ScanPurpose::BackupFailover => 4,
        ScanPurpose::BackupRecovery => 5,
    }
}

fn stop_code(reason: StopReason) -> i32 {
    match reason {
        StopReason::NotConfigured => 1,
        StopReason::ManualOverrideBackup => 2,
        StopReason::ManualOverrideUnmanaged => 3,
    }
}

fn log_code(event: LogEvent) -> i32 {
    match event {
        LogEvent::Started => 1,
        LogEvent::Stopped => 2,
        LogEvent::PriorityConnected => 3,
        LogEvent::PriorityVisibleWaiting => 4,
        LogEvent::NetworkDisconnectedWaiting => 5,
        LogEvent::AutomaticFailover => 6,
        LogEvent::PriorityLostConnectingBackup => 7,
        LogEvent::BackupConnectedPNotFound => 8,
        LogEvent::NeitherFound => 9,
        LogEvent::BackupNotFound => 10,
        LogEvent::BackupNotFoundWaiting => 11,
        LogEvent::PreviousBackupReconnect => 12,
        LogEvent::SystemJoinedBackup => 13,
        LogEvent::TreatingAsFallback => 14,
        LogEvent::CooldownSkipped => 15,
        LogEvent::AssociationSuccess => 16,
        LogEvent::AssociationTimeout => 17,
        LogEvent::AssociationFailure => 18,
        LogEvent::AssociationLateSuccess => 19,
        LogEvent::AssociationLateFailure => 20,
        LogEvent::PermissionRequired => 21,
    }
}

fn outcome_from_code(code: i32) -> AssociationOutcome {
    match code {
        0 => AssociationOutcome::Success,
        2 => AssociationOutcome::Failure,
        _ => AssociationOutcome::Timeout,
    }
}

unsafe fn opt_string(ptr: *const c_char) -> Option<String> {
    if ptr.is_null() {
        return None;
    }
    let value = CStr::from_ptr(ptr).to_string_lossy();
    if value.is_empty() {
        None
    } else {
        Some(value.into_owned())
    }
}

unsafe fn req_string(ptr: *const c_char) -> String {
    opt_string(ptr).unwrap_or_default()
}

fn render_actions(engine: &mut AwEngine, actions: Vec<Action>) {
    let mut strings: Vec<CString> = Vec::new();
    let mut rendered: Vec<AwAction> = Vec::with_capacity(actions.len());

    for action in actions {
        let mut raw = AwAction {
            kind: 0,
            role: 0,
            reason: 0,
            purpose: 0,
            delay_ms: 0,
            ssid: std::ptr::null(),
        };

        match action {
            Action::Scan(purpose) => {
                raw.kind = 1;
                raw.purpose = scan_code(purpose);
            }
            Action::Associate { ssid, role } => {
                raw.kind = 2;
                raw.role = role_code(role);
                if let Ok(value) = CString::new(ssid) {
                    raw.ssid = value.as_ptr();
                    // Moving the CString into the Vec does not move its heap
                    // buffer, so the pointer stays valid until the next call.
                    strings.push(value);
                }
            }
            Action::CheckNow => raw.kind = 3,
            Action::Stop(reason) => {
                raw.kind = 4;
                raw.reason = stop_code(reason);
            }
            Action::WaitForPermission => raw.kind = 5,
            Action::Log(event) => {
                raw.kind = 6;
                raw.reason = log_code(event);
            }
            Action::RefreshStatus => raw.kind = 7,
        }

        rendered.push(raw);
    }

    engine.strings = strings;
    engine.actions = rendered;
}

fn make_snapshot(engine: &mut AwEngine) -> AwSnapshot {
    let snapshot: Snapshot = engine.inner.snapshot();
    engine.current_ssid = snapshot
        .current_ssid
        .as_deref()
        .and_then(|ssid| CString::new(ssid).ok());
    engine.cooldown_target = snapshot
        .cooldown_target
        .as_deref()
        .and_then(|ssid| CString::new(ssid).ok());

    AwSnapshot {
        running: if snapshot.running { 1 } else { 0 },
        role: role_code(snapshot.role),
        permission: permission_code(snapshot.permission),
        is_associating: if snapshot.is_associating { 1 } else { 0 },
        cooldown_until_ms: snapshot
            .cooldown_until_ms
            .map(|value| value as i64)
            .unwrap_or(0),
        current_ssid: engine
            .current_ssid
            .as_ref()
            .map_or(std::ptr::null(), |value| value.as_ptr()),
        cooldown_target: engine
            .cooldown_target
            .as_ref()
            .map_or(std::ptr::null(), |value| value.as_ptr()),
    }
}

unsafe fn write_result(engine: &mut AwEngine, actions: Vec<Action>, out: *mut AwResult) {
    if out.is_null() {
        return;
    }

    render_actions(engine, actions);
    let snapshot = make_snapshot(engine);
    let actions_ptr = if engine.actions.is_empty() {
        std::ptr::null()
    } else {
        engine.actions.as_ptr()
    };

    *out = AwResult {
        count: engine.actions.len() as i32,
        actions: actions_ptr,
        snapshot,
    };
}

#[no_mangle]
pub unsafe extern "C" fn aw_engine_new(
    ssid_p: *const c_char,
    ssid_b: *const c_char,
) -> *mut AwEngine {
    let config = Config::new(req_string(ssid_p), req_string(ssid_b));
    Box::into_raw(Box::new(AwEngine::new(config)))
}

#[no_mangle]
pub unsafe extern "C" fn aw_engine_free(engine: *mut AwEngine) {
    if !engine.is_null() {
        drop(Box::from_raw(engine));
    }
}

#[no_mangle]
pub unsafe extern "C" fn aw_engine_set_config(
    engine: *mut AwEngine,
    ssid_p: *const c_char,
    ssid_b: *const c_char,
) {
    let Some(engine) = engine.as_mut() else {
        return;
    };
    engine
        .inner
        .set_config(req_string(ssid_p), req_string(ssid_b));
}

#[no_mangle]
pub unsafe extern "C" fn aw_engine_set_persisted_cooldown(
    engine: *mut AwEngine,
    target: *const c_char,
    until_ms: i64,
    now_ms: i64,
) {
    let Some(engine) = engine.as_mut() else {
        return;
    };
    let target = opt_string(target);
    let until = if until_ms > 0 {
        Some(until_ms as u64)
    } else {
        None
    };
    engine
        .inner
        .set_persisted_cooldown(target, until, now_ms.max(0) as u64);
}

#[no_mangle]
pub unsafe extern "C" fn aw_engine_start(
    engine: *mut AwEngine,
    now_ms: i64,
    permission: i32,
    current_ssid: *const c_char,
    out: *mut AwResult,
) {
    let Some(engine) = engine.as_mut() else {
        return;
    };
    let current = opt_string(current_ssid);
    let actions = engine.inner.start(
        now_ms.max(0) as u64,
        permission_from_code(permission),
        current.as_deref(),
    );
    write_result(engine, actions, out);
}

#[no_mangle]
pub unsafe extern "C" fn aw_engine_stop(engine: *mut AwEngine, out: *mut AwResult) {
    let Some(engine) = engine.as_mut() else {
        return;
    };
    let actions = engine.inner.stop();
    write_result(engine, actions, out);
}

#[no_mangle]
pub unsafe extern "C" fn aw_engine_check_begin(
    engine: *mut AwEngine,
    now_ms: i64,
    permission: i32,
    current_ssid: *const c_char,
    out: *mut AwResult,
) {
    let Some(engine) = engine.as_mut() else {
        return;
    };
    let current = opt_string(current_ssid);
    let actions = engine.inner.check_begin(
        now_ms.max(0) as u64,
        permission_from_code(permission),
        current.as_deref(),
    );
    write_result(engine, actions, out);
}

#[no_mangle]
pub unsafe extern "C" fn aw_engine_scan_result(
    engine: *mut AwEngine,
    found: i32,
    now_ms: i64,
    out: *mut AwResult,
) {
    let Some(engine) = engine.as_mut() else {
        return;
    };
    let actions = engine.inner.scan_result(found != 0, now_ms.max(0) as u64);
    write_result(engine, actions, out);
}

#[no_mangle]
pub unsafe extern "C" fn aw_engine_classification_result(
    engine: *mut AwEngine,
    priority_visible: i32,
    now_ms: i64,
    out: *mut AwResult,
) {
    let Some(engine) = engine.as_mut() else {
        return;
    };
    let actions = engine
        .inner
        .classification_result(priority_visible != 0, now_ms.max(0) as u64);
    write_result(engine, actions, out);
}

#[no_mangle]
pub unsafe extern "C" fn aw_engine_backup_scan_result(
    engine: *mut AwEngine,
    found: i32,
    now_ms: i64,
    out: *mut AwResult,
) {
    let Some(engine) = engine.as_mut() else {
        return;
    };
    let actions = engine
        .inner
        .backup_scan_result(found != 0, now_ms.max(0) as u64);
    write_result(engine, actions, out);
}

#[no_mangle]
pub unsafe extern "C" fn aw_engine_association_started(
    engine: *mut AwEngine,
    ssid: *const c_char,
    now_ms: i64,
) -> u64 {
    let Some(engine) = engine.as_mut() else {
        return 0;
    };
    let ssid = req_string(ssid);
    engine
        .inner
        .association_started(&ssid, now_ms.max(0) as u64)
}

#[no_mangle]
pub unsafe extern "C" fn aw_engine_association_result(
    engine: *mut AwEngine,
    ssid: *const c_char,
    generation: u64,
    outcome: i32,
    now_ms: i64,
    out: *mut AwResult,
) {
    let Some(engine) = engine.as_mut() else {
        return;
    };
    let ssid = req_string(ssid);
    let actions = engine.inner.association_result(
        &ssid,
        generation,
        outcome_from_code(outcome),
        now_ms.max(0) as u64,
    );
    write_result(engine, actions, out);
}

#[no_mangle]
pub unsafe extern "C" fn aw_engine_late_association_result(
    engine: *mut AwEngine,
    ssid: *const c_char,
    generation: u64,
    succeeded: i32,
    now_ms: i64,
    out: *mut AwResult,
) {
    let Some(engine) = engine.as_mut() else {
        return;
    };
    let ssid = req_string(ssid);
    let actions = engine.inner.late_association_result(
        &ssid,
        generation,
        succeeded != 0,
        now_ms.max(0) as u64,
    );
    write_result(engine, actions, out);
}

#[no_mangle]
pub unsafe extern "C" fn aw_engine_observed_change(
    engine: *mut AwEngine,
    previous_ssid: *const c_char,
    new_ssid: *const c_char,
    now_ms: i64,
    out: *mut AwResult,
) {
    let Some(engine) = engine.as_mut() else {
        return;
    };
    let previous = opt_string(previous_ssid);
    let new = opt_string(new_ssid);
    let actions = engine.inner.observed_change(
        previous.as_deref(),
        new.as_deref(),
        now_ms.max(0) as u64,
    );
    write_result(engine, actions, out);
}

#[no_mangle]
pub unsafe extern "C" fn aw_engine_snapshot(engine: *const AwEngine, out: *mut AwSnapshot) {
    if engine.is_null() || out.is_null() {
        return;
    }
    let engine = &mut *(engine as *mut AwEngine);
    *out = make_snapshot(engine);
}

#[no_mangle]
pub unsafe extern "C" fn aw_engine_role(engine: *const AwEngine, ssid: *const c_char) -> i32 {
    let Some(engine) = engine.as_ref() else {
        return 0;
    };
    let ssid = opt_string(ssid);
    role_code(engine.inner.role_for(ssid.as_deref()))
}

#[no_mangle]
pub unsafe extern "C" fn aw_engine_cooldown_active(
    engine: *const AwEngine,
    ssid: *const c_char,
    now_ms: i64,
) -> i32 {
    let Some(engine) = engine.as_ref() else {
        return 0;
    };
    let Some(ssid) = opt_string(ssid) else {
        return 0;
    };
    if engine
        .inner
        .cooldown_active_for(&ssid, now_ms.max(0) as u64)
    {
        1
    } else {
        0
    }
}

#[no_mangle]
pub unsafe extern "C" fn aw_engine_is_recent_programmatic_backup(
    engine: *const AwEngine,
    now_ms: i64,
) -> i32 {
    let Some(engine) = engine.as_ref() else {
        return 0;
    };
    if engine
        .inner
        .is_recent_programmatic_backup(now_ms.max(0) as u64)
    {
        1
    } else {
        0
    }
}

#[no_mangle]
pub unsafe extern "C" fn aw_engine_is_current_generation(
    engine: *const AwEngine,
    generation: u64,
) -> i32 {
    let Some(engine) = engine.as_ref() else {
        return 0;
    };
    if engine.inner.is_current_generation(generation) {
        1
    } else {
        0
    }
}
