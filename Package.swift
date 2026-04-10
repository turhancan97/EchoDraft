// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "EchoDraft",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "EchoDraftCore", targets: ["EchoDraftCore"]),
        .executable(name: "EchoDraft", targets: ["EchoDraft"]),
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation", from: "0.9.0"),
        .package(url: "https://github.com/Blaizzy/mlx-audio-swift", branch: "main"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", from: "2.30.3"),
    ],
    targets: [
        .target(
            name: "EchoDraftCore",
            dependencies: [
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
                .product(name: "MLXAudioCore", package: "mlx-audio-swift"),
                .product(name: "MLXAudioSTT", package: "mlx-audio-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
            ],
            path: "Sources/EchoDraftCore"
        ),
        .executableTarget(
            name: "EchoDraft",
            dependencies: ["EchoDraftCore"],
            path: "Sources/EchoDraftApp"
        ),
    ]
)
