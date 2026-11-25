import AppKit
import SwiftUI

/// One accent colour and a warm neutral scale.
///
/// The accent is a muted bamboo green inspired by the traditional colour 竹青.
/// Warning and danger colours exist only for semantic states; they never carry
/// a primary action. Neutrals are deliberately warm so the panel does not look
/// like a blue-grey admin console.
enum PanelColor {
    static let background = dynamic(light: 0xF7F5F1, dark: 0x1B1A18)
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x232120)
    static let separator = dynamic(light: 0xE4DFD7, dark: 0x3A3733)
    static let textSecondary = dynamic(light: 0x726D65, dark: 0xA8A29A)

    /// Fill for prominent buttons, toggles and selected segments.
    static let accent = dynamic(light: 0x2E6B5C, dark: 0x3C7D6C)
    /// Accent used as text or icon on the panel background.
    static let accentText = dynamic(light: 0x2E6B5C, dark: 0x8CC4B2)

    static let warning = dynamic(light: 0xA15C00, dark: 0xE0A458)
    static let danger = dynamic(light: 0xA33A32, dark: 0xE58C82)

    static func soft(_ color: Color, opacity: Double = 0.10) -> Color {
        color.opacity(opacity)
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return isDark ? NSColor(rgb: dark) : NSColor(rgb: light)
            }
        )
    }
}

extension NSColor {
    fileprivate convenience init(rgb: UInt32) {
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
