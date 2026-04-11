// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SVAI",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "SVAI", targets: ["SVAI"]),
    ],
    dependencies: [
        .package(path: "../SVCore")
    ],
    targets: [
        .target(
            name: "SVAI",
            dependencies: [
                .product(name: "SVCore", package: "SVCore"),
            ]
        ),
        .testTarget(
            name: "SVAITests",
            dependencies: ["SVAI"]
        ),
    ]
)
