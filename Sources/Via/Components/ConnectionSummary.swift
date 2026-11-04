import SwiftUI
import ViaCore

struct ConnectionSummary: View {
    @ObservedObject var appState: AppState
    @ObservedObject var i18n = LocalizationManager.shared

    var badgeText: String? = nil
    var badgeColor: Color = .secondary

    private var isConnected: Bool {
        if case .connected = appState.networkStatus {
            return true
        }
        return false
    }

    private var networkName: String {
        switch appState.networkStatus {
        case let .connected(ssid, _):
            return ssid
        case .notConnected:
            return i18n.localizedString("not_connected")
        case .permissionPending:
            return i18n.localizedString("permission_pending")
        case .permissionDenied:
            return i18n.localizedString("location_permission_denied")
        case .noInterface:
            return i18n.localizedString("wifi_unavailable")
        }
    }

    private var roleText: String {
        switch appState.connectedNetworkType {
        case .priority:
            return i18n.localizedString("role_priority")
        case .backup:
            return i18n.localizedString("role_backup")
        case .other:
            return i18n.localizedString("role_other")
        case .none:
            return i18n.localizedString("role_offline")
        }
    }

    private var iconName: String {
        isConnected ? "wifi" : "wifi.slash"
    }

    private var iconTint: Color {
        switch appState.networkStatus {
        case .connected:
            return .accentColor
        case .permissionDenied:
            return .orange
        case .permissionPending, .noInterface, .notConnected:
            return .secondary
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(iconTint.opacity(0.12))
                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(iconTint)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(networkName)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                Text(roleText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if let badgeText {
                StatusBadge(text: badgeText, color: badgeColor)
            }
        }
    }
}
