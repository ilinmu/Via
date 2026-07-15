import SwiftUI
import AppKit

public struct SettingsView: View {
    public static let panelWidth: CGFloat = 360

    @ObservedObject var appState: AppState
    var wifiManager: WifiManager
    @ObservedObject var i18n = LocalizationManager.shared
    var onHeightChange: (CGFloat) -> Void = { _ in }
    
    @State private var availableNetworks: [String] = []
    @State private var isScanning = false
    @State private var showHelp = false
    @State private var activeHeaderHint: String?
    
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
                .hoverHint(
                    i18n.localizedString("launch_at_login_tooltip"),
                    activeHint: $activeHeaderHint
                )
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
                .hoverHint(
                    i18n.localizedString("language_tooltip"),
                    activeHint: $activeHeaderHint
                )
                
                // Help Button
                Button(action: { showHelp.toggle() }) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .hoverHint(
                    i18n.localizedString("help_tooltip"),
                    activeHint: $activeHeaderHint
                )
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
                .hoverHint(
                    i18n.localizedString("quit_tooltip"),
                    activeHint: $activeHeaderHint
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)
            .zIndex(100)
            
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
                        VStack(alignment: .leading, spacing: 8) {
                            Divider()
                                .padding(.top, 12)

                            Text("✅ \(availableNetworks.count) \(i18n.localizedString("networks_found"))")
                                .font(.caption)
                                .foregroundColor(.green)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
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
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Text(i18n.localizedString("check_interval"))
                            .font(.caption)
                        TextField("60", value: $appState.checkInterval, formatter: NumberFormatter())
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 72)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text(
                        String(
                            format: i18n.localizedString("minimum_interval_hint"),
                            Int(AppState.minimumCheckInterval)
                        )
                    )
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Countdown (No Progress Bar)
                    if appState.isRunning, let nextCheck = wifiManager.nextCheckTime {
                        TimelineView(.animation) { context in
                            let now = context.date
                            let remaining = max(0, nextCheck.timeIntervalSince(now))
                            
                            Text(String(format: i18n.localizedString("next_check_in"), remaining))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                }
                .buttonStyle(.borderedProminent)
                .tint(appState.isRunning ? Color(red: 1.0, green: 0.184, blue: 0.212) : Color(red: 0.0, green: 0.431, blue: 0.945))
                .disabled(appState.ssidP.isEmpty || appState.ssidB.isEmpty)
                .padding()
                .background(Color(NSColor.controlBackgroundColor)) // Use controlBackgroundColor for softer look
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2) // Slightly stronger shadow
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow).ignoresSafeArea()) // Unified background
        .cornerRadius(16) // Rounded corners for the whole window content
        .frame(width: Self.panelWidth, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .readHeight { newHeight in
            onHeightChange(newHeight)
        }
        .overlay(alignment: .topTrailing) {
            if let activeHeaderHint {
                Text(activeHeaderHint)
                    .font(.caption2)
                    .foregroundColor(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 2)
                    .fixedSize()
                    .padding(.top, 44)
                    .padding(.trailing, 16)
                    .zIndex(1000)
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
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
                        .foregroundColor(.secondary)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 10)
            }
            .frame(height: 28)
            .padding(.leading, 11)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(NSColor.textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(NSColor.separatorColor).opacity(0.55), lineWidth: 1)
            )
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
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
    @Binding var activeHint: String?
    
    func body(content: Content) -> some View {
        content
            .padding(4)
            .contentShape(Rectangle())
            .help(text)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.15)) {
                    if hovering {
                        activeHint = text
                    } else if activeHint == text {
                        activeHint = nil
                    }
                }
            }
    }
}

private extension View {
    func hoverHint(_ text: String, activeHint: Binding<String?>) -> some View {
        modifier(HoverHintModifier(text: text, activeHint: activeHint))
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
