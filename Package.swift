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
        .executable(name: "PolicySmoke", targets: ["PolicySmoke"]),
        .library(name: "AutoWifiCore", targets: ["AutoWifiCore"])
    ],
    targets: [
        .executableTarget(
            name: "AutoWifi",
            dependencies: ["AutoWifiCore"]
        ),
        .systemLibrary(
            name: "CAutoWifiCore",
            path: "core/include"
        ),
        .executableTarget(
            name: "PolicySmoke",
            dependencies: ["AutoWifiCore"],
            path: "Tools/PolicySmoke"
        ),
        .target(
            name: "AutoWifiCore",
            dependencies: ["CAutoWifiCore"],
            linkerSettings: [
                .linkedFramework("SystemConfiguration"),
                .linkedFramework("Security")
            ]
        ),
        .testTarget(
            name: "AutoWifiTests",
            dependencies: ["AutoWifiCore"]
        )
    ]
)
