//! JNI bridge for the Android shell.
//!
//! Kotlin owns the UI and Wi-Fi APIs; this bridge only exposes the shared
//! policy engine. Results are JSON strings so the ABI stays small and stable
//! even when the platform shell adds fields.

use jni::objects::{JObject, JString};
use jni::sys::{jboolean, jint, jlong, jstring};
use jni::JNIEnv;
use serde_json::{json, Value};
use via_domain::{
    Action, AssociationOutcome, Config, Engine, LogEvent, Permission, Role, ScanPurpose, Snapshot,
    StopReason,
};

fn read_string(env: &mut JNIEnv, value: JString) -> String {
    env.get_string(&value)
        .map(|text| text.to_string_lossy().into_owned())
        .unwrap_or_default()
}

fn optional(value: String) -> Option<String> {
    if value.is_empty() {
        None
    } else {
        Some(value)
    }
}

fn to_jstring(env: &mut JNIEnv, value: String) -> jstring {
    env.new_string(value)
        .map(|text| text.into_raw())
        .unwrap_or(std::ptr::null_mut())
}

fn role_name(role: Role) -> &'static str {
    match role {
        Role::None => "none",
        Role::Priority => "priority",
        Role::Backup => "backup",
        Role::Other => "other",
    }
}

fn permission_name(permission: Permission) -> &'static str {
    match permission {
        Permission::Unknown => "unknown",
        Permission::Authorized => "authorized",
        Permission::Denied => "denied",
    }
}

fn scan_name(purpose: ScanPurpose) -> &'static str {
    match purpose {
        ScanPurpose::PriorityCheck => "priorityCheck",
        ScanPurpose::BackupCheck => "backupCheck",
        ScanPurpose::PriorityClassification => "priorityClassification",
        ScanPurpose::BackupFailover => "backupFailover",
        ScanPurpose::BackupRecovery => "backupRecovery",
    }
}

fn stop_name(reason: StopReason) -> &'static str {
    match reason {
        StopReason::NotConfigured => "notConfigured",
        StopReason::ManualOverrideBackup => "manualOverrideBackup",
        StopReason::ManualOverrideUnmanaged => "manualOverrideUnmanaged",
    }
}

fn log_name(event: LogEvent) -> &'static str {
    match event {
        LogEvent::Started => "started",
        LogEvent::Stopped => "stopped",
        LogEvent::PriorityConnected => "priorityConnected",
        LogEvent::PriorityVisibleWaiting => "priorityVisibleWaiting",
        LogEvent::NetworkDisconnectedWaiting => "networkDisconnectedWaiting",
        LogEvent::AutomaticFailover => "automaticFailover",
        LogEvent::PriorityLostConnectingBackup => "priorityLostConnectingBackup",
        LogEvent::BackupConnectedPNotFound => "backupConnectedPNotFound",
        LogEvent::NeitherFound => "neitherFound",
        LogEvent::BackupNotFound => "backupNotFound",
        LogEvent::BackupNotFoundWaiting => "backupNotFoundWaiting",
        LogEvent::PreviousBackupReconnect => "previousBackupReconnect",
        LogEvent::SystemJoinedBackup => "systemJoinedBackup",
        LogEvent::TreatingAsFallback => "treatingAsFallback",
        LogEvent::CooldownSkipped => "cooldownSkipped",
        LogEvent::AssociationSuccess => "associationSuccess",
        LogEvent::AssociationTimeout => "associationTimeout",
        LogEvent::AssociationFailure => "associationFailure",
        LogEvent::AssociationLateSuccess => "associationLateSuccess",
        LogEvent::AssociationLateFailure => "associationLateFailure",
        LogEvent::PermissionRequired => "permissionRequired",
        LogEvent::PriorityVisibleUnknown => "priorityVisibleUnknown",
    }
}

fn action_json(action: &Action) -> Value {
    match action {
        Action::Scan(purpose) => json!({
            "kind": "scan",
            "purpose": scan_name(*purpose),
        }),
        Action::Associate { ssid, role } => json!({
            "kind": "associate",
            "ssid": ssid,
            "role": role_name(*role),
        }),
        Action::CheckNow => json!({ "kind": "checkNow" }),
        Action::Stop(reason) => json!({
            "kind": "stop",
            "reason": stop_name(*reason),
        }),
        Action::WaitForPermission => json!({ "kind": "waitForPermission" }),
        Action::Log(event) => json!({
            "kind": "log",
            "event": log_name(*event),
        }),
        Action::RefreshStatus => json!({ "kind": "refreshStatus" }),
    }
}

fn snapshot_json(snapshot: &Snapshot) -> Value {
    json!({
        "running": snapshot.running,
        "role": role_name(snapshot.role),
        "permission": permission_name(snapshot.permission),
        "currentSsid": snapshot.current_ssid,
        "isAssociating": snapshot.is_associating,
        "cooldownUntilMs": snapshot.cooldown_until_ms,
        "cooldownTarget": snapshot.cooldown_target,
    })
}

fn result_json(engine: &Engine, actions: Vec<Action>) -> String {
    let actions: Vec<Value> = actions.iter().map(action_json).collect();
    json!({
        "actions": actions,
        "snapshot": snapshot_json(&engine.snapshot()),
    })
    .to_string()
}

fn engine_ref<'a>(handle: jlong) -> Option<&'a Engine> {
    if handle == 0 {
        None
    } else {
        unsafe { Some(&*(handle as *const Engine)) }
    }
}

fn engine_mut<'a>(handle: jlong) -> Option<&'a mut Engine> {
    if handle == 0 {
        None
    } else {
        unsafe { Some(&mut *(handle as *mut Engine)) }
    }
}

fn outcome_from_code(code: jint) -> AssociationOutcome {
    match code {
        0 => AssociationOutcome::Success,
        2 => AssociationOutcome::Failure,
        3 => AssociationOutcome::AdvisoryEnded,
        _ => AssociationOutcome::Timeout,
    }
}

/// -1 = unknown, 0 = absent, 1 = visible.
fn opt_found(code: jint) -> Option<bool> {
    match code {
        0 => Some(false),
        1 => Some(true),
        _ => None,
    }
}

#[no_mangle]
pub extern "system" fn Java_io_github_ilinmu_via_policy_PolicyEngine_nativeNew(
    mut env: JNIEnv,
    _this: JObject,
    ssid_p: JString,
    ssid_b: JString,
) -> jlong {
    let ssid_p = read_string(&mut env, ssid_p);
    let ssid_b = read_string(&mut env, ssid_b);
    let engine = Engine::new(Config::new(ssid_p, ssid_b));
    Box::into_raw(Box::new(engine)) as jlong
}

#[no_mangle]
pub extern "system" fn Java_io_github_ilinmu_via_policy_PolicyEngine_nativeFree(
    _env: JNIEnv,
    _this: JObject,
    handle: jlong,
) {
    if handle != 0 {
        unsafe {
            drop(Box::from_raw(handle as *mut Engine));
        }
    }
}

#[no_mangle]
pub extern "system" fn Java_io_github_ilinmu_via_policy_PolicyEngine_nativeSetConfig(
    mut env: JNIEnv,
    _this: JObject,
    handle: jlong,
    ssid_p: JString,
    ssid_b: JString,
) {
    let Some(engine) = engine_mut(handle) else {
        return;
    };
    engine.set_config(read_string(&mut env, ssid_p), read_string(&mut env, ssid_b));
}

#[no_mangle]
pub extern "system" fn Java_io_github_ilinmu_via_policy_PolicyEngine_nativeStart(
    mut env: JNIEnv,
    _this: JObject,
    handle: jlong,
    now_ms: jlong,
    permission: jint,
    current_ssid: JString,
) -> jstring {
    let Some(engine) = engine_mut(handle) else {
        return std::ptr::null_mut();
    };
    let current = optional(read_string(&mut env, current_ssid));
    let actions = engine.start(
        now_ms.max(0) as u64,
        permission_from_code(permission),
        current.as_deref(),
    );
    to_jstring(&mut env, result_json(engine, actions))
}

#[no_mangle]
pub extern "system" fn Java_io_github_ilinmu_via_policy_PolicyEngine_nativeStop(
    mut env: JNIEnv,
    _this: JObject,
    handle: jlong,
) -> jstring {
    let Some(engine) = engine_mut(handle) else {
        return std::ptr::null_mut();
    };
    let actions = engine.stop();
    to_jstring(&mut env, result_json(engine, actions))
}

#[no_mangle]
pub extern "system" fn Java_io_github_ilinmu_via_policy_PolicyEngine_nativeCheckBegin(
    mut env: JNIEnv,
    _this: JObject,
    handle: jlong,
    now_ms: jlong,
    permission: jint,
    current_ssid: JString,
) -> jstring {
    let Some(engine) = engine_mut(handle) else {
        return std::ptr::null_mut();
    };
    let current = optional(read_string(&mut env, current_ssid));
    let actions = engine.check_begin(
        now_ms.max(0) as u64,
        permission_from_code(permission),
        current.as_deref(),
    );
    to_jstring(&mut env, result_json(engine, actions))
}

#[no_mangle]
pub extern "system" fn Java_io_github_ilinmu_via_policy_PolicyEngine_nativeScanResult(
    mut env: JNIEnv,
    _this: JObject,
    handle: jlong,
    found: jint,
    now_ms: jlong,
) -> jstring {
    let Some(engine) = engine_mut(handle) else {
        return std::ptr::null_mut();
    };
    let actions = engine.scan_result(opt_found(found), now_ms.max(0) as u64);
    to_jstring(&mut env, result_json(engine, actions))
}

#[no_mangle]
pub extern "system" fn Java_io_github_ilinmu_via_policy_PolicyEngine_nativeClassificationResult(
    mut env: JNIEnv,
    _this: JObject,
    handle: jlong,
    priority_visible: jint,
    now_ms: jlong,
) -> jstring {
    let Some(engine) = engine_mut(handle) else {
        return std::ptr::null_mut();
    };
    let actions = engine.classification_result(opt_found(priority_visible), now_ms.max(0) as u64);
    to_jstring(&mut env, result_json(engine, actions))
}

#[no_mangle]
pub extern "system" fn Java_io_github_ilinmu_via_policy_PolicyEngine_nativeBackupScanResult(
    mut env: JNIEnv,
    _this: JObject,
    handle: jlong,
    found: jint,
    now_ms: jlong,
) -> jstring {
    let Some(engine) = engine_mut(handle) else {
        return std::ptr::null_mut();
    };
    let actions = engine.backup_scan_result(opt_found(found), now_ms.max(0) as u64);
    to_jstring(&mut env, result_json(engine, actions))
}

#[no_mangle]
pub extern "system" fn Java_io_github_ilinmu_via_policy_PolicyEngine_nativeAssociationStarted(
    mut env: JNIEnv,
    _this: JObject,
    handle: jlong,
    ssid: JString,
    now_ms: jlong,
) -> jlong {
    let Some(engine) = engine_mut(handle) else {
        return 0;
    };
    let ssid = read_string(&mut env, ssid);
    engine.association_started(&ssid, now_ms.max(0) as u64) as jlong
}

#[no_mangle]
pub extern "system" fn Java_io_github_ilinmu_via_policy_PolicyEngine_nativeAssociationResult(
    mut env: JNIEnv,
    _this: JObject,
    handle: jlong,
    ssid: JString,
    generation: jlong,
    outcome: jint,
    now_ms: jlong,
) -> jstring {
    let Some(engine) = engine_mut(handle) else {
        return std::ptr::null_mut();
    };
    let ssid = read_string(&mut env, ssid);
    let actions = engine.association_result(
        &ssid,
        generation as u64,
        outcome_from_code(outcome),
        now_ms.max(0) as u64,
    );
    to_jstring(&mut env, result_json(engine, actions))
}

#[no_mangle]
pub extern "system" fn Java_io_github_ilinmu_via_policy_PolicyEngine_nativeLateAssociationResult(
    mut env: JNIEnv,
    _this: JObject,
    handle: jlong,
    ssid: JString,
    generation: jlong,
    succeeded: jboolean,
    now_ms: jlong,
) -> jstring {
    let Some(engine) = engine_mut(handle) else {
        return std::ptr::null_mut();
    };
    let ssid = read_string(&mut env, ssid);
    let actions = engine.late_association_result(
        &ssid,
        generation as u64,
        succeeded != 0,
        now_ms.max(0) as u64,
    );
    to_jstring(&mut env, result_json(engine, actions))
}

#[no_mangle]
pub extern "system" fn Java_io_github_ilinmu_via_policy_PolicyEngine_nativeObservedChange(
    mut env: JNIEnv,
    _this: JObject,
    handle: jlong,
    previous_ssid: JString,
    new_ssid: JString,
    now_ms: jlong,
) -> jstring {
    let Some(engine) = engine_mut(handle) else {
        return std::ptr::null_mut();
    };
    let previous = optional(read_string(&mut env, previous_ssid));
    let new = optional(read_string(&mut env, new_ssid));
    let actions = engine.observed_change(previous.as_deref(), new.as_deref(), now_ms.max(0) as u64);
    to_jstring(&mut env, result_json(engine, actions))
}

#[no_mangle]
pub extern "system" fn Java_io_github_ilinmu_via_policy_PolicyEngine_nativeSnapshot(
    mut env: JNIEnv,
    _this: JObject,
    handle: jlong,
) -> jstring {
    let Some(engine) = engine_ref(handle) else {
        return std::ptr::null_mut();
    };
    to_jstring(&mut env, snapshot_json(&engine.snapshot()).to_string())
}

#[no_mangle]
pub extern "system" fn Java_io_github_ilinmu_via_policy_PolicyEngine_nativeRole(
    mut env: JNIEnv,
    _this: JObject,
    handle: jlong,
    ssid: JString,
) -> jint {
    let Some(engine) = engine_ref(handle) else {
        return 0;
    };
    let ssid = read_string(&mut env, ssid);
    role_code(engine.role_for(Some(&ssid)))
}

#[no_mangle]
pub extern "system" fn Java_io_github_ilinmu_via_policy_PolicyEngine_nativeCooldownActive(
    mut env: JNIEnv,
    _this: JObject,
    handle: jlong,
    ssid: JString,
    now_ms: jlong,
) -> jboolean {
    let Some(engine) = engine_ref(handle) else {
        return 0;
    };
    let ssid = read_string(&mut env, ssid);
    if engine.cooldown_active_for(&ssid, now_ms.max(0) as u64) {
        1
    } else {
        0
    }
}

#[no_mangle]
pub extern "system" fn Java_io_github_ilinmu_via_policy_PolicyEngine_nativeIsRecentProgrammaticBackup(
    _env: JNIEnv,
    _this: JObject,
    handle: jlong,
    now_ms: jlong,
) -> jboolean {
    let Some(engine) = engine_ref(handle) else {
        return 0;
    };
    if engine.is_recent_programmatic_backup(now_ms.max(0) as u64) {
        1
    } else {
        0
    }
}

#[no_mangle]
pub extern "system" fn Java_io_github_ilinmu_via_policy_PolicyEngine_nativeIsCurrentGeneration(
    _env: JNIEnv,
    _this: JObject,
    handle: jlong,
    generation: jlong,
) -> jboolean {
    let Some(engine) = engine_ref(handle) else {
        return 0;
    };
    if engine.is_current_generation(generation as u64) {
        1
    } else {
        0
    }
}

fn permission_from_code(code: jint) -> Permission {
    match code {
        1 => Permission::Authorized,
        2 => Permission::Denied,
        _ => Permission::Unknown,
    }
}

fn role_code(role: Role) -> jint {
    match role {
        Role::None => 0,
        Role::Priority => 1,
        Role::Backup => 2,
        Role::Other => 3,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn action_json_serializes_scan_and_associate() {
        assert_eq!(
            action_json(&Action::Scan(ScanPurpose::BackupFailover)),
            json!({ "kind": "scan", "purpose": "backupFailover" })
        );
        assert_eq!(
            action_json(&Action::Associate {
                ssid: "P".to_string(),
                role: Role::Priority,
            }),
            json!({ "kind": "associate", "ssid": "P", "role": "priority" })
        );
    }

    #[test]
    fn result_json_contains_actions_and_snapshot() {
        let engine = Engine::new(Config::new("P", "B"));
        let value: Value =
            serde_json::from_str(&result_json(&engine, vec![Action::RefreshStatus])).unwrap();
        assert_eq!(value["actions"][0]["kind"], "refreshStatus");
        assert_eq!(value["snapshot"]["running"], false);
        assert_eq!(value["snapshot"]["role"], "none");
    }

    #[test]
    fn scan_codes_distinguish_unknown_from_absent() {
        assert_eq!(opt_found(1), Some(true));
        assert_eq!(opt_found(0), Some(false));
        assert_eq!(opt_found(-1), None);
    }

    #[test]
    fn permission_codes_are_stable() {
        assert_eq!(permission_from_code(0), Permission::Unknown);
        assert_eq!(permission_from_code(1), Permission::Authorized);
        assert_eq!(permission_from_code(2), Permission::Denied);
    }
}
