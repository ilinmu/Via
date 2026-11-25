import SwiftUI
import UIKit

/// One accent (a muted bamboo green) and warm neutrals, shared with the
/// macOS and Android shells.
enum ViaColors {
    static let accent = adaptive(light: 0x2E6B5C, dark: 0x3C7D6C)
    static let accentText = adaptive(light: 0x2E6B5C, dark: 0x8CC4B2)
    static let background = adaptive(light: 0xF7F5F1, dark: 0x1B1A18)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x232120)
    static let separator = adaptive(light: 0xE4DFD7, dark: 0x3A3733)
    static let secondaryText = adaptive(light: 0x726D65, dark: 0xA8A29A)
    static let warning = adaptive(light: 0xA15C00, dark: 0xE0A458)
    static let danger = adaptive(light: 0xA33A32, dark: 0xE58C82)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(
            uiColor: UIColor { traits in
                UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
            }
        )
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
