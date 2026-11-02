import SwiftUI
import AutoWifiCore

struct NetworksStepView: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var i18n = LocalizationManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(i18n.localizedString("onboarding_networks_title"))
                .font(.title3.weight(.semibold))

            Text(i18n.localizedString("onboarding_networks_body"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            NetworkSetupForm(
                draft: $model.draft,
                availableNetworks: model.availableNetworks,
                isScanning: model.isScanning,
                scanOutcome: model.scanOutcome,
                canScan: model.canScan,
                onScan: { model.scan() }
            )

            Text(i18n.localizedString("onboarding_networks_hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
