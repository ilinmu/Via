import SwiftUI
import ViaCore

struct NetworksStepView: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var i18n = LocalizationManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(i18n.localizedString("onboarding_networks_title"))
                .font(PanelFont.title)

            Text(i18n.localizedString("onboarding_networks_body"))
                .font(PanelFont.body)
                .foregroundStyle(PanelColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            NetworkSetupForm(
                draft: $model.draft,
                availableNetworks: model.availableNetworks,
                isScanning: model.isScanning,
                scanOutcome: model.scanOutcome,
                canScan: model.canScan,
                onScan: { model.scan() },
                currentSSID: model.currentSSID
            )

            Text(i18n.localizedString("onboarding_networks_hint"))
                .font(PanelFont.caption)
                .foregroundStyle(PanelColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
