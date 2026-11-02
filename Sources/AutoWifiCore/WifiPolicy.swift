import Foundation
import Darwin
import CAutoWifiCore

/// Swift-facing mirror of the C ABI's `AwPermission`.
public enum WifiPolicyPermission: Int32, Sendable {
    case unknown = 0
    case authorized = 1
    case denied = 2
}

/// Swift-facing mirror of the C ABI's `AwRole`.
public enum WifiPolicyRole: Int32, Sendable {
    case none = 0
    case priority = 1
    case backup = 2
    case other = 3
}

public enum WifiPolicyAssociationOutcome: Int32, Sendable {
    case success = 0
    case timeout = 1
    case failure = 2
}

/// A decision returned by the shared policy core.
public enum WifiPolicyAction: Equatable, Sendable {
    public enum ScanPurpose: Int32, Sendable {
        case priorityCheck = 1
        case backupCheck = 2
        case priorityClassification = 3
        case backupFailover = 4
        case backupRecovery = 5
    }

    public enum StopReason: Int32, Sendable {
        case notConfigured = 1
        case manualOverrideBackup = 2
        case manualOverrideUnmanaged = 3
    }

    public enum LogEvent: Int32, Sendable {
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

    case scan(ScanPurpose)
    case associate(ssid: String, role: WifiPolicyRole)
    case checkNow
    case stop(StopReason)
    case waitForPermission
    case log(LogEvent)
    case refreshStatus
}

public struct WifiPolicySnapshot: Equatable, Sendable {
    public let running: Bool
    public let role: WifiPolicyRole
    public let permission: WifiPolicyPermission
    public let currentSSID: String?
    public let isAssociating: Bool
    public let cooldownUntil: Date?
    public let cooldownTarget: String?
}

/// Loads the Rust policy core at runtime.
///
/// The core is shipped as `libautowifi_core.dylib` next to the app (or in
/// `Contents/Frameworks`). `dlopen` is used deliberately: the macOS target can
/// keep using SwiftPM without an Xcode-built XCFramework, and the same C ABI is
/// consumed by the other platform shells.
private final class WifiPolicyBindings {
    typealias NewFn = @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> OpaquePointer?
    typealias FreeFn = @convention(c) (OpaquePointer?) -> Void
    typealias SetConfigFn = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Void
    typealias SetCooldownFn = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, Int64, Int64) -> Void
    typealias StartFn = @convention(c) (OpaquePointer?, Int64, Int32, UnsafePointer<CChar>?, UnsafeMutablePointer<AwResult>?) -> Void
    typealias StopFn = @convention(c) (OpaquePointer?, UnsafeMutablePointer<AwResult>?) -> Void
    typealias ScanResultFn = @convention(c) (OpaquePointer?, Int32, Int64, UnsafeMutablePointer<AwResult>?) -> Void
    typealias ClassificationResultFn = @convention(c) (OpaquePointer?, Int32, Int64, UnsafeMutablePointer<AwResult>?) -> Void
    typealias AssociationStartedFn = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, Int64) -> UInt64
    typealias AssociationResultFn = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, UInt64, Int32, Int64, UnsafeMutablePointer<AwResult>?) -> Void
    typealias LateAssociationResultFn = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, UInt64, Int32, Int64, UnsafeMutablePointer<AwResult>?) -> Void
    typealias ObservedChangeFn = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?, Int64, UnsafeMutablePointer<AwResult>?) -> Void
    typealias SnapshotFn = @convention(c) (OpaquePointer?, UnsafeMutablePointer<AwSnapshot>?) -> Void
    typealias RoleFn = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> Int32
    typealias CooldownActiveFn = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, Int64) -> Int32
    typealias RecentProgrammaticFn = @convention(c) (OpaquePointer?, Int64) -> Int32
    typealias CurrentGenerationFn = @convention(c) (OpaquePointer?, UInt64) -> Int32

    let handle: UnsafeMutableRawPointer
    let new: NewFn
    let free: FreeFn
    let setConfig: SetConfigFn
    let setCooldown: SetCooldownFn
    let start: StartFn
    let stop: StopFn
    let checkBegin: StartFn
    let scanResult: ScanResultFn
    let classificationResult: ClassificationResultFn
    let backupScanResult: ScanResultFn
    let associationStarted: AssociationStartedFn
    let associationResult: AssociationResultFn
    let lateAssociationResult: LateAssociationResultFn
    let observedChange: ObservedChangeFn
    let snapshot: SnapshotFn
    let role: RoleFn
    let cooldownActive: CooldownActiveFn
    let recentProgrammatic: RecentProgrammaticFn
    let currentGeneration: CurrentGenerationFn

    init?(path: String) {
        guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
            return nil
        }

        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let pointer = dlsym(handle, name) else { return nil }
            return unsafeBitCast(pointer, to: T.self)
        }

        guard
            let new = symbol("aw_engine_new", as: NewFn.self),
            let free = symbol("aw_engine_free", as: FreeFn.self),
            let setConfig = symbol("aw_engine_set_config", as: SetConfigFn.self),
            let setCooldown = symbol("aw_engine_set_persisted_cooldown", as: SetCooldownFn.self),
            let start = symbol("aw_engine_start", as: StartFn.self),
            let stop = symbol("aw_engine_stop", as: StopFn.self),
            let checkBegin = symbol("aw_engine_check_begin", as: StartFn.self),
            let scanResult = symbol("aw_engine_scan_result", as: ScanResultFn.self),
            let classificationResult = symbol("aw_engine_classification_result", as: ClassificationResultFn.self),
            let backupScanResult = symbol("aw_engine_backup_scan_result", as: ScanResultFn.self),
            let associationStarted = symbol("aw_engine_association_started", as: AssociationStartedFn.self),
            let associationResult = symbol("aw_engine_association_result", as: AssociationResultFn.self),
            let lateAssociationResult = symbol("aw_engine_late_association_result", as: LateAssociationResultFn.self),
            let observedChange = symbol("aw_engine_observed_change", as: ObservedChangeFn.self),
            let snapshot = symbol("aw_engine_snapshot", as: SnapshotFn.self),
            let role = symbol("aw_engine_role", as: RoleFn.self),
            let cooldownActive = symbol("aw_engine_cooldown_active", as: CooldownActiveFn.self),
            let recentProgrammatic = symbol("aw_engine_is_recent_programmatic_backup", as: RecentProgrammaticFn.self),
            let currentGeneration = symbol("aw_engine_is_current_generation", as: CurrentGenerationFn.self)
        else {
            dlclose(handle)
            return nil
        }

        self.handle = handle
        self.new = new
        self.free = free
        self.setConfig = setConfig
        self.setCooldown = setCooldown
        self.start = start
        self.stop = stop
        self.checkBegin = checkBegin
        self.scanResult = scanResult
        self.classificationResult = classificationResult
        self.backupScanResult = backupScanResult
        self.associationStarted = associationStarted
        self.associationResult = associationResult
        self.lateAssociationResult = lateAssociationResult
        self.observedChange = observedChange
        self.snapshot = snapshot
        self.role = role
        self.cooldownActive = cooldownActive
        self.recentProgrammatic = recentProgrammatic
        self.currentGeneration = currentGeneration
    }

    deinit {
        dlclose(handle)
    }

    static func load() -> WifiPolicyBindings? {
        for path in candidatePaths() {
            if let bindings = WifiPolicyBindings(path: path) {
                return bindings
            }
        }
        return nil
    }

    static func candidatePaths() -> [String] {
        var paths: [String] = []

        if let explicit = ProcessInfo.processInfo.environment["AUTOWIFI_CORE_PATH"],
           !explicit.isEmpty {
            paths.append(explicit)
        }

        let bundle = Bundle.main
        if let frameworks = bundle.privateFrameworksURL {
            paths.append(frameworks.appendingPathComponent("libautowifi_core.dylib").path)
        }
        paths.append(
            bundle.bundleURL
                .appendingPathComponent("Contents/Frameworks/libautowifi_core.dylib")
                .path
        )
        paths.append(bundle.bundleURL.appendingPathComponent("libautowifi_core.dylib").path)

        var directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<5 {
            paths.append(
                directory.appendingPathComponent("core/target/release/libautowifi_core.dylib").path
            )
            paths.append(
                directory.appendingPathComponent("core/target/debug/libautowifi_core.dylib").path
            )
            directory.deleteLastPathComponent()
        }

        var seen = Set<String>()
        return paths.filter { seen.insert($0).inserted }
    }
}

/// Thin, typed wrapper around the shared policy core.
///
/// Call this from the same main actor that owns the monitoring loop. The
/// underlying engine is not safe for concurrent calls.
public final class WifiPolicyEngine {
    private let bindings: WifiPolicyBindings
    private let handle: OpaquePointer

    nonisolated(unsafe) private static var didLogLoadFailure = false

    public init?(ssidP: String, ssidB: String) {
        guard let bindings = WifiPolicyBindings.load() else {
            Self.logLoadFailure()
            return nil
        }

        let handle: OpaquePointer? = ssidP.withCString { priority in
            ssidB.withCString { backup in
                bindings.new(priority, backup)
            }
        }

        guard let handle else {
            return nil
        }

        self.bindings = bindings
        self.handle = handle
    }

    deinit {
        bindings.free(handle)
    }

    public func setConfig(ssidP: String, ssidB: String) {
        ssidP.withCString { priority in
            ssidB.withCString { backup in
                bindings.setConfig(handle, priority, backup)
            }
        }
    }

    public func setPersistedCooldown(target: String?, until: Date?, now: Date = Date()) {
        withOptionalCString(target) { targetPointer in
            bindings.setCooldown(
                handle,
                targetPointer,
                until.map(Self.milliseconds) ?? 0,
                Self.milliseconds(now)
            )
        }
    }

    public func start(
        now: Date = Date(),
        permission: WifiPolicyPermission,
        currentSSID: String?
    ) -> [WifiPolicyAction] {
        var result = AwResult()
        withOptionalCString(currentSSID) { ssid in
            bindings.start(handle, Self.milliseconds(now), permission.rawValue, ssid, &result)
        }
        return consume(result)
    }

    public func stop() -> [WifiPolicyAction] {
        var result = AwResult()
        bindings.stop(handle, &result)
        return consume(result)
    }

    public func checkBegin(
        now: Date = Date(),
        permission: WifiPolicyPermission,
        currentSSID: String?
    ) -> [WifiPolicyAction] {
        var result = AwResult()
        withOptionalCString(currentSSID) { ssid in
            bindings.checkBegin(
                handle,
                Self.milliseconds(now),
                permission.rawValue,
                ssid,
                &result
            )
        }
        return consume(result)
    }

    public func scanResult(found: Bool, now: Date = Date()) -> [WifiPolicyAction] {
        var result = AwResult()
        bindings.scanResult(handle, found ? 1 : 0, Self.milliseconds(now), &result)
        return consume(result)
    }

    public func classificationResult(
        priorityVisible: Bool,
        now: Date = Date()
    ) -> [WifiPolicyAction] {
        var result = AwResult()
        bindings.classificationResult(
            handle,
            priorityVisible ? 1 : 0,
            Self.milliseconds(now),
            &result
        )
        return consume(result)
    }

    public func backupScanResult(found: Bool, now: Date = Date()) -> [WifiPolicyAction] {
        var result = AwResult()
        bindings.backupScanResult(handle, found ? 1 : 0, Self.milliseconds(now), &result)
        return consume(result)
    }

    public func associationStarted(ssid: String, now: Date = Date()) -> UInt64 {
        ssid.withCString { pointer in
            bindings.associationStarted(handle, pointer, Self.milliseconds(now))
        }
    }

    public func associationResult(
        ssid: String,
        generation: UInt64,
        outcome: WifiPolicyAssociationOutcome,
        now: Date = Date()
    ) -> [WifiPolicyAction] {
        var result = AwResult()
        ssid.withCString { pointer in
            bindings.associationResult(
                handle,
                pointer,
                generation,
                outcome.rawValue,
                Self.milliseconds(now),
                &result
            )
        }
        return consume(result)
    }

    public func lateAssociationResult(
        ssid: String,
        generation: UInt64,
        succeeded: Bool,
        now: Date = Date()
    ) -> [WifiPolicyAction] {
        var result = AwResult()
        ssid.withCString { pointer in
            bindings.lateAssociationResult(
                handle,
                pointer,
                generation,
                succeeded ? 1 : 0,
                Self.milliseconds(now),
                &result
            )
        }
        return consume(result)
    }

    public func observedChange(
        previous: String?,
        new: String?,
        now: Date = Date()
    ) -> [WifiPolicyAction] {
        var result = AwResult()
        withOptionalCString(previous) { previousPointer in
            withOptionalCString(new) { newPointer in
                bindings.observedChange(
                    handle,
                    previousPointer,
                    newPointer,
                    Self.milliseconds(now),
                    &result
                )
            }
        }
        return consume(result)
    }

    public func snapshot() -> WifiPolicySnapshot {
        var raw = AwSnapshot()
        bindings.snapshot(handle, &raw)

        return WifiPolicySnapshot(
            running: raw.running != 0,
            role: WifiPolicyRole(rawValue: raw.role) ?? .none,
            permission: WifiPolicyPermission(rawValue: raw.permission) ?? .unknown,
            currentSSID: raw.current_ssid.map { String(cString: $0) },
            isAssociating: raw.is_associating != 0,
            cooldownUntil: raw.cooldown_until_ms > 0
                ? Date(timeIntervalSince1970: Double(raw.cooldown_until_ms) / 1000)
                : nil,
            cooldownTarget: raw.cooldown_target.map { String(cString: $0) }
        )
    }

    public func role(for ssid: String?) -> WifiPolicyRole {
        guard let ssid else { return .none }
        let raw = ssid.withCString { pointer in
            bindings.role(handle, pointer)
        }
        return WifiPolicyRole(rawValue: raw) ?? .none
    }

    public func cooldownActive(for ssid: String, now: Date = Date()) -> Bool {
        ssid.withCString { pointer in
            bindings.cooldownActive(handle, pointer, Self.milliseconds(now)) != 0
        }
    }

    public func isRecentProgrammaticBackup(now: Date = Date()) -> Bool {
        bindings.recentProgrammatic(handle, Self.milliseconds(now)) != 0
    }

    public func isCurrentGeneration(_ generation: UInt64) -> Bool {
        bindings.currentGeneration(handle, generation) != 0
    }

    private func consume(_ result: AwResult) -> [WifiPolicyAction] {
        guard result.count > 0, let actions = result.actions else {
            return []
        }

        var parsed: [WifiPolicyAction] = []
        parsed.reserveCapacity(Int(result.count))

        for index in 0..<Int(result.count) {
            let raw = actions[index]
            switch raw.kind {
            case 1:
                if let purpose = WifiPolicyAction.ScanPurpose(rawValue: raw.purpose) {
                    parsed.append(.scan(purpose))
                }
            case 2:
                let ssid = raw.ssid.map { String(cString: $0) } ?? ""
                let role = WifiPolicyRole(rawValue: raw.role) ?? .none
                parsed.append(.associate(ssid: ssid, role: role))
            case 3:
                parsed.append(.checkNow)
            case 4:
                if let reason = WifiPolicyAction.StopReason(rawValue: raw.reason) {
                    parsed.append(.stop(reason))
                }
            case 5:
                parsed.append(.waitForPermission)
            case 6:
                if let event = WifiPolicyAction.LogEvent(rawValue: raw.reason) {
                    parsed.append(.log(event))
                }
            case 7:
                parsed.append(.refreshStatus)
            default:
                break
            }
        }

        return parsed
    }

    private func withOptionalCString<T>(
        _ value: String?,
        _ body: (UnsafePointer<CChar>?) -> T
    ) -> T {
        guard let value else { return body(nil) }
        return value.withCString(body)
    }

    private static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    private static func logLoadFailure() {
        guard !didLogLoadFailure else { return }
        didLogLoadFailure = true
        let paths = WifiPolicyBindings.candidatePaths().joined(separator: ", ")
        let message = "AutoWifi: policy core not loaded; checked: \(paths)\n"
        FileHandle.standardError.write(Data(message.utf8))
    }
}
