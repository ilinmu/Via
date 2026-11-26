// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Nativewifi",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "Nativewifi", type: .dynamic, targets: ["Nativewifi"])],
    dependencies: [],
    targets: [
        .target(name: "Nativewifi"),
    ],
    swiftLanguageModes: [.v5]
)
