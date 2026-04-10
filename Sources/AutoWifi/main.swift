import Cocoa
import SwiftUI
import Combine
import AutoWifiCore

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var window: NSPanel!
    var appState = AppState()
    var wifiManager: WifiManager!
    var cancellables = Set<AnyCancellable>()
    var eventMonitor: Any?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Initialize WifiManager
        wifiManager = WifiManager(appState: appState)
        
        // Create the SwiftUI view
        let contentView = SettingsView(appState: appState, wifiManager: wifiManager)

        // Create the window (NSPanel) instead of NSPopover
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 600),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        window.contentView = NSHostingView(rootView: contentView)
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
            button.image = NSImage(systemSymbolName: "wifi", accessibilityDescription: "Auto-Wifi")
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        // Observe network changes to update tooltip
        appState.$currentNetworkName
            .receive(on: RunLoop.main)
            .sink { [weak self] networkName in
                self?.statusItem.button?.toolTip = "Auto-Wifi: \(networkName)"
            }
            .store(in: &cancellables)
            
        // Observe network type to update status item icon/text

        // Observe network type and running state to update status item icon/text
        appState.$connectedNetworkType
            .combineLatest(appState.$isRunning)
            .receive(on: RunLoop.main)
            .sink { [weak self] (type, isRunning) in
                guard let self = self, let button = self.statusItem.button else { return }
                
                // Create custom image with superscript/dot
                let image = self.createStatusImage(type: type, isRunning: isRunning)
                button.image = image
                button.title = "" // Clear text
            }
            .store(in: &cancellables)
            
        // Monitor clicks outside to close
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, self.window.isVisible else { return }
            self.closePopover(sender: event)
        }
    }
    
    private func createStatusImage(type: AppState.ConnectedNetworkType, isRunning: Bool) -> NSImage {
        let size = NSSize(width: 24, height: 22)
        
        // Use drawingHandler to create a dynamic image that adapts to system appearance
        let image = NSImage(size: size, flipped: false) { rect in
            // 1. Draw Wi-Fi Icon
            // Use labelColor to adapt to Light/Dark mode automatically
            let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
                .applying(.init(paletteColors: [.labelColor]))
            
            if let baseImage = NSImage(systemSymbolName: "wifi", accessibilityDescription: "Auto-Wifi")?.withSymbolConfiguration(config) {
                baseImage.draw(at: NSPoint(x: 0, y: 4), from: .zero, operation: .sourceOver, fraction: 1.0)
            }
            
            // 2. Draw Red Dot or Text
            if !isRunning {
                // Draw Red Dot for stopped state
                // Use systemRed which is visible in both modes
                NSColor.systemRed.setFill()
                let dotRect = NSRect(x: 16, y: 2, width: 6, height: 6)
                let path = NSBezierPath(ovalIn: dotRect)
                path.fill()
            } else {
                // Draw subscript P/B for running state
                let text: String
                switch type {
                case .priority: text = "P"
                case .backup: text = "B"
                default: text = ""
                }
                
                if !text.isEmpty {
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: NSFont.systemFont(ofSize: 10, weight: .regular),
                        .foregroundColor: NSColor.labelColor
                    ]
                    
                    let attributedString = NSAttributedString(string: text, attributes: attributes)
                    // Position at bottom right
                    attributedString.draw(at: NSPoint(x: 15, y: 0))
                }
            }
            return true
        }
        
        image.isTemplate = false // Disable template mode to allow colors
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
        if let button = statusItem.button {
            // Calculate position
            let buttonRect = button.window?.convertToScreen(button.frame) ?? .zero
            let windowHeight = window.frame.height
            let windowWidth = window.frame.width
            
            // Center horizontally below button
            let x = buttonRect.origin.x + (buttonRect.width / 2) - (windowWidth / 2)
            // Position directly below button
            let y = buttonRect.origin.y - windowHeight - 2 // 2px gap
            
            window.setFrameOrigin(NSPoint(x: x, y: y))
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    func closePopover(sender: AnyObject?) {
        window.orderOut(sender)
    }
}

// Entry point
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
