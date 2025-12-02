// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AutoWifi",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "AutoWifi", targets: ["AutoWifi"]),
        .library(name: "AutoWifiCore", targets: ["AutoWifiCore"])
    ],
    targets: [
        .executableTarget(
            name: "AutoWifi",
            dependencies: ["AutoWifiCore"]
        ),
        .target(
            name: "AutoWifiCore",
            dependencies: []
        ),
        .testTarget(
            name: "AutoWifiTests",
            dependencies: ["AutoWifiCore"]
        )
    ]
)
