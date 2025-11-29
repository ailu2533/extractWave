// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftWaveform",
    platforms: [.iOS(.v17)],
    products: [
        .library(
            name: "SwiftWaveform",
            targets: ["SwiftWaveform"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/ailu2533/FFmpegKitSPM.git", branch: "main"),
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.2.0"),
    ],
    targets: [
        .target(
            name: "SwiftWaveform",
            dependencies: [
                .product(name: "FFmpegKitSPM", package: "FFmpegKitSPM"),
                .product(name: "Atomics", package: "swift-atomics"),
            ],
            path: "Sources/SwiftWaveform"
        ),
        .testTarget(
            name: "SwiftWaveformTests",
            dependencies: [
                "SwiftWaveform",
                .product(name: "Atomics", package: "swift-atomics"),
            ],
            resources: [.process("Resources")]
        ),
    ]
)
