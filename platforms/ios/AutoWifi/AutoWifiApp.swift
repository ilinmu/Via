import SwiftUI

@main
struct AutoWifiApp: App {
    @StateObject private var controller = WifiController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(controller)
        }
    }
}
