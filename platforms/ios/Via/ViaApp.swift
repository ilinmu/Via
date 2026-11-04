import SwiftUI

@main
struct ViaApp: App {
    @StateObject private var controller = WifiController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(controller)
        }
    }
}
