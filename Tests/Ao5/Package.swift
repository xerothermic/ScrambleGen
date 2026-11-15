// swift-tools-version:5.9
// Off-device unit tests for the Ao5 calculation. The source file is symlinked
// from the watch app, so the tests exercise the shipping code.
// Run on a Mac:  cd Tests/Ao5 && swift test
import PackageDescription

let package = Package(
    name: "Ao5",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "Ao5Core"),
        .testTarget(name: "Ao5CoreTests", dependencies: ["Ao5Core"]),
    ]
)
