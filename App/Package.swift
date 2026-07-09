// swift-tools-version: 6.0
import PackageDescription

// PeptideKit — the pure, platform-agnostic domain core of the PinWise app.
// All dosing math, models, and protocol logic live here so they can be unit-tested
// on macOS/CI without an iOS simulator. The SwiftUI app links this package.
let package = Package(
    name: "PeptideKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v13),
        .watchOS(.v10),
    ],
    products: [
        .library(name: "PeptideKit", targets: ["PeptideKit"]),
    ],
    targets: [
        // Swift 6 language mode (from swift-tools-version: 6.0) already enables strict
        // concurrency, so no explicit upcoming-feature flag is needed — and the Swift 6.0
        // toolchain errors on the redundant flag.
        .target(name: "PeptideKit"),
        // Runnable verification harness (`swift run pk-verify`). Exists because the
        // Command Line Tools toolchain ships no XCTest/swift-testing; in full Xcode,
        // run the PeptideKitTests suite instead — it covers the same cases.
        .executableTarget(
            name: "pk-verify",
            dependencies: ["PeptideKit"]
        ),
        .testTarget(
            name: "PeptideKitTests",
            dependencies: ["PeptideKit"]
        ),
    ]
)
