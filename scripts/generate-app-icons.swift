#!/usr/bin/env swift
//
// Renders the Via app icon for every platform from one design:
// a blue rounded square with a small Wi-Fi glyph and the word "Via".
//
// Run from the repository root:
//
//     swift scripts/generate-app-icons.swift
//
// Outputs:
//   Via/Assets.xcassets/AppIcon.appiconset/icon_1024x1024.png   (macOS)
//   platforms/ios/Via/Assets.xcassets/AppIcon.appiconset/icon_1024x1024.png
//   platforms/windows/Assets/app.ico
//   platforms/android/app/src/main/res/mipmap-*/ic_launcher_foreground.png
//
import AppKit
import Foundation

enum Background {
    case fullBleed
    case rounded
    case none
}

let topColor = NSColor(srgbRed: 0.18, green: 0.60, blue: 1.00, alpha: 1)
let bottomColor = NSColor(srgbRed: 0.02, green: 0.34, blue: 0.84, alpha: 1)

func render(size: CGFloat, background: Background, contentScale: CGFloat, opaque: Bool) -> NSBitmapImageRep {
    let pixels = Int(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    if opaque {
        NSColor.white.setFill()
        rect.fill()
    }

    if background != .none {
        let gradient = NSGradient(colors: [topColor, bottomColor])!
        let path: NSBezierPath
        switch background {
        case .fullBleed:
            path = NSBezierPath(rect: rect)
        case .rounded:
            let inset = size * 0.055
            path = NSBezierPath(
                roundedRect: rect.insetBy(dx: inset, dy: inset),
                xRadius: size * 0.222,
                yRadius: size * 0.222
            )
        case .none:
            path = NSBezierPath()
        }
        path.addClip()
        gradient.draw(in: rect, angle: -90)
    }

    let box = size * contentScale
    let origin = NSPoint(x: (size - box) / 2, y: (size - box) / 2)

    // Wi-Fi glyph: the largest arc pair plus the dot, drawn from the SF Symbol
    // so it matches the rest of the app.
    let symbolConfig = NSImage.SymbolConfiguration(pointSize: box * 0.5, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "wifi", accessibilityDescription: nil)?
        .withSymbolConfiguration(symbolConfig) {
        let width = box * 0.56
        let height = symbol.size.height * (width / symbol.size.width)
        let wifiRect = NSRect(
            x: (size - width) / 2,
            y: origin.y + box * 0.47,
            width: width,
            height: height
        )
        symbol.draw(in: wifiRect)
    }

    let font = NSFont.systemFont(ofSize: box * 0.23, weight: .semibold)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
        .kern: box * 0.005,
    ]
    let text = "Via" as NSString
    let textSize = text.size(withAttributes: attributes)
    text.draw(
        at: NSPoint(
            x: (size - textSize.width) / 2,
            y: origin.y + box * 0.12
        ),
        withAttributes: attributes
    )

    NSGraphicsContext.restoreGraphicsState()

    guard opaque else { return rep }

    // Re-draw into an RGBX context so the PNG has no alpha channel.
    guard let source = rep.cgImage else { return rep }
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let context = CGContext(
        data: nil,
        width: source.width,
        height: source.height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { return rep }
    context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
    guard let flattened = context.makeImage() else { return rep }
    return NSBitmapImageRep(cgImage: flattened)
}

func png(_ rep: NSBitmapImageRep) -> Data {
    rep.representation(using: .png, properties: [:])!
}

func write(_ data: Data, to relativePath: String) {
    let url = URL(fileURLWithPath: relativePath)
    try! FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try! data.write(to: url)
    print("wrote \(relativePath)")
}

func renderIcon(size: CGFloat, background: Background, contentScale: CGFloat, opaque: Bool = false) -> Data {
    png(render(size: size, background: background, contentScale: contentScale, opaque: opaque))
}

// ICO container with PNG-compressed entries.
func writeICO(_ images: [(Int, Data)], to path: String) {
    var data = Data([0, 0, 1, 0])
    var count = UInt16(images.count).littleEndian
    data.append(contentsOf: withUnsafeBytes(of: &count) { Data($0) })

    var offset = 6 + 16 * images.count
    for (size, image) in images {
        data.append(UInt8(size == 256 ? 0 : size))
        data.append(UInt8(size == 256 ? 0 : size))
        data.append(contentsOf: [0, 0])
        var planes = UInt16(1).littleEndian
        var bitCount = UInt16(32).littleEndian
        data.append(contentsOf: withUnsafeBytes(of: &planes) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: &bitCount) { Data($0) })
        var length = UInt32(image.count).littleEndian
        var imageOffset = UInt32(offset).littleEndian
        data.append(contentsOf: withUnsafeBytes(of: &length) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: &imageOffset) { Data($0) })
        offset += image.count
    }
    for (_, image) in images {
        data.append(image)
    }

    write(data, to: path)
}

// macOS: the .icns is generated from this PNG by scripts/package-app.sh.
write(
    renderIcon(size: 1024, background: .rounded, contentScale: 0.78),
    to: "Via/Assets.xcassets/AppIcon.appiconset/icon_1024x1024.png"
)

// iOS: the system applies the corner mask, so the artwork is full-bleed and
// has no alpha channel, since transparent icons are rejected on submission.
write(
    renderIcon(size: 1024, background: .fullBleed, contentScale: 0.78, opaque: true),
    to: "platforms/ios/Via/Assets.xcassets/AppIcon.appiconset/icon_1024x1024.png"
)

// Windows: executable and tray icon.
let icoSizes = [16, 24, 32, 48, 64, 128, 256]
writeICO(
    icoSizes.map { ($0, renderIcon(size: CGFloat($0), background: .rounded, contentScale: 0.78)) },
    to: "platforms/windows/Assets/app.ico"
)

// Android: adaptive-icon foreground. Only the inner 72 of 108 dp are
// guaranteed visible, so the artwork stays inside that circle.
let androidDensities: [(String, Int)] = [
    ("mdpi", 108),
    ("hdpi", 162),
    ("xhdpi", 216),
    ("xxhdpi", 324),
    ("xxxhdpi", 432),
]
for (density, size) in androidDensities {
    write(
        renderIcon(size: CGFloat(size), background: .none, contentScale: 0.62),
        to: "platforms/android/app/src/main/res/mipmap-\(density)/ic_launcher_foreground.png"
    )
}
