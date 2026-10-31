// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Intunix",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "Intunix", targets: ["Intunix"]),
    ],
    targets: [
        // Pure logic shared with every platform (ported from @intunix/core). Builds and tests on Linux too.
        .target(name: "IntunixCore"),
        // SwiftUI forms and the public API. UI code compiles on iOS only.
        .target(name: "Intunix", dependencies: ["IntunixCore"]),
        .testTarget(name: "IntunixCoreTests", dependencies: ["IntunixCore"]),
        .testTarget(name: "IntunixUITests", dependencies: ["Intunix", "IntunixCore"]),
    ]
)
