// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "modern-widget",
    platforms: [
        .macOS("26.0"),
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
