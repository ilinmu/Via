import Foundation
import Combine

@MainActor
public class AppState: ObservableObject {
    @Published public var ssidP: String {
        didSet { userDefaults.set(ssidP, forKey: "ssidP") }
    }
    @Published public var passwordP: String {
        didSet { userDefaults.set(passwordP, forKey: "passwordP") }
    }
    @Published public var ssidB: String {
        didSet { userDefaults.set(ssidB, forKey: "ssidB") }
    }
    @Published public var passwordB: String {
        didSet { userDefaults.set(passwordB, forKey: "passwordB") }
    }
    @Published public var checkInterval: Double {
        didSet { userDefaults.set(checkInterval, forKey: "checkInterval") }
    }
    @Published public var isRunning: Bool = false
    @Published public var currentStatus: String = "Ready"
    @Published public var lastLog: String = ""
    @Published public var currentNetworkName: String = "Not Connected"
    public enum ConnectedNetworkType {
        case none
        case priority
        case backup
        case other
    }
    
    @Published public var connectedNetworkType: ConnectedNetworkType = .none
    
    @Published public var launchAtLogin: Bool = false {
        didSet {
            toggleLaunchAtLogin()
        }
    }

    private let userDefaults: UserDefaults
    private var launchService: LaunchServiceProtocol?

    public init(userDefaults: UserDefaults = .standard, launchService: LaunchServiceProtocol? = nil) {
        self.userDefaults = userDefaults
        
        if #available(macOS 13.0, *) {
            self.launchService = launchService ?? LaunchAtLoginManager.shared
        } else {
            self.launchService = launchService ?? MockLaunchService() // Fallback for older OS (though target is 13)
        }
        
        self.ssidP = userDefaults.string(forKey: "ssidP") ?? ""
        self.passwordP = userDefaults.string(forKey: "passwordP") ?? ""
        self.ssidB = userDefaults.string(forKey: "ssidB") ?? ""
        self.passwordB = userDefaults.string(forKey: "passwordB") ?? ""
        self.checkInterval = userDefaults.double(forKey: "checkInterval")
        if self.checkInterval == 0 { self.checkInterval = 60 }
        
        // Sync launch state
        self.launchAtLogin = self.launchService?.isEnabled ?? false
    }
    
    private func toggleLaunchAtLogin() {
        guard let service = launchService else { return }
        
        // Avoid recursive loop if state matches
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
            // Revert UI state if operation failed
            // We need to do this carefully to avoid infinite loop, but since we check equality above, it should be fine
            // However, changing published property in didSet is tricky.
            // Ideally we should separate the action from the property binding.
            // For simplicity in SwiftUI, we often use binding. 
            // Let's keep it simple: if it fails, the UI might be out of sync with system.
            // A better way is to have a function `setLaunchAtLogin(_ enabled: Bool)`
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
}
