import SwiftUI

public struct SettingsView: View {
    @ObservedObject var appState: AppState
    var wifiManager: WifiManager
    @ObservedObject var i18n = LocalizationManager.shared
    
    @State private var availableNetworks: [String] = []
    @State private var isScanning = false
    @State private var showHelp = false
    
    public init(appState: AppState, wifiManager: WifiManager) {
        self.appState = appState
        self.wifiManager = wifiManager
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(i18n.localizedString("app_title"))
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Launch at Login Button
                Button(action: { appState.launchAtLogin.toggle() }) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 16))
                        .foregroundColor(appState.launchAtLogin ? .blue : .secondary)
                }
                .buttonStyle(.plain)
                .help(i18n.localizedString("launch_at_login_tooltip"))
                .padding(.trailing, 4)
                
                // Language Toggle
                Button(action: { i18n.toggleLanguage() }) {
                    Text(i18n.language == .chinese ? "EN" : "中")
                        .font(.caption)
                        .padding(4)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help(i18n.localizedString("language_tooltip"))
                
                // Help Button
                Button(action: { showHelp.toggle() }) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(i18n.localizedString("help_tooltip"))
                .popover(isPresented: $showHelp) {
                    HelpView()
                        .frame(width: 300, height: 250)
                }
                
                // Quit Button
                Button(action: { NSApplication.shared.terminate(nil) }) {
                    Image(systemName: "power")
                        .font(.system(size: 16))
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .help(i18n.localizedString("quit_tooltip"))
            }
            .padding()
            // Removed header background to let root background show through
            
            ScrollView {
                VStack(spacing: 16) {
                    // Current Status Card & Scan
                    VStack(spacing: 0) {
                        HStack {
                            Image(systemName: "wifi")
                                .font(.system(size: 24))
                                .foregroundColor(.blue)
                            VStack(alignment: .leading) {
                                Text(i18n.localizedString("current_network"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(appState.currentNetworkName)
                                    .font(.title3)
                                    .fontWeight(.semibold)
                            }
                            
                            Spacer()
                            
                            // Scan Button
                            Button(action: { scanNetworks() }) {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                        .rotationEffect(.degrees(isScanning ? 360 : 0))
                                        .animation(isScanning ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isScanning)
                                    if !isScanning {
                                        Text(i18n.localizedString("scan_networks"))
                                            .font(.caption)
                                    }
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(isScanning)
                        }
                        
                        if !availableNetworks.isEmpty {
                            Divider()
                            Text("✅ \(availableNetworks.count) \(i18n.localizedString("networks_found"))")
                                .font(.caption)
                                .foregroundColor(.green)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                    
                    // Priority Network P
                    NetworkCard(
                        title: i18n.localizedString("priority_network"),
                        ssid: $appState.ssidP,
                        password: $appState.passwordP,
                        networks: availableNetworks,
                        icon: "star.fill",
                        color: .yellow
                    )
                    
                    // Backup Network B
                    NetworkCard(
                        title: i18n.localizedString("backup_network"),
                        ssid: $appState.ssidB,
                        password: $appState.passwordB,
                        networks: availableNetworks,
                        icon: "arrow.triangle.2.circlepath",
                        color: .orange
                    )
                    
                    // Settings & Control
                    VStack(spacing: 12) {
                        HStack {
                            Text(i18n.localizedString("check_interval"))
                                .font(.caption)
                            TextField("60", value: $appState.checkInterval, formatter: NumberFormatter())
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                        }
                        
                        // Countdown (No Progress Bar)
                        if appState.isRunning, let nextCheck = wifiManager.nextCheckTime {
                            TimelineView(.animation) { context in
                                let now = context.date
                                let remaining = max(0, nextCheck.timeIntervalSince(now))
                                
                                Text(String(format: i18n.localizedString("next_check_in"), remaining))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        
                        Button(action: {
                            if appState.isRunning {
                                wifiManager.stopMonitoring()
                            } else {
                                wifiManager.startMonitoring()
                            }
                        }) {
                            HStack {
                                Image(systemName: appState.isRunning ? "stop.fill" : "play.fill")
                                Text(appState.isRunning ? i18n.localizedString("stop_monitoring") : i18n.localizedString("start_monitoring"))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(appState.isRunning ? Color(red: 1.0, green: 0.184, blue: 0.212) : Color(red: 0.0, green: 0.431, blue: 0.945))
                        .disabled(appState.ssidP.isEmpty || appState.ssidB.isEmpty)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor)) // Use controlBackgroundColor for softer look
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2) // Slightly stronger shadow
                }
                .padding()
            }
            // Removed ScrollView background to let root background show through
        }
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow).ignoresSafeArea()) // Unified background
        .cornerRadius(16) // Rounded corners for the whole window content
        .frame(width: 360, height: 560)
        .onAppear {
            wifiManager.refreshStatus()
        }
    }
    
    private func scanNetworks() {
        wifiManager.requestPermissions()
        isScanning = true
        availableNetworks = []
        appState.log(i18n.localizedString("scanning"))
        
        Task {
            let networks = await wifiManager.getAvailableNetworks()
            await MainActor.run {
                availableNetworks = networks
                isScanning = false
                
                if networks.isEmpty {
                    appState.log(i18n.localizedString("permission_hint"))
                } else {
                    appState.log(i18n.localizedString("scan_success"))
                }
            }
        }
    }
}

struct NetworkCard: View {
    let title: String
    @Binding var ssid: String
    @Binding var password: String
    let networks: [String]
    let icon: String
    let color: Color
    @ObservedObject var i18n = LocalizationManager.shared
    @State private var showPassword = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            
            if networks.isEmpty {
                TextField(i18n.localizedString("ssid_placeholder"), text: $ssid)
                    .textFieldStyle(.roundedBorder)
            } else {
                Picker("", selection: $ssid) {
                    Text(i18n.localizedString("select_network")).tag("")
                    ForEach(networks, id: \.self) { network in
                        Text(network).tag(network)
                    }
                }
                .labelsHidden()
            }
            
            HStack {
                if showPassword {
                    TextField(i18n.localizedString("password"), text: $password)
                        .textFieldStyle(.roundedBorder)
                } else {
                    SecureField(i18n.localizedString("password"), text: $password)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .overlay(
                Button(action: { showPassword.toggle() }) {
                    Image(systemName: showPassword ? "eye.slash" : "eye")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
                , alignment: .trailing
            )
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

struct HelpView: View {
    @ObservedObject var i18n = LocalizationManager.shared
    
    var body: some View {
        ScrollView {
            Text(i18n.localizedString("help_content"))
                .padding()
        }
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = .active
        return visualEffectView
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
