import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var controller: WifiController
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            StatusView(selection: $selection)
                .tag(0)
                .tabItem {
                    Label(L10n.t("tab_status", controller.language), systemImage: "wifi")
                }

            NetworksView()
                .tag(1)
                .tabItem {
                    Label(
                        L10n.t("tab_networks", controller.language),
                        systemImage: "network"
                    )
                }

            SettingsView()
                .tag(2)
                .tabItem {
                    Label(
                        L10n.t("tab_settings", controller.language),
                        systemImage: "gearshape"
                    )
                }
        }
        .tint(ViaColors.accent)
        .sheet(isPresented: $controller.showOnboarding, onDismiss: {
            controller.markOnboardingSeen()
        }) {
            OnboardingView()
                .environmentObject(controller)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                controller.refreshPermission()
                Task {
                    await controller.resumeMonitoringIfNeeded()
                    await controller.resumeFromBackground()
                }
            } else {
                controller.pauseForBackground()
            }
        }
    }
}

private struct StatusView: View {
    @EnvironmentObject private var controller: WifiController
    @Binding var selection: Int

    private var hasLocationAccess: Bool {
        controller.permission == .authorizedAlways || controller.permission == .authorizedWhenInUse
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    connectionHeader

                    Divider()

                    Toggle(isOn: Binding(
                        get: { controller.isRunning },
                        set: { enabled in
                            if enabled {
                                Task { await controller.startMonitoring() }
                            } else {
                                controller.stopMonitoring()
                            }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.t("auto_switch", controller.language))
                                .font(.body.weight(.semibold))
                            Text(L10n.t("auto_switch_hint", controller.language))
                                .font(.footnote)
                                .foregroundStyle(ViaColors.secondaryText)
                        }
                    }
                    .disabled(
                        !controller.isRunning
                            && (!controller.isComplete
                                || controller.permission == .denied
                                || controller.permission == .restricted)
                    )

                    if !controller.isComplete {
                        setupHint
                    }

                    if controller.isRunning {
                        nextCheck
                    }

                    if !hasLocationAccess {
                        permissionCard
                    }

                    if !controller.message.isEmpty {
                        Text(controller.message)
                            .font(.footnote)
                            .foregroundStyle(ViaColors.secondaryText)
                    }

                    Button {
                        Task { await controller.checkNow() }
                    } label: {
                        Label(
                            L10n.t("refresh", controller.language),
                            systemImage: "arrow.clockwise"
                        )
                    }
                    .buttonStyle(.bordered)
                    .disabled(!controller.isRunning || controller.isChecking)
                }
                .padding()
            }
            .background(ViaColors.background)
            .navigationTitle(L10n.t("app_title", controller.language))
        }
    }

    private var connectionHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            StatusIcon(
                role: controller.role,
                isRunning: controller.isRunning,
                size: 32
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(
                    controller.currentSSID
                        ?? L10n.t("not_connected", controller.language)
                )
                .font(.title2.weight(.semibold))
                .lineLimit(2)
                if controller.currentSSID != nil, controller.role != .none {
                    Text(roleText)
                        .font(.footnote)
                        .foregroundStyle(ViaColors.secondaryText)
                }
            }
        }
    }

    private var setupHint: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(ViaColors.secondaryText)
            Text(L10n.t("status_setup_hint", controller.language))
                .font(.footnote)
                .foregroundStyle(ViaColors.secondaryText)
            Spacer(minLength: 8)
            Button(L10n.t("open_networks", controller.language)) {
                selection = 1
            }
            .font(.footnote)
        }
    }

    @ViewBuilder
    private var nextCheck: some View {
        HStack {
            Text(L10n.t("next_check", controller.language))
                .font(.footnote)
                .foregroundStyle(ViaColors.secondaryText)
            Spacer(minLength: 8)
            if controller.isChecking {
                Text(L10n.t("waiting", controller.language))
                    .font(.footnote)
                    .foregroundStyle(ViaColors.secondaryText)
            } else if let next = controller.nextCheck {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(
                        L10n.duration(
                            max(0, Int(next.timeIntervalSince(context.date))),
                            controller.language
                        )
                    )
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(ViaColors.secondaryText)
                }
            }
        }
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.t("permission_required", controller.language))
                .font(.footnote)
            HStack(spacing: 12) {
                if controller.permission == .notDetermined {
                    Button(L10n.t("grant_permission", controller.language)) {
                        controller.requestPermission()
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button(L10n.t("open_settings", controller.language)) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            ViaColors.warning.opacity(0.10),
            in: RoundedRectangle(cornerRadius: 10)
        )
    }

    private var roleText: String {
        switch controller.role {
        case .priority:
            return L10n.t("role_priority", controller.language)
        case .backup:
            return L10n.t("role_backup", controller.language)
        case .other:
            return L10n.t("role_other", controller.language)
        case .none:
            return L10n.t("role_none", controller.language)
        }
    }
}

private struct NetworksView: View {
    @EnvironmentObject private var controller: WifiController
    @State private var showValidation = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(L10n.t("networks_description", controller.language))
                        .font(.footnote)
                        .foregroundStyle(ViaColors.secondaryText)
                    Text(L10n.t("scan_unavailable", controller.language))
                        .font(.footnote)
                        .foregroundStyle(ViaColors.secondaryText)
                }

                Section {
                    NetworkEditor(
                        title: L10n.t("priority_network", controller.language),
                        ssid: $controller.ssidP,
                        password: $controller.passwordP,
                        language: controller.language,
                        currentSSID: controller.currentSSID,
                        onUseCurrent: {
                            Task {
                                await controller.useCurrent(primary: true)
                            }
                        }
                    )
                    NetworkEditor(
                        title: L10n.t("backup_network", controller.language),
                        ssid: $controller.ssidB,
                        password: $controller.passwordB,
                        language: controller.language,
                        currentSSID: controller.currentSSID,
                        onUseCurrent: {
                            Task {
                                await controller.useCurrent(primary: false)
                            }
                        }
                    )
                }

                Section {
                    Button(L10n.t("save_changes", controller.language)) {
                        showValidation = !controller.save()
                    }
                    if controller.hasUnsavedChanges {
                        Text(L10n.t("unsaved", controller.language))
                            .font(.footnote)
                            .foregroundStyle(ViaColors.warning)
                    }
                    if showValidation, !controller.message.isEmpty {
                        Text(controller.message)
                            .font(.footnote)
                            .foregroundStyle(ViaColors.danger)
                    }
                    Text(L10n.t("password_optional", controller.language))
                        .font(.footnote)
                        .foregroundStyle(ViaColors.secondaryText)
                }
            }
            .scrollContentBackground(.hidden)
            .background(ViaColors.background)
            .navigationTitle(L10n.t("tab_networks", controller.language))
        }
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var controller: WifiController

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(L10n.t("settings_general", controller.language))) {
                    Picker(L10n.t("language", controller.language), selection: $controller.language) {
                        Text("中文").tag("zh")
                        Text("English").tag("en")
                    }
                    .pickerStyle(.menu)

                    Picker(L10n.t("interval", controller.language), selection: $controller.checkInterval) {
                        ForEach(intervalOptions, id: \.self) { seconds in
                            Text(L10n.duration(seconds, controller.language)).tag(seconds)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section {
                    Text(L10n.t("ios_background_note", controller.language))
                        .font(.footnote)
                        .foregroundStyle(ViaColors.secondaryText)
                }

                Section(header: Text(L10n.t("about", controller.language))) {
                    HStack {
                        Text(L10n.t("version", controller.language))
                        Spacer()
                        Text(versionText)
                            .foregroundStyle(ViaColors.secondaryText)
                    }
                    Text(L10n.t("privacy_note", controller.language))
                        .font(.footnote)
                        .foregroundStyle(ViaColors.secondaryText)
                }

                Section {
                    Button(L10n.t("rerun_setup", controller.language)) {
                        controller.showOnboarding = true
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(ViaColors.background)
            .navigationTitle(L10n.t("tab_settings", controller.language))
        }
    }

    private var intervalOptions: [Int] {
        var options = [30, 60, 300, 900, 1800, 3600]
        if !options.contains(controller.checkInterval) {
            options.append(controller.checkInterval)
        }
        return options.sorted()
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

private struct NetworkEditor: View {
    let title: String
    @Binding var ssid: String
    @Binding var password: String
    let language: String
    let currentSSID: String?
    let onUseCurrent: () -> Void
    @State private var showPassword = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.body.weight(.semibold))

            TextField(L10n.t("network_name", language), text: $ssid)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)

            if let currentSSID, currentSSID != ssid {
                Button {
                    onUseCurrent()
                } label: {
                    Label(L10n.t("use_current", language), systemImage: "wifi")
                        .font(.footnote)
                }
                .buttonStyle(.borderless)
            }

            HStack {
                Group {
                    if showPassword {
                        TextField(L10n.t("password", language), text: $password)
                    } else {
                        SecureField(L10n.t("password", language), text: $password)
                    }
                }
                .textFieldStyle(.roundedBorder)

                Button {
                    showPassword.toggle()
                } label: {
                    Image(systemName: showPassword ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(
                    L10n.t(showPassword ? "hide_password" : "show_password", language)
                )
            }
        }
        .padding(.vertical, 4)
    }
}

private struct OnboardingView: View {
    @EnvironmentObject private var controller: WifiController
    @State private var step = 0

    private var hasLocationAccess: Bool {
        controller.permission == .authorizedAlways || controller.permission == .authorizedWhenInUse
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("\(step + 1) / 3")
                    .font(.footnote)
                    .foregroundStyle(ViaColors.secondaryText)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        switch step {
                        case 0:
                            permissionStep
                        case 1:
                            networksStep
                        default:
                            finishStep
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 10) {
                    if step > 0 {
                        Button(L10n.t("back", controller.language)) {
                            step -= 1
                        }
                        .buttonStyle(.bordered)
                    }

                    if step < 2 {
                        Button(L10n.t("skip", controller.language)) {
                            controller.markOnboardingSeen()
                        }
                        .foregroundStyle(ViaColors.secondaryText)
                    }

                    Spacer()

                    if step < 2 {
                        Button(L10n.t("next", controller.language)) {
                            step += 1
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(step == 1 && !controller.isComplete)
                    } else {
                        Button(L10n.t("save_only", controller.language)) {
                            if controller.save() {
                                controller.markOnboardingSeen()
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(!controller.isComplete)

                        if hasLocationAccess {
                            Button(L10n.t("start", controller.language)) {
                                Task {
                                    await controller.startMonitoring()
                                    if controller.isRunning {
                                        controller.markOnboardingSeen()
                                    }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!controller.isComplete)
                        } else {
                            Button(L10n.t("open_settings", controller.language)) {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
            .padding()
            .background(ViaColors.background)
            .navigationTitle(L10n.t("app_title", controller.language))
        }
    }

    private var permissionStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.t("onboarding_permission_title", controller.language))
                .font(.title2.weight(.semibold))
            Text(L10n.t("onboarding_permission_body", controller.language))
                .foregroundStyle(ViaColors.secondaryText)

            if hasLocationAccess {
                Label(
                    L10n.t("grant_permission", controller.language),
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundStyle(ViaColors.accentText)
            } else if controller.permission == .notDetermined {
                Button(L10n.t("grant_permission", controller.language)) {
                    controller.requestPermission()
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button(L10n.t("open_settings", controller.language)) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                Text(L10n.t("onboarding_permission_denied_body", controller.language))
                    .font(.footnote)
                    .foregroundStyle(ViaColors.secondaryText)
            }

            Text(L10n.t("onboarding_permission_always_hint", controller.language))
                .font(.footnote)
                .foregroundStyle(ViaColors.secondaryText)
        }
    }

    private var networksStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.t("onboarding_networks_title", controller.language))
                .font(.title2.weight(.semibold))
            Text(L10n.t("onboarding_networks_body", controller.language))
                .foregroundStyle(ViaColors.secondaryText)
            Text(L10n.t("scan_unavailable", controller.language))
                .font(.footnote)
                .foregroundStyle(ViaColors.secondaryText)

            NetworkEditor(
                title: L10n.t("priority_network", controller.language),
                ssid: $controller.ssidP,
                password: $controller.passwordP,
                language: controller.language,
                currentSSID: controller.currentSSID,
                onUseCurrent: {
                    Task { await controller.useCurrent(primary: true) }
                }
            )
            NetworkEditor(
                title: L10n.t("backup_network", controller.language),
                ssid: $controller.ssidB,
                password: $controller.passwordB,
                language: controller.language,
                currentSSID: controller.currentSSID,
                onUseCurrent: {
                    Task { await controller.useCurrent(primary: false) }
                }
            )

            if !controller.message.isEmpty {
                Text(controller.message)
                    .font(.footnote)
                    .foregroundStyle(ViaColors.secondaryText)
            }
        }
    }

    private var finishStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.t("onboarding_finish_title", controller.language))
                .font(.title2.weight(.semibold))
            Text(L10n.t("onboarding_finish_body", controller.language))
                .foregroundStyle(ViaColors.secondaryText)

            VStack(spacing: 8) {
                summaryRow(
                    L10n.t("priority_network", controller.language),
                    controller.ssidP
                )
                Divider()
                summaryRow(
                    L10n.t("backup_network", controller.language),
                    controller.ssidB
                )
                Divider()
                summaryRow(
                    L10n.t("permission_label", controller.language),
                    hasLocationAccess
                        ? L10n.t("permission_granted", controller.language)
                        : L10n.t("permission_required", controller.language)
                )
            }

            if !hasLocationAccess {
                Text(L10n.t("start_unavailable_permission", controller.language))
                    .font(.footnote)
                    .foregroundStyle(ViaColors.warning)
            }

            if !controller.message.isEmpty {
                Text(controller.message)
                    .font(.footnote)
                    .foregroundStyle(ViaColors.secondaryText)
            }
        }
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(ViaColors.secondaryText)
            Spacer(minLength: 12)
            Text(value.isEmpty ? "—" : value)
                .font(.body)
                .multilineTextAlignment(.trailing)
        }
    }
}
