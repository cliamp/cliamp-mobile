// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CliampCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "CliampCore", targets: ["CliampCore"])
    ],
    targets: [
        .target(
            name: "CliampCore",
            swiftSettings: [.unsafeFlags(["-warnings-as-errors"])]
        ),
        .testTarget(
            name: "CliampCoreTests",
            dependencies: ["CliampCore"],
            swiftSettings: [.unsafeFlags(["-warnings-as-errors"])]
        ),
    ]
)
