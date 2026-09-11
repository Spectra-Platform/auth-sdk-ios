// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "spectra-auth-sdk-ios",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
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
