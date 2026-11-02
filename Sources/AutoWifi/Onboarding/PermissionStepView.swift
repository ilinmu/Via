import CoreLocation
import SwiftUI
import AutoWifiCore

struct PermissionStepView: View {
    @ObservedObject var wifiManager: WifiManager
    @ObservedObject var i18n = LocalizationManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "location.circle")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(.tint)

            Text(i18n.localizedString("onboarding_permission_title"))
                .font(.title3.weight(.semibold))

            Text(i18n.localizedString("onboarding_permission_body"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            permissionControl

            Text(i18n.localizedString("onboarding_permission_later_hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(i18n.localizedString("onboarding_privacy_note"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
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
            .font(.callout)
            .foregroundStyle(.green)

        case .notDetermined:
            HStack(spacing: 10) {
                Button(i18n.localizedString("permission_grant")) {
                    wifiManager.requestPermissions()
                }
                .buttonStyle(.borderedProminent)

                Button(i18n.localizedString("permission_open_settings")) {
                    SystemLinks.openLocationSettings()
                }
                .buttonStyle(.link)
                .font(.callout)
            }

        default:
            HStack(alignment: .center, spacing: 10) {
                Button(i18n.localizedString("permission_open_settings")) {
                    SystemLinks.openLocationSettings()
                }
                .buttonStyle(.borderedProminent)

                Text(i18n.localizedString("permission_always_required"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
