import Foundation
import Combine

@MainActor
public class AppState: ObservableObject {
    public static let defaultCheckInterval: Double = 60
    public static let minimumCheckInterval: Double = 5

    private enum DefaultsKey {
        static let ssidP = "ssidP"
        static let ssidB = "ssidB"
        static let checkInterval = "checkInterval"
        static let passwordP = "passwordP"
        static let passwordB = "passwordB"
    }

    @Published public var ssidP: String {
        didSet { userDefaults.set(ssidP, forKey: DefaultsKey.ssidP) }
    }
    @Published public var passwordP: String {
        didSet { persistPassword(passwordP, key: DefaultsKey.passwordP) }
    }
    @Published public var ssidB: String {
        didSet { userDefaults.set(ssidB, forKey: DefaultsKey.ssidB) }
    }
    @Published public var passwordB: String {
        didSet { persistPassword(passwordB, key: DefaultsKey.passwordB) }
    }
    @Published public var checkInterval: Double {
        didSet { persistCheckInterval() }
    }
    @Published public var isRunning: Bool = false
    @Published public var currentStatus: String = "Ready"
    @Published public var lastLog: String = ""
    @Published public var currentNetworkName: String = "Not Connected"
    public enum ConnectedNetworkType: Equatable {
        case none
        case priority
        case backup
        case other
    }
    
    @Published public var connectedNetworkType: ConnectedNetworkType = .none
    
    @Published public var launchAtLogin: Bool = false {
        didSet {
            toggleLaunchAtLoginIfNeeded()
        }
    }

    private let userDefaults: UserDefaults
    private let secureStore: SecureStoreProtocol
    private var launchService: LaunchServiceProtocol?
    private var isSynchronizingLaunchAtLogin = false

    public init(
        userDefaults: UserDefaults = .standard,
        launchService: LaunchServiceProtocol? = nil,
        secureStore: SecureStoreProtocol = KeychainStore.shared
    ) {
        self.userDefaults = userDefaults
        self.secureStore = secureStore
        
        if #available(macOS 13.0, *) {
            self.launchService = launchService ?? LaunchAtLoginManager.shared
        } else {
            self.launchService = launchService ?? MockLaunchService() // Fallback for older OS (though target is 13)
        }
        
        self.ssidP = userDefaults.string(forKey: DefaultsKey.ssidP) ?? ""
        self.passwordP = AppState.loadPassword(
            from: secureStore,
            userDefaults: userDefaults,
            key: DefaultsKey.passwordP
        )
        self.ssidB = userDefaults.string(forKey: DefaultsKey.ssidB) ?? ""
        self.passwordB = AppState.loadPassword(
            from: secureStore,
            userDefaults: userDefaults,
            key: DefaultsKey.passwordB
        )
        self.checkInterval = AppState.normalizedCheckInterval(
            userDefaults.object(forKey: DefaultsKey.checkInterval) as? Double
        )
        
        // Sync launch state
        syncLaunchAtLogin(self.launchService?.isEnabled ?? false)
    }
    
    private func toggleLaunchAtLoginIfNeeded() {
        guard !isSynchronizingLaunchAtLogin else { return }
        guard let service = launchService else { return }
        
        if service.isEnabled == launchAtLogin { return }
        
        do {
            if launchAtLogin {
                try service.enable()
                log("✅ Launch at login enabled")
            } else {
                try service.disable()
                log("✅ Launch at login disabled")
            }
        } catch {
            log("❌ Failed to toggle launch at login: \(error.localizedDescription)")
            syncLaunchAtLogin(service.isEnabled)
        }
    }
    
    public func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        let timestamp = formatter.string(from: Date())
        let logMessage = "[\(timestamp)] \(message)"
        print(logMessage)
        self.lastLog = logMessage
        self.currentStatus = message
    }

    private func persistCheckInterval() {
        let normalized = Self.normalizedCheckInterval(checkInterval)
        if normalized != checkInterval {
            checkInterval = normalized
            return
        }

        userDefaults.set(normalized, forKey: DefaultsKey.checkInterval)
    }

    private func persistPassword(_ password: String, key: String) {
        do {
            if password.isEmpty {
                try secureStore.removeValue(forKey: key)
            } else {
                try secureStore.setString(password, forKey: key)
            }
            userDefaults.removeObject(forKey: key)
        } catch {
            log("❌ Failed to save credentials securely: \(error.localizedDescription)")
        }
    }

    private func syncLaunchAtLogin(_ enabled: Bool) {
        isSynchronizingLaunchAtLogin = true
        launchAtLogin = enabled
        isSynchronizingLaunchAtLogin = false
    }

    private static func loadPassword(
        from secureStore: SecureStoreProtocol,
        userDefaults: UserDefaults,
        key: String
    ) -> String {
        if let password = (try? secureStore.string(forKey: key)) ?? nil {
            return password
        }

        let legacyPassword = userDefaults.string(forKey: key) ?? ""
        guard !legacyPassword.isEmpty else {
            return ""
        }

        do {
            try secureStore.setString(legacyPassword, forKey: key)
            userDefaults.removeObject(forKey: key)
        } catch {
            print("Failed to migrate password for \(key): \(error.localizedDescription)")
        }

        return legacyPassword
    }

    private static func normalizedCheckInterval(_ value: Double?) -> Double {
        let candidate = value ?? defaultCheckInterval
        guard candidate.isFinite else {
            return defaultCheckInterval
        }

        return max(candidate, minimumCheckInterval)
    }
}
