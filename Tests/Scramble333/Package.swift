// swift-tools-version:5.9
// Off-device unit tests for the random-state 3x3 scrambler. The sources are
// symlinked from the watch app, so the tests exercise the shipping code.
// Run on a Mac:  cd Tests/Scramble333 && swift test
// (the first test builds ~6 MB of tables; a debug build takes a while, or use
// `swift test -c release`).
import PackageDescription

let package = Package(
    name: "Scramble333",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "Scramble333Core"),
        .testTarget(name: "Scramble333CoreTests", dependencies: ["Scramble333Core"]),
    ]
)
