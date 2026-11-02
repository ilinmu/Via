import Foundation
import AutoWifiCore

@MainActor
struct NetworkDraft {
    private struct Snapshot: Equatable {
        let ssidP: String
        let passwordP: String
        let ssidB: String
        let passwordB: String
    }

    enum Validation: Equatable {
        case valid
        case missingPrimary
        case missingBackup
        case sameNetwork

        var errorKey: String? {
            switch self {
            case .valid:
                return nil
            case .missingPrimary:
                return "missing_primary"
            case .missingBackup:
                return "missing_backup"
            case .sameNetwork:
                return "same_network_error"
            }
        }
    }

    var ssidP: String
    var passwordP: String
    var ssidB: String
    var passwordB: String

    private var original: Snapshot

    init(appState: AppState) {
        ssidP = appState.ssidP
        passwordP = appState.passwordP
        ssidB = appState.ssidB
        passwordB = appState.passwordB
        original = Snapshot(
            ssidP: appState.ssidP,
            passwordP: appState.passwordP,
            ssidB: appState.ssidB,
            passwordB: appState.passwordB
        )
    }

    var trimmedSSIDP: String {
        ssidP.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedSSIDB: String {
        ssidB.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasAnySSID: Bool {
        !trimmedSSIDP.isEmpty || !trimmedSSIDB.isEmpty
    }

    var validation: Validation {
        guard !trimmedSSIDP.isEmpty else { return .missingPrimary }
        guard !trimmedSSIDB.isEmpty else { return .missingBackup }
        guard trimmedSSIDP.caseInsensitiveCompare(trimmedSSIDB) != .orderedSame else {
            return .sameNetwork
        }
        return .valid
    }

    var isValid: Bool {
        validation == .valid
    }

    var hasChanges: Bool {
        Snapshot(
            ssidP: ssidP,
            passwordP: passwordP,
            ssidB: ssidB,
            passwordB: passwordB
        ) != original
    }

    mutating func commit(to appState: AppState) {
        let primary = trimmedSSIDP
        let backup = trimmedSSIDB
        ssidP = primary
        ssidB = backup

        if appState.ssidP != primary {
            appState.ssidP = primary
        }
        if appState.passwordP != passwordP {
            appState.passwordP = passwordP
        }
        if appState.ssidB != backup {
            appState.ssidB = backup
        }
        if appState.passwordB != passwordB {
            appState.passwordB = passwordB
        }

        original = Snapshot(
            ssidP: primary,
            passwordP: passwordP,
            ssidB: backup,
            passwordB: passwordB
        )
    }

    mutating func reload(from appState: AppState) {
        ssidP = appState.ssidP
        passwordP = appState.passwordP
        ssidB = appState.ssidB
        passwordB = appState.passwordB
        original = Snapshot(
            ssidP: appState.ssidP,
            passwordP: appState.passwordP,
            ssidB: appState.ssidB,
            passwordB: appState.passwordB
        )
    }
}
