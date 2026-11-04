import SwiftUI
import ViaCore

struct NetworksTabView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var model: PanelModel
    @ObservedObject var i18n = LocalizationManager.shared

    @State private var showValidation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(i18n.localizedString("networks_title"))
                    .font(.title3.weight(.semibold))
                Text(i18n.localizedString("networks_description"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            NetworkSetupForm(
                draft: $model.draft,
                availableNetworks: model.availableNetworks,
                isScanning: model.isScanning,
                scanOutcome: model.scanOutcome,
                canScan: model.canScan,
                onScan: { model.scan() },
                showValidation: showValidation
            )

            if appState.credentialStorageWarning != nil {
                WarningBanner(
                    message: i18n.localizedString("credential_storage_warning")
                )
            }

            HStack(alignment: .center, spacing: 8) {
                Text(
                    i18n.localizedString(
                        model.draft.hasChanges ? "unsaved_changes" : "saved"
                    )
                )
                .font(.caption)
                .foregroundStyle(model.draft.hasChanges ? .orange : .secondary)

                Spacer(minLength: 8)

                Button(i18n.localizedString("save_changes")) {
                    if model.commitDraft() {
                        showValidation = false
                    } else {
                        showValidation = true
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!model.draft.hasChanges)
            }

            Text(i18n.localizedString("networks_auto_save"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, PanelLayout.horizontalPadding)
        .padding(.vertical, 16)
    }
}
