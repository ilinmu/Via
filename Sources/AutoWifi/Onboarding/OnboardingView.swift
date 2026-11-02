import SwiftUI
import AutoWifiCore

struct OnboardingView: View {
    @ObservedObject var wifiManager: WifiManager
    @ObservedObject var model: PanelModel
    @ObservedObject var i18n = LocalizationManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            progress

            stepContent
                .id(model.step)

            Divider()

            footer
        }
        .padding(.horizontal, PanelLayout.horizontalPadding)
        .padding(.vertical, 16)
    }

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(SetupStep.allCases) { step in
                Capsule()
                    .fill(
                        step.rawValue <= model.step.rawValue
                            ? Color.accentColor
                            : Color(nsColor: .separatorColor)
                    )
                    .frame(height: 3)
            }
        }
        .accessibilityLabel(
            String(
                format: i18n.localizedString("onboarding_step_format"),
                model.step.rawValue + 1,
                SetupStep.allCases.count
            )
        )
    }

    @ViewBuilder
    private var stepContent: some View {
        switch model.step {
        case .permission:
            PermissionStepView(wifiManager: wifiManager)
        case .networks:
            NetworksStepView(model: model)
        case .finish:
            FinishStepView(model: model)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if model.step != .permission {
                Button(i18n.localizedString("onboarding_back")) {
                    model.goBack()
                }
                .buttonStyle(.bordered)
                .disabled(model.isStarting)
            }

            Spacer(minLength: 8)

            if model.step == .finish {
                Button(i18n.localizedString("onboarding_save_only")) {
                    model.finishOnboarding(enableMonitoring: false)
                }
                .buttonStyle(.bordered)
                .disabled(!model.draft.isValid || model.isStarting)

                Button {
                    model.finishOnboarding(enableMonitoring: true)
                } label: {
                    if model.isStarting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(i18n.localizedString("onboarding_start"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.draft.isValid || !model.permissionReady || model.isStarting)
            } else {
                Button(i18n.localizedString("onboarding_next")) {
                    model.advanceStep()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.step == .networks && !model.draft.isValid)
            }
        }
    }
}
