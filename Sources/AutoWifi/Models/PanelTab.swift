import Foundation

enum PanelRoute: Equatable {
    case onboarding
    case tabs
}

enum PanelTab: String, CaseIterable, Identifiable {
    case status
    case networks
    case settings

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .status:
            return "tab_status"
        case .networks:
            return "tab_networks"
        case .settings:
            return "tab_settings"
        }
    }
}

enum SetupStep: Int, CaseIterable, Identifiable {
    case permission
    case networks
    case finish

    var id: Int { rawValue }
}

enum ScanOutcome: Equatable {
    case idle
    case scanning
    case success(Int)
    case empty
    case permissionPending
    case permissionDenied
}
