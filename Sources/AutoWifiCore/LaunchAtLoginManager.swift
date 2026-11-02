import Foundation
import ServiceManagement

public enum LaunchAtLoginStatus: Equatable, Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound

    public var isEnabled: Bool {
        self == .enabled
    }
}

@MainActor
public protocol LaunchServiceProtocol {
    var status: LaunchAtLoginStatus { get }
    func enable() throws
    func disable() throws
}

public extension LaunchServiceProtocol {
    var isEnabled: Bool {
        status == .enabled
    }
}

@MainActor
public class LaunchAtLoginManager: LaunchServiceProtocol {
    public static let shared = LaunchAtLoginManager()

    private let service = SMAppService.mainApp

    public var status: LaunchAtLoginStatus {
        switch service.status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .notFound
        case .notRegistered:
            return .notRegistered
        @unknown default:
            return .notRegistered
        }
    }

    public func enable() throws {
        do {
            try service.register()
        } catch {
            print("Failed to enable launch at login: \(error)")
            throw error
        }
    }

    public func disable() throws {
        do {
            try service.unregister()
        } catch {
            print("Failed to disable launch at login: \(error)")
            throw error
        }
    }

    public static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
