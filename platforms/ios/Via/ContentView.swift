import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var controller: WifiController
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            StatusView()
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
        .sheet(isPresented: $controller.showOnboarding) {
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 14) {
                        StatusIcon(
                            role: controller.role,
                            isRunning: controller.isRunning,
                            size: 32
                        )
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.t("current_network", controller.language))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(controller.currentSSID ?? L10n.t("not_connected", controller.language))
                                .font(.title2.weight(.semibold))
                            Text(roleText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

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
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.t("auto_switch", controller.language))
                                .font(.headline)
                            Text(L10n.t("auto_switch_hint", controller.language))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if controller.permission != .authorizedAlways &&
                        controller.permission != .authorizedWhenInUse {
                        permissionCard
                    }

                    if !controller.message.isEmpty {
                        Text(controller.message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
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

                    Text(L10n.t("ios_limitation", controller.language))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle(L10n.t("app_title", controller.language))
        }
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t("permission_required", controller.language))
                .font(.subheadline)
            HStack {
                Button(L10n.t("grant_permission", controller.language)) {
                    controller.requestPermission()
                }
                .buttonStyle(.borderedProminent)

                Button(L10n.t("open_settings", controller.language)) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(L10n.t("networks_description", controller.language))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    NetworkEditor(
                        title: L10n.t("priority_network", controller.language),
                        ssid: $controller.ssidP,
                        password: $controller.passwordP,
                        language: controller.language
                    )
                    NetworkEditor(
                        title: L10n.t("backup_network", controller.language),
                        ssid: $controller.ssidB,
                        password: $controller.passwordB,
                        language: controller.language
                    )
                }

                Section {
                    Button(L10n.t("save_changes", controller.language)) {
                        controller.save()
                    }
                    .disabled(!controller.isComplete)

                    Text(L10n.t("password_optional", controller.language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Text(L10n.t("scan_unavailable", controller.language))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button(L10n.t("use_current", controller.language)) {
                        Task { await controller.useCurrentNetwork() }
                    }
                }
            }
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
                    // A menu picker matches macOS: one row showing the current
                    // language that opens a list, instead of side-by-side chips.
                    .pickerStyle(.menu)

                    Stepper(
                        value: $controller.checkInterval,
                        in: 5...3600
                    ) {
                        Text("\(L10n.t("interval", controller.language)): \(controller.checkInterval) \(L10n.t("seconds", controller.language))")
                    }
                }

                Section {
                    Text(L10n.t("ios_background_note", controller.language))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section(header: Text(L10n.t("about", controller.language))) {
                    Text("\(L10n.t("version", controller.language)) 1.0")
                    Text(L10n.t("privacy_note", controller.language))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button(L10n.t("rerun_setup", controller.language)) {
                        controller.showOnboarding = true
                    }
                }
            }
            .navigationTitle(L10n.t("tab_settings", controller.language))
        }
    }
}

private struct NetworkEditor: View {
    let title: String
    @Binding var ssid: String
    @Binding var password: String
    let language: String
    @State private var showPassword = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            TextField("SSID", text: $ssid)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)

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

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("\(step + 1) / 3")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                switch step {
                case 0:
                    Text(L10n.t("onboarding_permission_title", controller.language))
                        .font(.title2.weight(.semibold))
                    Text(L10n.t("onboarding_permission_body", controller.language))
                        .foregroundStyle(.secondary)
                    Button(L10n.t("grant_permission", controller.language)) {
                        controller.requestPermission()
                    }
                    .buttonStyle(.borderedProminent)

                case 1:
                    Text(L10n.t("onboarding_networks_title", controller.language))
                        .font(.title2.weight(.semibold))
                    Text(L10n.t("onboarding_networks_body", controller.language))
                        .foregroundStyle(.secondary)
                    NetworkEditor(
                        title: L10n.t("priority_network", controller.language),
                        ssid: $controller.ssidP,
                        password: $controller.passwordP,
                        language: controller.language
                    )
                    NetworkEditor(
                        title: L10n.t("backup_network", controller.language),
                        ssid: $controller.ssidB,
                        password: $controller.passwordB,
                        language: controller.language
                    )

                default:
                    Text(L10n.t("onboarding_finish_title", controller.language))
                        .font(.title2.weight(.semibold))
                    Text(L10n.t("onboarding_finish_body", controller.language))
                        .foregroundStyle(.secondary)
                    Text("\(L10n.t("priority_network", controller.language)): \(controller.ssidP)")
                    Text("\(L10n.t("backup_network", controller.language)): \(controller.ssidB)")
                }

                Spacer()

                HStack {
                    if step > 0 {
                        Button(L10n.t("back", controller.language)) {
                            step -= 1
                        }
                    }

                    Button(L10n.t("skip", controller.language)) {
                        controller.showOnboarding = false
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
                                controller.showOnboarding = false
                            }
                        }
                        .disabled(!controller.isComplete)

                        Button(L10n.t("start", controller.language)) {
                            Task {
                                await controller.startMonitoring()
                                if controller.isRunning {
                                    controller.showOnboarding = false
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!controller.isComplete)
                    }
                }
            }
            .padding()
            .navigationTitle(L10n.t("app_title", controller.language))
        }
    }
}
