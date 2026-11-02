import Foundation

enum PolicyPermission: Int32 {
    case unknown = 0
    case authorized = 1
    case denied = 2
}

enum PolicyRole: Int32 {
    case none = 0
    case priority = 1
    case backup = 2
    case other = 3
}

enum PolicyScanPurpose: Int32 {
    case priorityCheck = 1
    case backupCheck = 2
    case priorityClassification = 3
    case backupFailover = 4
    case backupRecovery = 5
}

enum PolicyStopReason: Int32 {
    case notConfigured = 1
    case manualOverrideBackup = 2
    case manualOverrideUnmanaged = 3
}

enum PolicyLogEvent: Int32 {
    case started = 1
    case stopped = 2
    case priorityConnected = 3
    case priorityVisibleWaiting = 4
    case networkDisconnectedWaiting = 5
    case automaticFailover = 6
    case priorityLostConnectingBackup = 7
    case backupConnectedPNotFound = 8
    case neitherFound = 9
    case backupNotFound = 10
    case backupNotFoundWaiting = 11
    case previousBackupReconnect = 12
    case systemJoinedBackup = 13
    case treatingAsFallback = 14
    case cooldownSkipped = 15
    case associationSuccess = 16
    case associationTimeout = 17
    case associationFailure = 18
    case associationLateSuccess = 19
    case associationLateFailure = 20
    case permissionRequired = 21
}

enum PolicyAction: Equatable {
    case scan(PolicyScanPurpose)
    case associate(ssid: String, role: PolicyRole)
    case checkNow
    case stop(PolicyStopReason)
    case waitForPermission
    case log(PolicyLogEvent)
    case refreshStatus
}

struct PolicySnapshot: Equatable {
    let running: Bool
    let role: PolicyRole
    let permission: PolicyPermission
    let currentSSID: String?
    let isAssociating: Bool
    let cooldownUntilMs: Int64
    let cooldownTarget: String?
}

/// Swift wrapper over the shared Rust policy core. The C library is linked as
/// a static XCFramework built by the CI workflow.
final class PolicyEngine {
    private let handle: OpaquePointer

    init?(ssidP: String, ssidB: String) {
        var created: OpaquePointer?
        ssidP.withCString { priority in
            ssidB.withCString { backup in
                created = aw_engine_new(priority, backup)
            }
        }

        guard let created else {
            return nil
        }

        handle = created
    }

    deinit {
        aw_engine_free(handle)
    }

    func setConfig(ssidP: String, ssidB: String) {
        ssidP.withCString { priority in
            ssidB.withCString { backup in
                aw_engine_set_config(handle, priority, backup)
            }
        }
    }

    func start(permission: PolicyPermission, currentSSID: String?) -> [PolicyAction] {
        var result = AwResult()
        withOptionalCString(currentSSID) { ssid in
            aw_engine_start(handle, Self.nowMs(), permission.rawValue, ssid, &result)
        }
        return Self.consume(result)
    }

    func stop() -> [PolicyAction] {
        var result = AwResult()
        aw_engine_stop(handle, &result)
        return Self.consume(result)
    }

    func checkBegin(permission: PolicyPermission, currentSSID: String?) -> [PolicyAction] {
        var result = AwResult()
        withOptionalCString(currentSSID) { ssid in
            aw_engine_check_begin(handle, Self.nowMs(), permission.rawValue, ssid, &result)
        }
        return Self.consume(result)
    }

    func scanResult(found: Bool) -> [PolicyAction] {
        var result = AwResult()
        aw_engine_scan_result(handle, found ? 1 : 0, Self.nowMs(), &result)
        return Self.consume(result)
    }

    func classificationResult(priorityVisible: Bool) -> [PolicyAction] {
        var result = AwResult()
        aw_engine_classification_result(
            handle,
            priorityVisible ? 1 : 0,
            Self.nowMs(),
            &result
        )
        return Self.consume(result)
    }

    func backupScanResult(found: Bool) -> [PolicyAction] {
        var result = AwResult()
        aw_engine_backup_scan_result(handle, found ? 1 : 0, Self.nowMs(), &result)
        return Self.consume(result)
    }

    func associationStarted(ssid: String) -> UInt64 {
        ssid.withCString { value in
            aw_engine_association_started(handle, value, Self.nowMs())
        }
    }

    func associationResult(ssid: String, generation: UInt64, outcome: Int32) -> [PolicyAction] {
        var result = AwResult()
        ssid.withCString { value in
            aw_engine_association_result(
                handle,
                value,
                generation,
                outcome,
                Self.nowMs(),
                &result
            )
        }
        return Self.consume(result)
    }

    func lateAssociationResult(ssid: String, generation: UInt64, succeeded: Bool) -> [PolicyAction] {
        var result = AwResult()
        ssid.withCString { value in
            aw_engine_late_association_result(
                handle,
                value,
                generation,
                succeeded ? 1 : 0,
                Self.nowMs(),
                &result
            )
        }
        return Self.consume(result)
    }

    func observedChange(previous: String?, new: String?) -> [PolicyAction] {
        var result = AwResult()
        withOptionalCString(previous) { previousPointer in
            withOptionalCString(new) { newPointer in
                aw_engine_observed_change(
                    handle,
                    previousPointer,
                    newPointer,
                    Self.nowMs(),
                    &result
                )
            }
        }
        return Self.consume(result)
    }

    func snapshot() -> PolicySnapshot {
        var raw = AwSnapshot()
        aw_engine_snapshot(handle, &raw)
        return PolicySnapshot(
            running: raw.running != 0,
            role: PolicyRole(rawValue: raw.role) ?? .none,
            permission: PolicyPermission(rawValue: raw.permission) ?? .unknown,
            currentSSID: raw.current_ssid.map { String(cString: $0) },
            isAssociating: raw.is_associating != 0,
            cooldownUntilMs: raw.cooldown_until_ms,
            cooldownTarget: raw.cooldown_target.map { String(cString: $0) }
        )
    }

    private func withOptionalCString<T>(
        _ value: String?,
        _ body: (UnsafePointer<CChar>?) -> T
    ) -> T {
        guard let value else {
            return body(nil)
        }
        return value.withCString { body($0) }
    }

    private static func consume(_ result: AwResult) -> [PolicyAction] {
        guard let actions = result.actions else {
            return []
        }

        return (0..<Int(result.count)).compactMap { index in
            let raw = actions[index]
            switch raw.kind {
            case 1:
                return .scan(PolicyScanPurpose(rawValue: raw.purpose) ?? .priorityCheck)
            case 2:
                let ssid = raw.ssid.map { String(cString: $0) } ?? ""
                return .associate(
                    ssid: ssid,
                    role: PolicyRole(rawValue: raw.role) ?? .none
                )
            case 3:
                return .checkNow
            case 4:
                return .stop(PolicyStopReason(rawValue: raw.reason) ?? .notConfigured)
            case 5:
                return .waitForPermission
            case 6:
                return .log(PolicyLogEvent(rawValue: raw.reason) ?? .started)
            case 7:
                return .refreshStatus
            default:
                return nil
            }
        }
    }

    private static func nowMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
}
