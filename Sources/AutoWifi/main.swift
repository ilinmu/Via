import Cocoa
import SwiftUI
import Combine
import AutoWifiCore

@MainActor
final class FocusablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
              let key = event.charactersIgnoringModifiers?.lowercased(),
              let action = Self.editingAction(for: key)
        else {
            return super.performKeyEquivalent(with: event)
        }

        if NSApp.sendAction(action, to: nil, from: self) {
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    private static func editingAction(for key: String) -> Selector? {
        switch key {
        case "x":
            return #selector(NSText.cut(_:))
        case "c":
            return #selector(NSText.copy(_:))
        case "v":
            return #selector(NSText.paste(_:))
        case "a":
            return #selector(NSText.selectAll(_:))
        default:
            return nil
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var window: NSPanel!
    var appState = AppState()
    var wifiManager: WifiManager!
    var cancellables = Set<AnyCancellable>()
    var eventMonitor: Any?
    var preferredPanelHeight: CGFloat = 440
    private var statusImageCache: [StatusImageKey: NSImage] = [:]

    private struct StatusImageKey: Hashable {
        let type: AppState.ConnectedNetworkType
        let isRunning: Bool
        let isDark: Bool
        let scale: Int
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Initialize WifiManager
        wifiManager = WifiManager(appState: appState)
        if appState.isRunning {
            Task { @MainActor in
                await wifiManager.startMonitoring()
            }
        }
        
        // Create the SwiftUI view
        let contentView = SettingsView(
            appState: appState,
            wifiManager: wifiManager
        ) { [weak self] newHeight in
            self?.updateWindowHeight(to: newHeight)
        }

        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame.size.width = SettingsView.panelWidth
        preferredPanelHeight = max(ceil(hostingView.fittingSize.height), 360)

        // Create the window at its final fitted height. This prevents the first
        // presentation from showing a clipped lower section and then jumping
        // upward after SwiftUI reports its measured height.
        let window = FocusablePanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: SettingsView.panelWidth,
                height: preferredPanelHeight
            ),
            styleMask: [.borderless],
            backing: .buffered, defer: false
        )
        window.contentView = hostingView
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.level = .floating
        self.window = window

        // Create the status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        updateStatusItemImage()
        updateStatusItemTooltip()

        // Observe the unified network status to update tooltip and icon.
        appState.$networkStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItemTooltip()
                self?.updateStatusItemImage()
            }
            .store(in: &cancellables)

        appState.$isRunning
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItemImage()
            }
            .store(in: &cancellables)

        // Keep the tooltip localized when the user switches language.
        LocalizationManager.shared.$language
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItemTooltip()
            }
            .store(in: &cancellables)

        // Re-render when the system appearance changes so the glyph keeps the
        // same contrast as the native Wi-Fi menu bar icon.
        NSApp.publisher(for: \.effectiveAppearance)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItemImage()
            }
            .store(in: &cancellables)
            
        // Monitor clicks outside to close
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, self.window.isVisible else { return }
            self.closePopover(sender: event)
        }
    }
    
    func applicationDidBecomeActive(_ notification: Notification) {
        appState.refreshLaunchAtLoginStatus()
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState.flushPendingPasswordSaves()
    }

    private func updateStatusItemTooltip() {
        let tooltip = statusTooltip(for: appState.networkStatus)
        statusItem?.button?.toolTip = tooltip
        statusItem?.button?.setAccessibilityLabel(tooltip)
    }

    private func statusTooltip(for status: AppState.NetworkStatus) -> String {
        let i18n = LocalizationManager.shared
        switch status {
        case let .connected(ssid, role):
            let roleText: String
            switch role {
            case .priority:
                roleText = i18n.localizedString("role_priority")
            case .backup:
                roleText = i18n.localizedString("role_backup")
            case .other:
                roleText = i18n.localizedString("role_other")
            case .none:
                roleText = i18n.localizedString("role_offline")
            }
            return "Auto-Wifi: \(ssid) · \(roleText)"
        case .notConnected:
            return "Auto-Wifi: \(i18n.localizedString("not_connected"))"
        case .permissionPending:
            return "Auto-Wifi: \(i18n.localizedString("permission_pending"))"
        case .permissionDenied:
            return "Auto-Wifi: \(i18n.localizedString("location_permission_denied"))"
        case .noInterface:
            return "Auto-Wifi: \(i18n.localizedString("wifi_unavailable"))"
        }
    }

    private func updateStatusItemImage() {
        guard let button = statusItem?.button else { return }
        let type = appState.connectedNetworkType
        let isRunning = appState.isRunning
        let isDark = usesDarkMenuBarContent()
        let scale = button.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let key = StatusImageKey(
            type: type,
            isRunning: isRunning,
            isDark: isDark,
            scale: Int((scale * 100).rounded())
        )

        if let cached = statusImageCache[key] {
            button.image = cached
        } else {
            let image = createStatusImage(
                type: type,
                isRunning: isRunning,
                isDark: isDark,
                scale: scale
            )
            statusImageCache[key] = image
            button.image = image
        }
        button.title = ""
    }

    private func usesDarkMenuBarContent() -> Bool {
        // The menu bar can be dark or light independently of the app's own
        // appearance (macOS 26+ adapts it to the wallpaper). The status item
        // button is the one view whose effectiveAppearance reliably reflects
        // the menu bar itself.
        let appearance = statusItem?.button?.effectiveAppearance ?? NSApp.effectiveAppearance
        switch appearance.name {
        case .darkAqua, .vibrantDark,
             .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark:
            return true
        default:
            return false
        }
    }

    private func createStatusImage(
        type: AppState.ConnectedNetworkType,
        isRunning: Bool,
        isDark: Bool,
        scale: CGFloat
    ) -> NSImage {
        let size = NSSize(width: 24, height: 22)

        // Render into a concrete bitmap instead of a lazily-drawn NSImage.
        // macOS 27's menu bar does not reliably invoke drawingHandler-based
        // status images, which left the icon invisible after the upgrade.
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale),
            pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return NSImage(systemSymbolName: "wifi", accessibilityDescription: "Auto-Wifi") ?? NSImage()
        }
        rep.size = size

        // Pure white on a dark menu bar, pure black on a light one, matching
        // the native Wi-Fi menu bar icon's full-contrast monochrome look.
        let iconColor: NSColor = isDark ? .white : .black
        let letterColor: NSColor = iconColor

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

        if let symbol = NSImage(systemSymbolName: "wifi", accessibilityDescription: "Auto-Wifi")?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .medium)) {
            let colored = symbol.withSymbolConfiguration(.init(paletteColors: [iconColor]))
            colored?.draw(at: NSPoint(x: 0, y: 4), from: .zero, operation: .sourceOver, fraction: 1.0)
        }

        if !isRunning {
            NSColor.systemRed.setFill()
            let dotRect = NSRect(x: 16, y: 2, width: 6, height: 6)
            NSBezierPath(ovalIn: dotRect).fill()
        } else {
            let text: String
            switch type {
            case .priority: text = "P"
            case .backup: text = "B"
            default: text = ""
            }

            if !text.isEmpty {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 10, weight: .bold),
                    .foregroundColor: letterColor
                ]
                NSAttributedString(string: text, attributes: attributes).draw(at: NSPoint(x: 15, y: 0))
            }
        }

        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: size)
        image.addRepresentation(rep)
        image.isTemplate = false // Disable template mode to allow the red dot/P-B colors
        return image
    }

    @MainActor @objc func togglePopover(_ sender: AnyObject?) {
        if window.isVisible {
            closePopover(sender: sender)
        } else {
            showPopover(sender: sender)
        }
    }
    
    func showPopover(sender: AnyObject?) {
        updatePreferredPanelHeightFromContent()

        var frame = window.frame
        frame.size = NSSize(width: SettingsView.panelWidth, height: preferredPanelHeight)
        if let origin = panelOrigin(for: frame.size) {
            frame.origin = origin
        }

        window.setFrame(frame, display: false)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func closePopover(sender: AnyObject?) {
        window.orderOut(sender)
    }

    private func updateWindowHeight(to measuredHeight: CGFloat) {
        // The height preference is emitted while SwiftUI is laying out. Resize
        // after that layout pass to avoid AppKit layout recursion and the brief
        // clipped/lower-half-first presentation seen when opening the panel.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil else { return }

            let targetHeight = max(ceil(measuredHeight), 360)
            self.preferredPanelHeight = targetHeight

            guard abs(self.window.frame.height - targetHeight) > 1 else { return }

            var frame = self.window.frame
            frame.size = NSSize(width: SettingsView.panelWidth, height: targetHeight)

            if self.window.isVisible, let origin = self.panelOrigin(for: frame.size) {
                frame.origin = origin
            }

            self.window.setFrame(frame, display: self.window.isVisible)
        }
    }

    private func updatePreferredPanelHeightFromContent() {
        guard let contentView = window.contentView else { return }
        let fittedHeight = contentView.fittingSize.height
        guard fittedHeight.isFinite, fittedHeight > 0 else { return }
        preferredPanelHeight = max(ceil(fittedHeight), 360)
    }

    private func panelOrigin(for size: NSSize) -> NSPoint? {
        guard let button = statusItem.button else { return nil }

        let buttonRect = button.window?.convertToScreen(button.frame) ?? .zero
        var x = buttonRect.origin.x + (buttonRect.width / 2) - (size.width / 2)
        var y = buttonRect.origin.y - size.height - 2

        // Keep the panel inside the usable screen area, including on displays
        // narrower than the panel or when the status item sits near an edge.
        if let screen = button.window?.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
            y = min(max(y, visible.minY + 8), visible.maxY - size.height - 8)
        }

        return NSPoint(x: x, y: y)
    }
}

// Entry point. Top-level code runs on the main thread; `assumeIsolated`
// satisfies the main-actor annotations on NSApplication and AppDelegate.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
