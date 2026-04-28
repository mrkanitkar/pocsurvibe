// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SVAudio",
    defaultLocalization: "en",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "SVAudio", targets: ["SVAudio"]),
    ],
    dependencies: [
        .package(path: "../SVCore"),
        .package(url: "https://github.com/AudioKit/AudioKit", from: "5.6.0"),
        .package(url: "https://github.com/AudioKit/SoundpipeAudioKit", from: "5.6.0"),
        .package(url: "https://github.com/AudioKit/Microtonality", branch: "main"),
        // Verovio uses "version-X.Y.Z" git tags (not bare semver), so SPM's `from:` constraint
        // cannot resolve them. Pin to the post-6.1.1 HEAD commit which also carries the SPM fix
        // for the missing include/tuning-library header search path (omitted from the 6.1.x tags).
        .package(url: "https://github.com/rism-digital/verovio", revision: "b98911d9ef5f1c5db8e807974a8ae8cdbd478d6d"),
        .package(url: "https://github.com/weichsel/ZIPFoundation", from: "0.9.20"),
    ],
    targets: [
        // ObjC helper that catches NSExceptions from AVAudioUnitSampler
        // and converts them to NSError for Swift interop.
        .target(
            name: "ObjCExceptionCatcher",
            path: "Sources/ObjCExceptionCatcher",
            publicHeadersPath: "include"
        ),
        .target(
            name: "SVAudio",
            dependencies: [
                .product(name: "SVCore", package: "SVCore"),
                .product(name: "AudioKit", package: "AudioKit"),
                .product(name: "SoundpipeAudioKit", package: "SoundpipeAudioKit"),
                .product(name: "Microtonality", package: "Microtonality"),
                .product(name: "VerovioToolkit", package: "verovio"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
                "ObjCExceptionCatcher",
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "SVAudioTests",
            dependencies: [
                "SVAudio",
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ]
        ),
    ]
)
