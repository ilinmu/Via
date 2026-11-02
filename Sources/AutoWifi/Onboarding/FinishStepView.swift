import SwiftUI
import AutoWifiCore

struct FinishStepView: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var i18n = LocalizationManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(i18n.localizedString("onboarding_finish_title"))
                .font(.title3.weight(.semibold))

            Text(i18n.localizedString("onboarding_finish_body"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                PanelSummaryRow(
                    title: i18n.localizedString("priority_network"),
                    value: model.draft.trimmedSSIDP
                )

                Divider()
                    .padding(.vertical, 2)

                PanelSummaryRow(
                    title: i18n.localizedString("backup_network"),
                    value: model.draft.trimmedSSIDB
                )

                Divider()
                    .padding(.vertical, 2)

                PanelSummaryRow(
                    title: i18n.localizedString("permission_label"),
                    value: permissionText
                )
            }

            if !model.permissionReady {
                WarningBanner(
                    message: i18n.localizedString("permission_required_for_automation"),
                    actionTitle: i18n.localizedString("permission_open_settings")
                ) {
                    SystemLinks.openLocationSettings()
                }
            }

            Text(i18n.localizedString("onboarding_privacy_note"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var permissionText: String {
        switch model.wifiManager.locationAuthorizationStatus {
        case .authorizedAlways:
            return i18n.localizedString("permission_granted")
        case .notDetermined:
            return i18n.localizedString("permission_pending")
        default:
            return i18n.localizedString("location_permission_denied")
        }
    }
}
