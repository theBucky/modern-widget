// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "modern-widget",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "ModernWidget",
            targets: ["ModernWidget"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "ModernWidget"
        ),
    ],
    swiftLanguageModes: [.v6]
)
