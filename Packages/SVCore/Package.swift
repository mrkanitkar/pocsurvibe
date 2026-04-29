// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SVCore",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "SVCore", targets: ["SVCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/PostHog/posthog-ios", from: "3.0.0")
    ],
    targets: [
        .target(
            name: "SVCore",
            dependencies: [
                .product(name: "PostHog", package: "posthog-ios"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "SVCoreTests",
            dependencies: ["SVCore"],
            resources: [.copy("Resources/Play")]
        ),
    ]
)
