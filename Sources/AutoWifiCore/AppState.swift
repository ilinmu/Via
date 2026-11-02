import Foundation
import Combine
import OSLog

@MainActor
public class AppState: ObservableObject {
    private static let logger = Logger(subsystem: "com.linmu.AutoWifi", category: "runtime")
    private static let diagnosticLogger = Logger(subsystem: "com.linmu.AutoWifi", category: "diagnostic")
    public static let defaultCheckInterval: Double = 60
    public static let minimumCheckInterval: Double = 5
    public static let maximumCheckInterval: Double = 3600

    private static let logTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter
    }()

    private enum DefaultsKey {
        static let ssidP = "ssidP"
        static let ssidB = "ssidB"
        static let checkInterval = "checkInterval"
        static let passwordP = "passwordP"
        static let passwordB = "passwordB"
        static let isRunning = "isRunning"
        static let associationCooldownUntil = "associationCooldownUntil"
    }

    @Published public var ssidP: String {
        didSet { userDefaults.set(ssidP, forKey: DefaultsKey.ssidP) }
    }
    @Published public var passwordP: String {
        didSet { persistPassword(passwordP, account: CredentialAccount.priority) }
    }
    @Published public var ssidB: String {
        didSet { userDefaults.set(ssidB, forKey: DefaultsKey.ssidB) }
    }
    @Published public var passwordB: String {
        didSet { persistPassword(passwordB, account: CredentialAccount.backup) }
    }
    @Published public var checkInterval: Double {
        didSet { persistCheckInterval() }
    }
    @Published public var isRunning: Bool {
        didSet { userDefaults.set(isRunning, forKey: DefaultsKey.isRunning) }
    }

    /// Runtime log text. The settings panel does not display these fields, so
    /// they are deliberately not `@Published`: writing them must not rebuild
    /// the whole SwiftUI view tree on every log line.
    public internal(set) var currentStatus: String = "Ready"
    public internal(set) var lastLog: String = ""
    public internal(set) var interfaceStatus: String = "Detecting Wi-Fi interface..."

    public enum ConnectedNetworkType: Hashable {
        case none
        case priority
        case backup
        case other
    }

    public enum NetworkStatus: Equatable {
        case connected(ssid: String, role: ConnectedNetworkType)
        case notConnected
        case permissionPending
        case permissionDenied
        case noInterface
    }

    @Published public private(set) var networkStatus: NetworkStatus = .notConnected

    public enum CredentialStorageWarning: Equatable, Sendable {
        case readFailed(account: String)
        case migrationFailed(account: String)
        case writeFailed(account: String)

        public var account: String {
            switch self {
            case let .readFailed(account),
                 let .migrationFailed(account),
                 let .writeFailed(account):
                return account
            }
        }
    }

    /// A non-fatal password storage problem that should stay visible in the
    /// settings panel. Legacy plaintext is deliberately retained when migration
    /// fails so a keychain error cannot destroy the only stored copy.
    @Published public private(set) var credentialStorageWarning: CredentialStorageWarning?

    /// Compatibility accessor for logging, tooltips and tests. UI code should
    /// switch on `networkStatus` and localize the result.
    public var currentNetworkName: String {
        switch networkStatus {
        case let .connected(ssid, _):
            return ssid
        case .notConnected:
            return "Not Connected"
        case .permissionPending:
            return LocalizationManager.shared.localizedString("permission_pending")
        case .permissionDenied:
            return "Location Permission Denied"
        case .noInterface:
            return "No Interface"
        }
    }

    public var connectedNetworkType: ConnectedNetworkType {
        if case let .connected(_, role) = networkStatus {
            return role
        }
        return .none
    }

    @Published public var launchAtLogin: Bool = false {
        didSet {
            toggleLaunchAtLoginIfNeeded()
        }
    }

    /// `launchAtLogin` is true only for `.enabled`. This status also exposes
    /// the `.requiresApproval` state so the UI can point the user at System
    /// Settings instead of silently showing the feature as off.
    @Published public private(set) var launchAtLoginStatus: LaunchAtLoginStatus = .notRegistered

    public var launchAtLoginRequiresApproval: Bool {
        launchAtLoginStatus == .requiresApproval
    }

    private let userDefaults: UserDefaults
    private let credentialStore: CredentialStore
    private var passwordSaveTasks: [String: Task<Void, Never>] = [:]
    private var launchService: LaunchServiceProtocol?
    private var isSynchronizingLaunchAtLogin = false

    public var associationCooldownUntil: Date? {
        get {
            guard let stored = userDefaults.object(forKey: DefaultsKey.associationCooldownUntil) as? Date else {
                return nil
            }
            return stored > Date() ? stored : nil
        }
        set {
            if let newValue {
                userDefaults.set(newValue, forKey: DefaultsKey.associationCooldownUntil)
            } else {
                userDefaults.removeObject(forKey: DefaultsKey.associationCooldownUntil)
            }
        }
    }

    private var associationCooldownTarget: String?

    public func hasActiveAssociationCooldown(for ssid: String) -> Bool {
        guard let target = associationCooldownTarget else {
            // Legacy persisted cooldown without a target still applies.
            return associationCooldownUntil != nil
        }
        return target == ssid && associationCooldownUntil != nil
    }

    public func beginAssociationCooldown(duration: TimeInterval, for ssid: String) {
        associationCooldownTarget = ssid
        associationCooldownUntil = Date().addingTimeInterval(max(duration, 1))
    }

    public func clearAssociationCooldown() {
        associationCooldownTarget = nil
        associationCooldownUntil = nil
    }

    /// Assign only when the value actually changes. `@Published` emits on every
    /// assignment, even for an equal value, which would otherwise invalidate
    /// the whole view tree on every periodic status refresh.
    public func setNetworkStatus(_ status: NetworkStatus) {
        guard networkStatus != status else { return }
        networkStatus = status
    }

    public init(
        userDefaults: UserDefaults = .standard,
        launchService: LaunchServiceProtocol? = nil,
        credentialStore: CredentialStore = KeychainCredentialStore.shared
    ) {
        self.userDefaults = userDefaults
        self.credentialStore = credentialStore
        self.launchService = launchService ?? LaunchAtLoginManager.shared

        self.ssidP = userDefaults.string(forKey: DefaultsKey.ssidP) ?? ""
        self.passwordP = ""
        self.ssidB = userDefaults.string(forKey: DefaultsKey.ssidB) ?? ""
        self.passwordB = ""
        self.checkInterval = AppState.normalizedCheckInterval(
            userDefaults.object(forKey: DefaultsKey.checkInterval) as? Double
        )
        self.isRunning = userDefaults.bool(forKey: DefaultsKey.isRunning)
        if self.isRunning {
            // A cooldown persisted across restarts must not block the first
            // check of a new process from recovering to the priority network.
            associationCooldownUntil = nil
            associationCooldownTarget = nil
        }

        let priorityPassword = Self.loadPassword(
            account: CredentialAccount.priority,
            legacyKey: DefaultsKey.passwordP,
            defaults: userDefaults,
            store: credentialStore
        )
        let backupPassword = Self.loadPassword(
            account: CredentialAccount.backup,
            legacyKey: DefaultsKey.passwordB,
            defaults: userDefaults,
            store: credentialStore
        )
        self.passwordP = priorityPassword.password
        self.passwordB = backupPassword.password
        self.credentialStorageWarning = priorityPassword.warning ?? backupPassword.warning

        // Sync launch state
        syncLaunchAtLogin(self.launchService?.status ?? .notRegistered)
    }

    private func toggleLaunchAtLoginIfNeeded() {
        guard !isSynchronizingLaunchAtLogin else { return }
        guard let service = launchService else { return }

        if launchAtLogin {
            guard service.status != .enabled else {
                syncLaunchAtLogin(service.status)
                return
            }

            do {
                try service.enable()
                syncLaunchAtLogin(service.status)
                if service.status == .requiresApproval {
                    log("⚠️ Launch at login requires approval in System Settings.")
                } else if service.status == .enabled {
                    log("✅ Launch at login enabled")
                }
            } catch {
                log("❌ Failed to toggle launch at login: \(error.localizedDescription)")
                syncLaunchAtLogin(service.status)
            }
        } else {
            guard service.status != .notRegistered else {
                syncLaunchAtLogin(service.status)
                return
            }

            do {
                try service.disable()
                syncLaunchAtLogin(service.status)
                log("✅ Launch at login disabled")
            } catch {
                log("❌ Failed to toggle launch at login: \(error.localizedDescription)")
                syncLaunchAtLogin(service.status)
            }
        }
    }

    public func openLaunchAtLoginSettings() {
        LaunchAtLoginManager.openSystemSettings()
    }

    /// Refresh after the user may have approved the login item in System
    /// Settings. Called when the app becomes active again.
    public func refreshLaunchAtLoginStatus() {
        syncLaunchAtLogin(launchService?.status ?? .notRegistered)
    }

    public func log(_ message: String) {
        let timestamp = Self.logTimeFormatter.string(from: Date())
        let logMessage = "[\(timestamp)] \(message)"
        print(logMessage)
        Self.logger.notice("\(message, privacy: .private(mask: .hash))")
        self.lastLog = logMessage
        self.currentStatus = message
    }

    public func diagnostic(_ message: String) {
        Self.diagnosticLogger.notice("\(message, privacy: .public)")
    }

    private func persistCheckInterval() {
        let normalized = Self.normalizedCheckInterval(checkInterval)
        if normalized != checkInterval {
            checkInterval = normalized
            return
        }

        userDefaults.set(normalized, forKey: DefaultsKey.checkInterval)
    }

    /// Keychain writes are coalesced so typing a password does not issue one
    /// keychain update per keystroke. App termination flushes pending writes.
    private func persistPassword(_ password: String, account: String) {
        passwordSaveTasks[account]?.cancel()
        let store = credentialStore
        passwordSaveTasks[account] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }

            do {
                try store.setPassword(password, for: account)
                self?.clearCredentialWarning(for: account)
            } catch {
                Self.logger.error(
                    "Keychain write failed for \(account, privacy: .public): \(String(describing: error), privacy: .private)"
                )
                self?.credentialStorageWarning = .writeFailed(account: account)
            }
            self?.passwordSaveTasks[account] = nil
        }
    }

    /// Writes any debounced password change immediately. Call before quitting.
    /// Only accounts with a pending change are written, so a keychain read
    /// failure during launch can never cause an untouched password to be
    /// deleted on exit.
    public func flushPendingPasswordSaves() {
        let pendingAccounts = Array(passwordSaveTasks.keys)
        for task in passwordSaveTasks.values {
            task.cancel()
        }
        passwordSaveTasks.removeAll()

        for account in pendingAccounts {
            switch account {
            case CredentialAccount.priority:
                writePasswordImmediately(passwordP, account: account)
            case CredentialAccount.backup:
                writePasswordImmediately(passwordB, account: account)
            default:
                break
            }
        }
    }

    private func writePasswordImmediately(_ password: String, account: String) {
        do {
            try credentialStore.setPassword(password, for: account)
            clearCredentialWarning(for: account)
        } catch {
            Self.logger.error(
                "Keychain flush failed for \(account, privacy: .public): \(String(describing: error), privacy: .private)"
            )
            credentialStorageWarning = .writeFailed(account: account)
        }
    }

    /// Reads the keychain entry, falling back to the pre-Keychain plaintext
    /// `UserDefaults` value once and migrating it only after the
    /// keychain write can be read back. On failure the legacy value is kept so
    /// a transient keychain error cannot destroy the user's only copy.
    private static func loadPassword(
        account: String,
        legacyKey: String,
        defaults: UserDefaults,
        store: CredentialStore
    ) -> (password: String, warning: CredentialStorageWarning?) {
        let storedPassword: String?
        do {
            storedPassword = try store.password(for: account)
        } catch {
            logger.error(
                "Keychain read failed for \(account, privacy: .public): \(String(describing: error), privacy: .private)"
            )
            let legacy = defaults.string(forKey: legacyKey) ?? ""
            return (legacy, .readFailed(account: account))
        }

        if let storedPassword, !storedPassword.isEmpty {
            if defaults.object(forKey: legacyKey) != nil {
                defaults.removeObject(forKey: legacyKey)
            }
            return (storedPassword, nil)
        }

        guard let legacy = defaults.string(forKey: legacyKey), !legacy.isEmpty else {
            defaults.removeObject(forKey: legacyKey)
            return ("", nil)
        }

        do {
            try store.setPassword(legacy, for: account)
            guard try store.password(for: account) == legacy else {
                throw CredentialStoreError.verificationFailed
            }
            defaults.removeObject(forKey: legacyKey)
            return (legacy, nil)
        } catch {
            logger.error(
                "Keychain migration failed for \(account, privacy: .public): \(String(describing: error), privacy: .private)"
            )
            return (legacy, .migrationFailed(account: account))
        }
    }

    private func clearCredentialWarning(for account: String) {
        guard credentialStorageWarning?.account == account else { return }
        credentialStorageWarning = nil
    }

    private func syncLaunchAtLogin(_ status: LaunchAtLoginStatus) {
        guard launchAtLoginStatus != status || launchAtLogin != status.isEnabled else {
            return
        }

        isSynchronizingLaunchAtLogin = true
        launchAtLoginStatus = status
        launchAtLogin = status.isEnabled
        isSynchronizingLaunchAtLogin = false
    }

    private static func normalizedCheckInterval(_ value: Double?) -> Double {
        let candidate = value ?? defaultCheckInterval
        guard candidate.isFinite else {
            return defaultCheckInterval
        }

        return min(max(candidate, minimumCheckInterval), maximumCheckInterval)
    }
}
