// swift-tools-version:5.9
// Test-only package: lets the pure logic (no SwiftUI) run `swift test` on Linux
// or macOS. The app itself still builds through the Xcode project.
import PackageDescription

let package = Package(
    name: "ScrambleGenLogic",
    targets: [
        .target(
            name: "SolveAverages",
            path: "RubiksScramble/RubiksScramble Watch App",
            exclude: ["Assets.xcassets", "PrivacyInfo.xcprivacy"] + [
                "ContentView.swift", "CubeMapView.swift", "CubeState.swift",
                "PuzzleArtDrawing.swift", "PuzzleStyle.swift", "RubiksScrambleApp.swift",
                "ScrambleGenerator.swift", "Square1MapView.swift", "Square1Scrambler.swift",
                "TimerView.swift", "SolveEntryView.swift",
            ],
            sources: ["SolveAverages.swift"]
        ),
        .testTarget(
            name: "SolveAveragesTests",
            dependencies: ["SolveAverages"],
            path: "Tests/SolveAveragesTests"
        ),
    ]
)
