// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "store-previews",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "store-previews", targets: ["store-previews"]),
        .library(name: "StorePreviewKit", targets: ["StorePreviewKit"]),
    ],
    targets: [
        .target(name: "StorePreviewKit"),
        .executableTarget(name: "store-previews", dependencies: ["StorePreviewKit"]),
        // The README tests run the built store-previews binary.
        .testTarget(name: "StorePreviewKitTests", dependencies: ["StorePreviewKit", "store-previews"]),
    ]
)
