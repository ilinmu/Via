import AppKit
import SwiftUI
import ViaCore

struct SettingsTabView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var model: PanelModel
    @ObservedObject var i18n = LocalizationManager.shared

    @State private var showHelp = false
    @FocusState private var intervalFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            generalSection

            Divider()

            automaticSection

            Divider()

            aboutSection
        }
        .padding(.horizontal, PanelLayout.horizontalPadding)
        .padding(.vertical, 16)
        .onChange(of: appState.checkInterval) { _ in
            if !intervalFocused {
                model.syncIntervalDraft()
            }
        }
        .onChange(of: model.intervalDraft) { newValue in
            let digits = String(newValue.filter(\.isNumber).prefix(4))
            if digits != newValue {
                model.intervalDraft = digits
            }
        }
    }

    private var generalSection: some View {
        SettingsSection(i18n.localizedString("general_settings")) {
            SettingsRow(
                i18n.localizedString("launch_at_login"),
                description: i18n.localizedString("launch_at_login_description")
            ) {
                Toggle("", isOn: $appState.launchAtLogin)
                    .labelsHidden()
                    .disabled(appState.launchAtLoginRequiresApproval)
                    .accessibilityLabel(i18n.localizedString("launch_at_login"))
            }

            if appState.launchAtLoginRequiresApproval {
                WarningBanner(
                    message: i18n.localizedString("launch_at_login_pending_hint"),
                    systemImage: "desktopcomputer",
                    actionTitle: i18n.localizedString("open_login_items_settings")
                ) {
                    appState.openLaunchAtLoginSettings()
                }
            }

            Divider()

            SettingsRow(i18n.localizedString("language")) {
                Picker("", selection: $i18n.language) {
                    Text("中文")
                        .tag(LocalizationManager.Language.chinese)
                    Text("English")
                        .tag(LocalizationManager.Language.english)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 140)
                .accessibilityLabel(i18n.localizedString("language"))
            }

            Divider()

            DisclosureGroup(isExpanded: $showHelp) {
                Text(i18n.localizedString("help_content"))
                    .font(PanelFont.body)
                    .foregroundStyle(PanelColor.textSecondary)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            } label: {
                Text(i18n.localizedString("help"))
                    .font(PanelFont.body)
            }

            Button(i18n.localizedString("rerun_setup")) {
                model.startOnboarding(
                    step: model.permissionReady ? .networks : .permission
                )
            }
            .buttonStyle(.link)
            .font(PanelFont.body)
        }
    }

    private var automaticSection: some View {
        SettingsSection(i18n.localizedString("automatic_settings")) {
            SettingsRow(i18n.localizedString("check_frequency")) {
                FieldContainer {
                    TextField("", text: $model.intervalDraft)
                        .textFieldStyle(.plain)
                        .font(PanelFont.body)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 48)
                        .focused($intervalFocused)
                        .onSubmit { model.commitInterval() }
                        .accessibilityLabel(i18n.localizedString("check_frequency"))

                    Text(i18n.localizedString("seconds_unit"))
                        .font(PanelFont.caption)
                        .foregroundStyle(PanelColor.textSecondary)
                }
                .frame(width: 100)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(intervalSummary)
                    .font(PanelFont.caption)
                    .foregroundStyle(PanelColor.textSecondary)
                Text(
                    intervalWasAdjusted
                        ? String(
                            format: i18n.localizedString("interval_adjusted_format"),
                            i18n.duration(effectiveInterval)
                        )
                        : i18n.localizedString("interval_range_hint")
                )
                .font(PanelFont.caption)
                .foregroundStyle(
                    intervalWasAdjusted ? PanelColor.warning : PanelColor.textSecondary
                )
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChange(of: intervalFocused) { focused in
            if !focused {
                model.commitInterval()
            }
        }
    }

    private var aboutSection: some View {
        SettingsSection(i18n.localizedString("about")) {
            SettingsRow(i18n.localizedString("version")) {
                Text(versionText)
                    .font(PanelFont.body)
                    .foregroundStyle(PanelColor.textSecondary)
            }

            Text(i18n.localizedString("privacy_note"))
                .font(PanelFont.caption)
                .foregroundStyle(PanelColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Button(i18n.localizedString("quit_app")) {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(PanelFont.body)
            .foregroundStyle(PanelColor.textSecondary)
        }
    }

    private var effectiveInterval: Double {
        let text = model.intervalDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(text), value.isFinite else {
            return appState.checkInterval
        }
        return min(
            max(value, AppState.minimumCheckInterval),
            AppState.maximumCheckInterval
        )
    }

    private var intervalSummary: String {
        String(
            format: i18n.localizedString("interval_summary"),
            i18n.duration(effectiveInterval)
        )
    }

    private var intervalWasAdjusted: Bool {
        let text = model.intervalDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(text), value.isFinite else { return false }
        return value != effectiveInterval.rounded()
    }

    private var versionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        if let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
           !build.isEmpty {
            return "\(version) (\(build))"
        }
        return version
    }
}
