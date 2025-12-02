import Cocoa
import SwiftUI
import Combine
import AutoWifiCore

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var appState = AppState()
    var wifiManager: WifiManager!
    var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Initialize WifiManager
        wifiManager = WifiManager(appState: appState)
        
        // Create the SwiftUI view
        let contentView = SettingsView(appState: appState, wifiManager: wifiManager)

        // Create the popover
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 360, height: 550)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: contentView)
        self.popover = popover

        // Create the status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "wifi", accessibilityDescription: "Auto-Wifi")
            button.action = #selector(togglePopover(_:))
        }
        
        // Observe network changes to update tooltip
        appState.$currentNetworkName
            .receive(on: RunLoop.main)
            .sink { [weak self] networkName in
                self?.statusItem.button?.toolTip = "Auto-Wifi: \(networkName)"
            }
            .store(in: &cancellables)
        
        // Auto-start if configured? (Optional, currently manual start)
    }

    @MainActor @objc func togglePopover(_ sender: AnyObject?) {
        if let button = self.statusItem.button {
            if self.popover.isShown {
                self.popover.performClose(sender)
            } else {
                self.popover.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
                // Bring app to front so popover is active
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}

// Entry point
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
