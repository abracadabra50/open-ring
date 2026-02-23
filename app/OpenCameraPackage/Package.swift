// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OpenCameraPackage",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OpenCameraFeature", targets: ["OpenCameraFeature"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "RingClient", targets: ["RingClient"]),
        .library(name: "Storage", targets: ["Storage"]),
        .library(name: "CameraDomain", targets: ["CameraDomain"]),
        .library(name: "CameraProviders", targets: ["CameraProviders"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/nicklockwood/SwiftFormat.git", from: "0.49.0"),
        .package(url: "https://github.com/stasel/WebRTC.git", from: "125.0.0"),
        .package(url: "https://github.com/tylerjonesio/vlckit-spm", branch: "main"),
    ],
    targets: [
        // Design System - colors, typography, components
        .target(
            name: "DesignSystem",
            dependencies: []
        ),

        // Ring API Client
        .target(
            name: "RingClient",
            dependencies: [
                .product(name: "WebRTC", package: "WebRTC")
            ]
        ),

        // Local Storage (SQLite via GRDB)
        .target(
            name: "Storage",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),

        .target(
            name: "CameraDomain",
            dependencies: []
        ),

        .target(
            name: "CameraProviders",
            dependencies: [
                "CameraDomain",
                "Storage",
                "RingClient",
                .product(name: "VLCKitSPM", package: "vlckit-spm"),
            ]
        ),

        // Main Feature module
        .target(
            name: "OpenCameraFeature",
            dependencies: [
                "DesignSystem",
                "RingClient",
                "Storage",
                "CameraDomain",
                "CameraProviders",
            ]
        ),

        .testTarget(
            name: "OpenCameraFeatureTests",
            dependencies: [
                "OpenCameraFeature",
                "CameraDomain",
                "CameraProviders",
            ]
        ),
    ]
)
