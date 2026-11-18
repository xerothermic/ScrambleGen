// swift-tools-version:5.9
// Off-device unit tests for the random-state Square-1 scrambler. The source is
// symlinked from the watch app, so the tests exercise the shipping code.
// Run on a Mac:  cd Tests/Square1RandomState && swift test -c release
// (the first test builds ~8 MB of tables; a debug build takes a while).
import PackageDescription

let package = Package(
    name: "Square1RandomState",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "Square1RandomStateCore"),
        .testTarget(name: "Square1RandomStateCoreTests", dependencies: ["Square1RandomStateCore"]),
    ]
)
