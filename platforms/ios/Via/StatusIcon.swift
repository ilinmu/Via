import SwiftUI

/// Mirrors the macOS menu bar icon: a Wi-Fi glyph, a red dot while monitoring
/// is off, and the connected role (P/B) while it runs.
///
/// iOS does not let an app place an icon in the system status bar, so the same
/// state icon is shown in the app's status header instead.
struct StatusIcon: View {
    let role: PolicyRole
    let isRunning: Bool
    var size: CGFloat = 30

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: "wifi")
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(.tint)

            if !isRunning {
                Circle()
                    .fill(Color.red)
                    .frame(width: size * 0.34, height: size * 0.34)
                    .offset(x: size * 0.10, y: size * 0.06)
            } else if let letter = roleLetter {
                Text(letter)
                    .font(.system(size: size * 0.44, weight: .bold))
                    .foregroundStyle(.primary)
                    .offset(x: size * 0.12, y: size * 0.02)
            }
        }
        .frame(width: size * 1.1, height: size)
        .accessibilityHidden(true)
    }

    private var roleLetter: String? {
        switch role {
        case .priority:
            return "P"
        case .backup:
            return "B"
        default:
            return nil
        }
    }
}
