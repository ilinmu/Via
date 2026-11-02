import CoreLocation
import SwiftUI
import AutoWifiCore

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

            Divider()

            autoSwitchRow

            if appState.isRunning {
                nextCheckRow
            } else if !model.canAutomate {
                setupHintRow
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

            HStack(spacing: 8) {
                ScanButton(
                    isScanning: model.isScanning,
                    isEnabled: model.canScan,
                    action: { model.scan() }
                )

                Button(i18n.localizedString("refresh_status")) {
                    model.refreshAll()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            if let scanFeedback {
                Text(scanFeedback)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, PanelLayout.horizontalPadding)
        .padding(.vertical, 16)
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
            return .accentColor
        }
        if appState.isRunning {
            return model.permissionReady ? .green : .orange
        }
        return .secondary
    }

    private var autoSwitchRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(i18n.localizedString("auto_switch"))
                    .font(.body)
                Text(i18n.localizedString("auto_switch_description"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if model.isStarting {
                ProgressView()
                    .controlSize(.small)
            }

            Toggle(
                "",
                isOn: Binding(
                    get: { appState.isRunning },
                    set: { newValue in
                        if newValue {
                            model.startMonitoring()
                        } else {
                            model.stopMonitoring()
                        }
                    }
                )
            )
            .labelsHidden()
            .disabled(model.isStarting || (!appState.isRunning && !model.canAutomate))
            .accessibilityLabel(i18n.localizedString("auto_switch"))
        }
    }

    @ViewBuilder
    private var nextCheckRow: some View {
        if model.isStarting {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(i18n.localizedString("status_checking"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        } else if let nextCheck = wifiManager.nextCheckTime {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = max(0, nextCheck.timeIntervalSince(context.date))
                HStack(spacing: 8) {
                    Label(i18n.localizedString("next_check"), systemImage: "timer")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(
                        String(
                            format: i18n.localizedString("seconds_short"),
                            remaining
                        )
                    )
                    .font(.subheadline.monospacedDigit())
                }
            }
        } else {
            HStack(spacing: 8) {
                Image(systemName: "timer")
                    .foregroundStyle(.secondary)
                Text(
                    i18n.localizedString(
                        model.permissionReady ? "status_checking" : "status_waiting_permission"
                    )
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private var setupHintRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text(
                i18n.localizedString(
                    model.isConfigurationComplete
                        ? "permission_required_for_automation"
                        : "configure_networks_hint"
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button(
                i18n.localizedString(
                    model.isConfigurationComplete
                        ? permissionActionTitle
                        : "go_to_networks"
                )
            ) {
                if model.isConfigurationComplete {
                    handlePermissionAction()
                } else {
                    model.tab = .networks
                }
            }
            .buttonStyle(.link)
            .font(.caption)
        }
    }

    private var unsavedDraftRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "square.and.pencil")
                .foregroundStyle(.orange)
            Text(i18n.localizedString("unsaved_changes"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(i18n.localizedString("go_to_networks")) {
                model.tab = .networks
            }
            .buttonStyle(.link)
            .font(.caption)
        }
    }

    private var permissionActionTitle: String {
        wifiManager.locationAuthorizationStatus == .notDetermined
            ? i18n.localizedString("permission_grant")
            : i18n.localizedString("permission_open_settings")
    }

    private func handlePermissionAction() {
        if wifiManager.locationAuthorizationStatus == .notDetermined {
            wifiManager.requestPermissions()
        } else {
            SystemLinks.openLocationSettings()
        }
    }

    private var scanFeedback: String? {
        switch model.scanOutcome {
        case let .success(count):
            return String(
                format: i18n.localizedString("networks_found_count"),
                count
            )
        case .empty:
            return i18n.localizedString("no_networks_found")
        case .idle, .scanning, .permissionPending, .permissionDenied:
            return nil
        }
    }

    private func displaySSID(_ ssid: String) -> String {
        let trimmed = ssid.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? i18n.localizedString("not_set") : trimmed
    }
}
