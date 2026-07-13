// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ClipCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "ClipCore", targets: ["ClipCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.20"),
    ],
    targets: [
        .target(
            name: "ClipCore",
            dependencies: ["ZIPFoundation"]
        ),
        .testTarget(
            name: "ClipCoreTests",
            dependencies: ["ClipCore", "ZIPFoundation"]
        ),
    ]
)
