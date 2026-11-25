import CoreLocation
import SwiftUI
import ViaCore

struct StatusTabView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var wifiManager: WifiManager
    @ObservedObject var model: PanelModel
    @ObservedObject var i18n = LocalizationManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ConnectionSummary(
                appState: appState,
                badgeText: statusBadgeText,
                badgeColor: statusBadgeColor
            )

            if appState.isRunning, let explanation = statusExplanation {
                Text(explanation)
                    .font(PanelFont.caption)
                    .foregroundStyle(PanelColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            autoSwitchRow

            if appState.isRunning {
                nextCheckRow
            } else if !model.isConfigurationComplete {
                setupHintRow
            }

            if !appState.isRunning, model.canAutomate, wifiManager.autoSwitchStopReason == .manualOverride {
                manualStopRow
            }

            if model.hasUnsavedDraft {
                unsavedDraftRow
            }

            Divider()

            VStack(spacing: 0) {
                PanelSummaryRow(
                    title: i18n.localizedString("priority_network"),
                    value: displaySSID(appState.ssidP),
                    showsChevron: true
                ) {
                    model.tab = .networks
                }

                Divider()

                PanelSummaryRow(
                    title: i18n.localizedString("backup_network"),
                    value: displaySSID(appState.ssidB),
                    showsChevron: true
                ) {
                    model.tab = .networks
                }
            }

            HStack {
                Button(i18n.localizedString("refresh_status")) {
                    model.refreshAll()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, PanelLayout.horizontalPadding)
        .padding(.vertical, 16)
    }

    private var autoSwitchBinding: Binding<Bool> {
        Binding(
            get: { appState.isRunning },
            set: { wanted in
                if wanted {
                    model.startMonitoring()
                } else {
                    model.stopMonitoring()
                }
            }
        )
    }

    private var statusBadgeText: String {
        if model.isStarting {
            return i18n.localizedString("starting")
        }
        if appState.isRunning {
            return i18n.localizedString(
                model.permissionReady ? "status_active" : "status_waiting_permission"
            )
        }
        return i18n.localizedString("status_paused")
    }

    private var statusBadgeColor: Color {
        if model.isStarting {
            return PanelColor.accent
        }
        if appState.isRunning {
            return model.permissionReady ? PanelColor.accent : PanelColor.warning
        }
        return PanelColor.textSecondary
    }

    /// Only added when it tells the user something the network name and role
    /// do not already say.
    private var statusExplanation: String? {
        switch appState.connectedNetworkType {
        case .backup:
            return i18n.localizedString("status_explanation_backup")
        case .other:
            return i18n.localizedString("status_explanation_other")
        case .none:
            return i18n.localizedString("status_explanation_offline")
        case .priority:
            return nil
        }
    }

    private var autoSwitchRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(i18n.localizedString("auto_switch"))
                    .font(PanelFont.body)
                    .foregroundStyle(.primary)
                Text(i18n.localizedString("auto_switch_description"))
                    .font(PanelFont.caption)
                    .foregroundStyle(PanelColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if model.isStarting {
                ProgressView()
                    .controlSize(.small)
            } else {
                Toggle("", isOn: autoSwitchBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!appState.isRunning && !model.canAutomate)
                    .accessibilityLabel(i18n.localizedString("auto_switch"))
            }
        }
    }

    @ViewBuilder
    private var nextCheckRow: some View {
        HStack(spacing: 8) {
            Text(i18n.localizedString("next_check"))
                .font(PanelFont.caption)
                .foregroundStyle(PanelColor.textSecondary)

            Spacer(minLength: 8)

            if model.isStarting {
                Text(i18n.localizedString("status_checking"))
                    .font(PanelFont.caption)
                    .foregroundStyle(PanelColor.textSecondary)
            } else if let nextCheck = wifiManager.nextCheckTime {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(0, nextCheck.timeIntervalSince(context.date))
                    Text(i18n.duration(remaining))
                        .font(PanelFont.caption.monospacedDigit())
                        .foregroundStyle(PanelColor.textSecondary)
                }
            } else {
                Text(
                    i18n.localizedString(
                        model.permissionReady ? "status_checking" : "status_waiting_permission"
                    )
                )
                .font(PanelFont.caption)
                .foregroundStyle(PanelColor.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var setupHintRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(PanelColor.textSecondary)
            Text(i18n.localizedString("start_unavailable_networks"))
                .font(PanelFont.caption)
                .foregroundStyle(PanelColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button(i18n.localizedString("go_to_networks")) {
                model.tab = .networks
            }
            .buttonStyle(.link)
            .font(PanelFont.caption)
        }
    }

    private var manualStopRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "hand.raised")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(PanelColor.warning)
            Text(i18n.localizedString("status_manual_stopped"))
                .font(PanelFont.caption)
                .foregroundStyle(PanelColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(i18n.localizedString("resume_auto_switch")) {
                model.startMonitoring()
            }
            .buttonStyle(.link)
            .font(PanelFont.caption)
        }
    }

    private var unsavedDraftRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(PanelColor.warning)
            Text(i18n.localizedString("unsaved_changes"))
                .font(PanelFont.caption)
                .foregroundStyle(PanelColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(i18n.localizedString("go_to_networks")) {
                model.tab = .networks
            }
            .buttonStyle(.link)
            .font(PanelFont.caption)
        }
    }

    private func displaySSID(_ ssid: String) -> String {
        let trimmed = ssid.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? i18n.localizedString("not_set") : trimmed
    }
}
