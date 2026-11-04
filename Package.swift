// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Via",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Via", targets: ["Via"]),
        .executable(name: "PolicySmoke", targets: ["PolicySmoke"]),
        .library(name: "ViaCore", targets: ["ViaCore"])
    ],
    targets: [
        .executableTarget(
            name: "Via",
            dependencies: ["ViaCore"]
        ),
        .systemLibrary(
            name: "CViaCore",
            path: "core/include"
        ),
        .executableTarget(
            name: "PolicySmoke",
            dependencies: ["ViaCore"],
            path: "Tools/PolicySmoke"
        ),
        .target(
            name: "ViaCore",
            dependencies: ["CViaCore"],
            linkerSettings: [
                .linkedFramework("SystemConfiguration"),
                .linkedFramework("Security")
            ]
        ),
        .testTarget(
            name: "ViaTests",
            dependencies: ["ViaCore"]
        )
    ]
)
