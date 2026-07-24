// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SpectraAuthSDK",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
    ],
    products: [
        .library(
            name: "SpectraAuthSDK",
            targets: ["SpectraAuthSDK"]
        ),
    ],
    targets: [
        .target(
            name: "SpectraAuthSDK"
        ),
        .testTarget(
            name: "SpectraAuthSDKTests",
            dependencies: ["SpectraAuthSDK"]
        ),
    ]
)

