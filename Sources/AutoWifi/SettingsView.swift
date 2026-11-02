import SwiftUI
import AppKit
import CoreLocation
import AutoWifiCore

public struct SettingsView: View {
    public static let panelWidth: CGFloat = 400

    @ObservedObject var appState: AppState
    @ObservedObject var wifiManager: WifiManager
    @ObservedObject var i18n = LocalizationManager.shared
    var onHeightChange: (CGFloat) -> Void = { _ in }

    @State private var availableNetworks: [String] = []
    @State private var isScanning = false
    @State private var showHelp = false
    @State private var intervalDraft = ""
    @FocusState private var intervalFieldFocused: Bool

    private let currentNetworkAccent = TechPalette.blue

    private var displayedNetworkName: String {
        switch appState.networkStatus {
        case let .connected(ssid, _):
            return ssid
        case .notConnected:
            return i18n.localizedString("not_connected")
        case .permissionPending:
            return i18n.localizedString("permission_pending")
        case .permissionDenied:
            return i18n.localizedString("location_permission_denied")
        case .noInterface:
            return i18n.localizedString("wifi_unavailable")
        }
    }

    private var networkIconName: String {
        if case .connected(_, _) = appState.networkStatus {
            return "wifi"
        }
        return "wifi.slash"
    }

    private var isLocationDenied: Bool {
        if case .permissionDenied = appState.networkStatus {
            return true
        }
        return false
    }

    private var isLocationPending: Bool {
        if case .permissionPending = appState.networkStatus {
            return true
        }
        return false
    }

    private var launchAtLoginHint: String {
        if appState.launchAtLoginRequiresApproval {
            return i18n.localizedString("launch_at_login_pending_hint")
        }
        return i18n.localizedString("launch_at_login_tooltip")
    }

    private var launchAtLoginColor: Color {
        if appState.launchAtLoginRequiresApproval {
            return TechPalette.orange
        }
        return appState.launchAtLogin ? TechPalette.cyan : Color.white.opacity(0.52)
    }

    private var networkRoleText: String {
        switch appState.connectedNetworkType {
        case .priority:
            return i18n.localizedString("role_priority")
        case .backup:
            return i18n.localizedString("role_backup")
        case .other:
            return i18n.localizedString("role_other")
        case .none:
            return i18n.localizedString("role_offline")
        }
    }

    private var scanButtonValue: String {
        if isScanning {
            return i18n.localizedString("scanning")
        }
        if isLocationPending {
            return i18n.localizedString("permission_pending")
        }
        if isLocationDenied {
            return i18n.localizedString("location_permission_denied")
        }

        if !availableNetworks.isEmpty {
            return String(
                format: i18n.localizedString("networks_found_count"),
                availableNetworks.count
            )
        }

        return i18n.localizedString("scan_networks")
    }

    private var isScanDisabled: Bool {
        isScanning || isLocationPending || isLocationDenied
    }

    private var isConfigurationIncomplete: Bool {
        appState.ssidP.isEmpty || appState.ssidB.isEmpty
    }

    public init(
        appState: AppState,
        wifiManager: WifiManager,
        onHeightChange: @escaping (CGFloat) -> Void = { _ in }
    ) {
        self.appState = appState
        self.wifiManager = wifiManager
        self.onHeightChange = onHeightChange
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9)
                            .fill(Color(red: 0.08, green: 0.84, blue: 1.0).opacity(0.12))
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(Color(red: 0.08, green: 0.84, blue: 1.0).opacity(0.5), lineWidth: 1)
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Color(red: 0.22, green: 0.88, blue: 1.0))
                    }
                    .frame(width: 34, height: 34)

                    VStack(alignment: .leading, spacing: 2) {
                    Text(i18n.localizedString("app_title"))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    Text(i18n.localizedString("app_subtitle"))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(Color.white.opacity(0.45))
                            .textCase(.uppercase)
                    }
                }

                Spacer()

                // Launch at Login Button
                Button(action: {
                    if appState.launchAtLoginRequiresApproval {
                        appState.openLaunchAtLoginSettings()
                    } else {
                        appState.launchAtLogin.toggle()
                    }
                }) {
                    Image(systemName: appState.launchAtLoginRequiresApproval
                          ? "exclamationmark.circle"
                          : "desktopcomputer")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(launchAtLoginColor)
                        .frame(width: 28, height: 28)
                        .background(TechPalette.control, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(launchAtLoginHint)
                .hoverHint(launchAtLoginHint)
                .padding(.trailing, 4)

                // Language Toggle
                Button(action: { i18n.toggleLanguage() }) {
                    Text(i18n.language == .chinese ? "EN" : "中")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.72))
                        .frame(width: 28, height: 28)
                        .background(TechPalette.control, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(i18n.localizedString("language_tooltip"))
                .hoverHint(i18n.localizedString("language_tooltip"))

                // Help Button
                Button(action: { showHelp.toggle() }) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white.opacity(0.52))
                        .frame(width: 28, height: 28)
                        .background(TechPalette.control, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(i18n.localizedString("help_tooltip"))
                .hoverHint(i18n.localizedString("help_tooltip"))
                .popover(isPresented: $showHelp) {
                    HelpView()
                        .frame(width: 350, height: 390)
                }

                // Quit Button
                Button(action: { NSApplication.shared.terminate(nil) }) {
                    Image(systemName: "power")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(red: 1.0, green: 0.38, blue: 0.46))
                        .frame(width: 28, height: 28)
                        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.red.opacity(0.16)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(i18n.localizedString("quit_tooltip"))
                .hoverHint(i18n.localizedString("quit_tooltip"), alignment: .bottomTrailing)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)
            .zIndex(100)

            if isLocationDenied {
                HStack(spacing: 10) {
                    Image(systemName: "location.slash")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color(red: 1.0, green: 0.55, blue: 0.60))

                    Text(i18n.localizedString("location_permission_hint"))
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 4)

                    Button(action: openLocationSettings) {
                        Text(i18n.localizedString("open_location_settings"))
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.08), in: Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.2)))
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }

            if appState.launchAtLoginRequiresApproval {
                HStack(spacing: 10) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(TechPalette.orange)

                    Text(i18n.localizedString("launch_at_login_pending_hint"))
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 4)

                    Button(action: { appState.openLaunchAtLoginSettings() }) {
                        Text(i18n.localizedString("open_login_items_settings"))
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.08), in: Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(TechPalette.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(TechPalette.orange.opacity(0.24)))
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }

            if appState.credentialStorageWarning != nil {
                HStack(spacing: 10) {
                    Image(systemName: "key.slash")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(TechPalette.orange)

                    Text(i18n.localizedString("credential_storage_warning"))
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(TechPalette.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(TechPalette.orange.opacity(0.24)))
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }

            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        TechIcon(
                            systemName: networkIconName,
                            accent: currentNetworkAccent
                        )

                        VStack(alignment: .leading, spacing: 3) {
                            Text("00 / LINK STATUS")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundColor(currentNetworkAccent.opacity(0.78))
                            Text(displayedNetworkName)
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 4)

                        HStack(spacing: 6) {
                            Circle()
                                .fill(currentNetworkAccent)
                                .frame(width: 6, height: 6)
                                .shadow(color: currentNetworkAccent, radius: 5)
                            Text(networkRoleText)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.62))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.035), in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.08)))
                    }

                    HStack(spacing: 10) {
                        StatusMetric(
                            icon: appState.isRunning ? "bolt.fill" : "pause.fill",
                            title: i18n.localizedString("auto_switch"),
                            value: i18n.localizedString(appState.isRunning ? "status_active" : "status_paused"),
                            accent: currentNetworkAccent
                        )

                        if appState.isRunning, let nextCheck = wifiManager.nextCheckTime {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                let remaining = max(0, nextCheck.timeIntervalSince(context.date))
                                StatusMetric(
                                    icon: "timer",
                                    title: i18n.localizedString("next_check"),
                                    value: String(format: i18n.localizedString("seconds_short"), remaining),
                                    accent: currentNetworkAccent
                                )
                            }
                        } else {
                            StatusMetric(
                                icon: "shield.fill",
                                title: i18n.localizedString("mode"),
                                value: i18n.localizedString(appState.isRunning ? "automatic" : "manual"),
                                accent: currentNetworkAccent
                            )
                        }

                        Button(action: { scanNetworks() }) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 12, weight: .bold))
                                    .rotationEffect(.degrees(isScanning ? 360 : 0))
                                    .animation(isScanning ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isScanning)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(i18n.localizedString("network_discovery"))
                                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.38))
                                    Text(scanButtonValue)
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 0)
                            }
                            .foregroundColor(currentNetworkAccent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(currentNetworkAccent.opacity(0.18)))
                        }
                        .buttonStyle(.plain)
                        .disabled(isScanDisabled)
                        .accessibilityLabel(scanButtonValue)
                    }
                }
                .padding(18)
                .techPanel(accent: currentNetworkAccent)

                // Priority Network P
                NetworkCard(
                    title: i18n.localizedString("priority_network"),
                    code: "01 / PRIMARY",
                    ssid: $appState.ssidP,
                    password: $appState.passwordP,
                    networks: availableNetworks,
                    icon: "arrow.up.right",
                    accent: TechPalette.cyan
                )

                // Backup Network B
                NetworkCard(
                    title: i18n.localizedString("backup_network"),
                    code: "02 / BACKUP",
                    ssid: $appState.ssidB,
                    password: $appState.passwordB,
                    networks: availableNetworks,
                    icon: "arrow.triangle.branch",
                    accent: TechPalette.violet
                )

                // Settings & Control
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        TechIcon(systemName: "slider.horizontal.3", accent: TechPalette.green)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("03 / AUTOMATION")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundColor(TechPalette.green.opacity(0.78))
                            Text(i18n.localizedString("automation_settings"))
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        }

                        Spacer()

                        HStack(spacing: 6) {
                            Circle()
                                .fill(appState.isRunning ? TechPalette.green : Color.white.opacity(0.28))
                                .frame(width: 6, height: 6)
                                .shadow(color: appState.isRunning ? TechPalette.green : .clear, radius: 5)
                            Text(i18n.localizedString(appState.isRunning ? "status_active" : "status_paused"))
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.64))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.04), in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.08)))
                    }

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(i18n.localizedString("check_frequency"))
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.38))
                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                TextField("60", text: $intervalDraft)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 19, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                                    .focused($intervalFieldFocused)
                                    .onSubmit { commitCheckInterval() }
                                    .onChange(of: intervalFieldFocused) { focused in
                                        if !focused {
                                            commitCheckInterval()
                                        }
                                    }
                                    .frame(width: 48)
                                Text(i18n.localizedString("seconds_unit"))
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundColor(TechPalette.green.opacity(0.8))
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .frame(width: 112, alignment: .leading)
                        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.07)))

                        Text(
                            String(
                                format: i18n.localizedString("minimum_interval_hint"),
                                Int(AppState.minimumCheckInterval)
                            )
                        )
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.white.opacity(0.38))
                        .lineLimit(2)

                        Spacer(minLength: 0)
                    }

                    Button(action: {
                        if appState.isRunning {
                            wifiManager.stopMonitoring()
                        } else {
                            Task {
                                await wifiManager.startMonitoring()
                            }
                        }
                    }) {
                        HStack {
                            Image(systemName: appState.isRunning ? "stop.fill" : "play.fill")
                            Text(appState.isRunning ? i18n.localizedString("stop_monitoring") : i18n.localizedString("start_monitoring"))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .foregroundColor(appState.isRunning ? Color(red: 1.0, green: 0.55, blue: 0.60) : TechPalette.green)
                        .background(
                            (appState.isRunning ? Color.red : TechPalette.green).opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke((appState.isRunning ? Color.red : TechPalette.green).opacity(0.38), lineWidth: 1)
                        )
                        .shadow(color: (appState.isRunning ? Color.red : TechPalette.green).opacity(0.12), radius: 10)
                    }
                    .buttonStyle(.plain)

                    if !appState.isRunning && isConfigurationIncomplete {
                        Text(i18n.localizedString("configure_networks_hint"))
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.42))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .disabled(!appState.isRunning && isConfigurationIncomplete)
                .opacity(!appState.isRunning && isConfigurationIncomplete ? 0.65 : 1)
                .padding(16)
                .techPanel(accent: TechPalette.green)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(
            ZStack {
                LinearGradient(
                    colors: [TechPalette.backgroundTop, TechPalette.backgroundBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                TechGrid()
                    .opacity(0.42)
                RadialGradient(
                    colors: [TechPalette.cyan.opacity(0.11), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 260
                )
            }
            .ignoresSafeArea()
        )
        .cornerRadius(20)
        .colorScheme(.dark)
        .frame(width: Self.panelWidth, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .readHeight { newHeight in
            onHeightChange(newHeight)
        }
        .onAppear {
            intervalDraft = Self.intervalText(appState.checkInterval)
            wifiManager.refreshStatus()
        }
        .onChange(of: appState.checkInterval) { _ in
            intervalDraft = Self.intervalText(appState.checkInterval)
        }
        .onChange(of: wifiManager.locationAuthorizationStatus) { status in
            guard status == .authorizedAlways,
                  availableNetworks.isEmpty,
                  !isScanning,
                  !appState.isRunning
            else {
                return
            }
            scanNetworks()
        }
    }

    private func scanNetworks() {
        wifiManager.requestPermissions()

        switch wifiManager.locationAuthorizationStatus {
        case .denied, .restricted:
            appState.log(i18n.localizedString("location_permission_hint"))
            return
        case .notDetermined:
            appState.log(i18n.localizedString("permission_pending"))
            return
        default:
            break
        }

        isScanning = true
        availableNetworks = []
        appState.log(i18n.localizedString("scanning"))

        Task {
            let networks = await wifiManager.getAvailableNetworks()
            await MainActor.run {
                availableNetworks = networks
                isScanning = false

                appState.log(
                    i18n.localizedString(networks.isEmpty ? "permission_hint" : "scan_success")
                )
            }
        }
    }

    private func commitCheckInterval() {
        let trimmed = intervalDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = Double(trimmed), value.isFinite {
            appState.checkInterval = value
        }
        intervalDraft = Self.intervalText(appState.checkInterval)
    }

    private static func intervalText(_ value: Double) -> String {
        String(Int(value.rounded()))
    }

    private func openLocationSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

private struct StatusMetric: View {
    let icon: String
    let title: String
    let value: String
    let accent: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(accent)
                .frame(width: 28, height: 28)
                .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(accent.opacity(0.18)))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.66))
                Text(value)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.06)))
    }
}

private enum TechPalette {
    static let backgroundTop = Color(red: 0.035, green: 0.055, blue: 0.10)
    static let backgroundBottom = Color(red: 0.018, green: 0.025, blue: 0.052)
    static let panel = Color(red: 0.055, green: 0.075, blue: 0.125)
    static let control = Color(red: 0.07, green: 0.09, blue: 0.14)
    static let blue = Color(red: 0.20, green: 0.48, blue: 1.0)
    static let cyan = Color(red: 0.10, green: 0.82, blue: 1.0)
    static let violet = Color(red: 0.62, green: 0.42, blue: 1.0)
    static let green = Color(red: 0.20, green: 0.94, blue: 0.64)
    static let orange = Color(red: 1.0, green: 0.68, blue: 0.28)
}

private struct TechGrid: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            let spacing: CGFloat = 24

            for x in stride(from: CGFloat.zero, through: size.width, by: spacing) {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }

            for y in stride(from: CGFloat.zero, through: size.height, by: spacing) {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }

            context.stroke(path, with: .color(.white.opacity(0.025)), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}

private struct TechIcon: View {
    let systemName: String
    let accent: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(accent)
            .frame(width: 32, height: 32)
            .background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(accent.opacity(0.25)))
    }
}

struct NetworkCard: View {
    let title: String
    let code: String
    @Binding var ssid: String
    @Binding var password: String
    let networks: [String]
    let icon: String
    let accent: Color
    @ObservedObject var i18n = LocalizationManager.shared
    @State private var showPassword = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TechIcon(systemName: icon, accent: accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(code)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(accent.opacity(0.78))
                    Text(title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }

                Spacer()

                HStack(spacing: 6) {
                    Circle()
                        .fill(ssid.isEmpty ? Color.white.opacity(0.25) : accent)
                        .frame(width: 6, height: 6)
                        .shadow(color: ssid.isEmpty ? .clear : accent, radius: 5)
                    Text(ssid.isEmpty ? i18n.localizedString("not_configured") : i18n.localizedString("configured"))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.58))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.035), in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.07)))
            }

            HStack(spacing: 6) {
                TextField(i18n.localizedString("ssid_placeholder"), text: $ssid)
                    .textFieldStyle(.plain)
                    .foregroundColor(.white)
                    .padding(.horizontal, 11)
                    .frame(height: 32)
                    .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.08)))

                if !networks.isEmpty {
                    Menu {
                        ForEach(networks, id: \.self) { network in
                            Button(network) {
                                ssid = network
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(accent)
                            .frame(width: 30, height: 32)
                            .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.08)))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .accessibilityLabel(i18n.localizedString("select_network"))
                }
            }

            HStack(spacing: 6) {
                if showPassword {
                    PasswordInputField(
                        text: $password,
                        placeholder: i18n.localizedString("password"),
                        isSecure: false
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    PasswordInputField(
                        text: $password,
                        placeholder: i18n.localizedString("password"),
                        isSecure: true
                    )
                    .frame(maxWidth: .infinity)
                }

                Button(action: { showPassword.toggle() }) {
                    Image(systemName: showPassword ? "eye.slash" : "eye")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.42))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    i18n.localizedString(showPassword ? "hide_password" : "show_password")
                )
                .padding(.trailing, 10)
            }
            .frame(height: 28)
            .padding(.leading, 11)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.20))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .padding(16)
        .techPanel(accent: accent)
    }
}

private final class PasteEnabledTextField: NSTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handleClipboardShortcut(event) || super.performKeyEquivalent(with: event)
    }
}

private final class PasteEnabledSecureTextField: NSSecureTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handleClipboardShortcut(event) || super.performKeyEquivalent(with: event)
    }
}

private extension NSTextField {
    func handleClipboardShortcut(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
              let key = event.charactersIgnoringModifiers?.lowercased()
        else {
            return false
        }

        switch key {
        case "v":
            NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self)
            return true
        case "c":
            NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self)
            return true
        case "x":
            NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self)
            return true
        case "a":
            NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self)
            return true
        default:
            return false
        }
    }
}

private final class PasswordFieldCoordinator: NSObject, NSTextFieldDelegate {
    var text: Binding<String>

    init(text: Binding<String>) {
        self.text = text
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let textField = notification.object as? NSTextField else { return }
        text.wrappedValue = textField.stringValue
    }
}

private struct PasswordInputField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let isSecure: Bool

    func makeCoordinator() -> PasswordFieldCoordinator {
        PasswordFieldCoordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField: NSTextField = isSecure
            ? PasteEnabledSecureTextField(string: text)
            : PasteEnabledTextField(string: text)
        configure(textField, coordinator: context.coordinator)
        textField.identifier = NSUserInterfaceItemIdentifier(rawValue: "PasswordInputTextField")
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        nsView.placeholderString = placeholder
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }
}

@MainActor
private func configure(_ textField: NSTextField, coordinator: PasswordFieldCoordinator) {
    textField.delegate = coordinator
    textField.isEditable = true
    textField.isSelectable = true
    textField.isBezeled = false
    textField.isBordered = false
    textField.drawsBackground = false
    textField.focusRingType = .none
    textField.font = .systemFont(ofSize: 13)
    textField.lineBreakMode = .byClipping
    textField.placeholderString = ""
    textField.usesSingleLineMode = true
    textField.menu = makeEditingMenu()
    textField.translatesAutoresizingMaskIntoConstraints = false
}

struct HelpView: View {
    @ObservedObject var i18n = LocalizationManager.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                TechIcon(systemName: "questionmark.circle.fill", accent: TechPalette.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text("SYS / HELP CENTER")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(TechPalette.blue.opacity(0.78))
                    Text(i18n.localizedString("help"))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }

                Spacer()

                HStack(spacing: 5) {
                    Circle()
                        .fill(TechPalette.green)
                        .frame(width: 6, height: 6)
                        .shadow(color: TechPalette.green, radius: 4)
                    Text(i18n.localizedString("local_only"))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .padding(16)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [TechPalette.blue.opacity(0.65), Color.white.opacity(0.04), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)

            ScrollView {
                Text(i18n.localizedString("help_content"))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.white.opacity(0.7))
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        }
        .background(
            ZStack {
                LinearGradient(
                    colors: [TechPalette.backgroundTop, TechPalette.backgroundBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                TechGrid().opacity(0.5)
                RadialGradient(
                    colors: [TechPalette.blue.opacity(0.12), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 220
                )
            }
        )
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(TechPalette.blue.opacity(0.28)))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .colorScheme(.dark)
    }
}

private func makeEditingMenu() -> NSMenu {
    let menu = NSMenu()
    menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "")
    menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "")
    menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "")
    menu.addItem(NSMenuItem.separator())
    menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "")
    return menu
}

private struct HoverHintModifier: ViewModifier {
    let text: String
    let alignment: Alignment
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .padding(4)
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.15)) {
                    isHovering = hovering
                }
            }
            .overlay(alignment: alignment) {
                if isHovering {
                    Text(text)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.88))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(TechPalette.control.opacity(0.98), in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.12)))
                        .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 4)
                        .fixedSize()
                        .offset(y: 30)
                        .zIndex(1000)
                        .allowsHitTesting(false)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                }
            }
            .zIndex(isHovering ? 1000 : 0)
    }
}

private extension View {
    func techPanel(accent: Color) -> some View {
        background(
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(TechPalette.panel.opacity(0.92))

                LinearGradient(
                    colors: [accent.opacity(0.09), .clear],
                    startPoint: .topLeading,
                    endPoint: .center
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                Rectangle()
                    .fill(accent)
                    .frame(width: 34, height: 2)
                    .padding(.leading, 16)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [accent.opacity(0.38), Color.white.opacity(0.07), Color.white.opacity(0.035)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.28), radius: 12, x: 0, y: 7)
    }

    func hoverHint(_ text: String, alignment: Alignment = .bottom) -> some View {
        modifier(HoverHintModifier(text: text, alignment: alignment))
    }

    func readHeight(onChange: @escaping (CGFloat) -> Void) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: HeightPreferenceKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(HeightPreferenceKey.self, perform: onChange)
    }
}

private struct HeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
