// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftWaveform",
    platforms: [.iOS(.v16)],
    products: [
        .library(
            name: "SwiftWaveform",
            targets: ["SwiftWaveform"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/ailu2533/FFmpegKitSPM.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "SwiftWaveform",
            dependencies: [
                .product(name: "FFmpegKitSPM", package: "FFmpegKitSPM"),
            ],
            path: "Sources/SwiftWaveform"
        ),
    ]
)
