import SwiftUI

/// Three text sizes are enough for the whole panel: 20 for a page's primary
/// subject, 13 for body and controls, 11 for supporting text. Hierarchy comes
/// from weight and colour instead of adding more sizes.
enum PanelFont {
    static let title = Font.system(size: 20, weight: .semibold)
    static let body = Font.system(size: 13)
    static let bodyStrong = Font.system(size: 13, weight: .semibold)
    static let caption = Font.system(size: 11)
    static let captionStrong = Font.system(size: 11, weight: .semibold)
}
