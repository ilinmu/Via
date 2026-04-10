import Foundation
import ServiceManagement

@MainActor
public protocol LaunchServiceProtocol {
    var isEnabled: Bool { get }
    func enable() throws
    func disable() throws
}

@available(macOS 13.0, *)
@MainActor
public class LaunchAtLoginManager: LaunchServiceProtocol {
    public static let shared = LaunchAtLoginManager()
    
    private let service = SMAppService.mainApp
    
    public var isEnabled: Bool {
        return service.status == .enabled
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
}

// Mock for testing or older macOS versions (though we target 13+)
public class MockLaunchService: LaunchServiceProtocol {
    public var isEnabled: Bool = false
    public var shouldFail: Bool = false
    
    public init() {}
    
    public func enable() throws {
        if shouldFail {
            throw NSError(domain: "MockLaunchService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Mock failure"])
        }
        isEnabled = true
    }
    
    public func disable() throws {
        if shouldFail {
            throw NSError(domain: "MockLaunchService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Mock failure"])
        }
        isEnabled = false
    }
}
