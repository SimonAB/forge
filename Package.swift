// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Forge",
    platforms: [.macOS(.v14), .iOS(.v17)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
    ],
    targets: [
        .target(
            name: "ForgeCore",
            dependencies: ["Yams"],
            path: "Sources/ForgeCore"
        ),
        .executableTarget(
            name: "forge",
            dependencies: [
                "ForgeCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/forge"
        ),
        .target(
            name: "ForgeUI",
            dependencies: ["ForgeCore"],
            path: "Sources/ForgeUI"
        ),
        .executableTarget(
            name: "forge-menubar",
            dependencies: ["ForgeCore", "ForgeUI"],
            path: "Sources/forge-menubar",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("SwiftUI"),
            ]
        ),
        .executableTarget(
            name: "forge-board",
            dependencies: ["ForgeCore", "ForgeUI"],
            path: "Sources/forge-board",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
            ]
        ),
        .testTarget(
            name: "ForgeCoreTests",
            dependencies: ["ForgeCore"],
            path: "Tests/ForgeCoreTests"
        ),
    ]
)
