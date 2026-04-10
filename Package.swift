// swift-tools-version: 5.10.0

import PackageDescription

let package = Package(
    name: "EchoDraft",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "EchoDraftCore", targets: ["EchoDraftCore"]),
        .executable(name: "EchoDraft", targets: ["EchoDraft"]),
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation", from: "0.9.0"),
    ],
    targets: [
        .target(
            name: "EchoDraftCore",
            dependencies: [
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
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
