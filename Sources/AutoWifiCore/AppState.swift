import Foundation
import Combine

@MainActor
public class AppState: ObservableObject {
    @Published public var ssidA: String {
        didSet { userDefaults.set(ssidA, forKey: "ssidA") }
    }
    @Published public var passwordA: String {
        didSet { userDefaults.set(passwordA, forKey: "passwordA") }
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

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.ssidA = userDefaults.string(forKey: "ssidA") ?? ""
        self.passwordA = userDefaults.string(forKey: "passwordA") ?? ""
        self.ssidB = userDefaults.string(forKey: "ssidB") ?? ""
        self.passwordB = userDefaults.string(forKey: "passwordB") ?? ""
        self.checkInterval = userDefaults.double(forKey: "checkInterval")
        if self.checkInterval == 0 { self.checkInterval = 60 }
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
