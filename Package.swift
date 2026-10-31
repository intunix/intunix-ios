// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Intunix",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "Intunix", targets: ["Intunix"]),
    ],
    targets: [
        // One module: logic ported from @intunix/core (builds and tests on Linux too) plus the
        // SwiftUI forms and public API (iOS only). One module keeps CocoaPods' spm_dependency
        // (React Native) from linking the logic twice.
        .target(name: "Intunix"),
        .testTarget(name: "IntunixCoreTests", dependencies: ["Intunix"]),
        .testTarget(name: "IntunixUITests", dependencies: ["Intunix"]),
    ]
)
