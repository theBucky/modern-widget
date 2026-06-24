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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "ModernWidget",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "ModernWidgetTests",
            dependencies: ["ModernWidget"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
