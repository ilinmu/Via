import AppKit

enum SystemLinks {
    static func openLocationSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
