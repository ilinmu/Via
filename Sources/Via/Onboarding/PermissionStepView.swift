import CoreLocation
import SwiftUI
import ViaCore

struct PermissionStepView: View {
    @ObservedObject var wifiManager: WifiManager
    @ObservedObject var i18n = LocalizationManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "location.circle")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(PanelColor.accentText)

            Text(i18n.localizedString("onboarding_permission_title"))
                .font(PanelFont.title)

            Text(i18n.localizedString("onboarding_permission_body"))
                .font(PanelFont.body)
                .foregroundStyle(PanelColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            permissionControl

            Text(i18n.localizedString("onboarding_permission_later_hint"))
                .font(PanelFont.caption)
                .foregroundStyle(PanelColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(i18n.localizedString("onboarding_privacy_note"))
                .font(PanelFont.caption)
                .foregroundStyle(PanelColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var permissionControl: some View {
        switch wifiManager.locationAuthorizationStatus {
        case .authorizedAlways:
            Label(
                i18n.localizedString("onboarding_permission_granted"),
                systemImage: "checkmark.circle.fill"
            )
            .font(PanelFont.body)
            .foregroundStyle(PanelColor.accentText)

        case .notDetermined:
            VStack(alignment: .leading, spacing: 8) {
                Button(i18n.localizedString("permission_grant")) {
                    wifiManager.requestPermissions()
                }
                .buttonStyle(.borderedProminent)

                HStack(spacing: 6) {
                    Text(i18n.localizedString("onboarding_permission_settings_hint"))
                        .font(PanelFont.caption)
                        .foregroundStyle(PanelColor.textSecondary)
                    Button(i18n.localizedString("permission_open_settings")) {
                        SystemLinks.openLocationSettings()
                    }
                    .buttonStyle(.link)
                    .font(PanelFont.caption)
                }
            }

        default:
            VStack(alignment: .leading, spacing: 8) {
                Button(i18n.localizedString("permission_open_settings")) {
                    SystemLinks.openLocationSettings()
                }
                .buttonStyle(.borderedProminent)

                Text(i18n.localizedString("permission_always_required"))
                    .font(PanelFont.caption)
                    .foregroundStyle(PanelColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
