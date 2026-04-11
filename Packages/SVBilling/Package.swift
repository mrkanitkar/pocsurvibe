// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SVBilling",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "SVBilling", targets: ["SVBilling"]),
    ],
    dependencies: [
        .package(path: "../SVCore")
    ],
    targets: [
        .target(
            name: "SVBilling",
            dependencies: [
                .product(name: "SVCore", package: "SVCore"),
            ]
        ),
        .testTarget(
            name: "SVBillingTests",
            dependencies: ["SVBilling"]
        ),
    ]
)
