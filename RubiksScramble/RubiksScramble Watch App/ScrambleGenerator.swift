import Foundation

/// Generates random 3x3 Rubik's cube scrambles in standard notation.
///
/// Rules:
///   1. Default length is 20 moves (configurable).
///   2. Standard outer-face notation only — no slice (M/E/S) or wide moves.
///   3. The same face never turns twice in a row.
enum ScrambleGenerator {
    static let defaultLength = 20

    /// Each face turn carries one modifier: "" (90° CW), "'" (90° CCW), or "2" (180°).
    private static let modifiers = ["", "'", "2"]

    static func generate(length: Int = defaultLength) -> [String] {
        var moves: [String] = []
        moves.reserveCapacity(max(0, length))
        var lastFace: CubeFace?

        for _ in 0..<max(0, length) {
            var face = CubeFace.allCases.randomElement()!
            while face == lastFace {
                face = CubeFace.allCases.randomElement()!
            }
            lastFace = face
            moves.append(face.notation + modifiers.randomElement()!)
        }
        return moves
    }

    static func generateString(length: Int = defaultLength) -> String {
        generate(length: length).joined(separator: " ")
    }
}

/// The puzzles the app can scramble.
enum Puzzle: String, CaseIterable, Identifiable {
    case cube3x3
    case square1
    case clock

    var id: Self { self }

    var name: String {
        switch self {
        case .cube3x3: "3×3"
        case .square1: "Square-1"
        case .clock: "Clock"
        }
    }

    var defaultLength: Int {
        switch self {
        case .cube3x3: ScrambleGenerator.defaultLength
        case .square1: Square1Scrambler.defaultSlices
        case .clock: 1
        }
    }

    var lengthRange: ClosedRange<Int> {
        switch self {
        case .cube3x3: 1...50
        case .square1: 1...30
        case .clock: 1...1
        }
    }

    /// 3×3 length counts face turns; Square-1 length counts slices.
    var lengthLabel: String {
        switch self {
        case .cube3x3: "Length"
        case .square1: "Slices"
        case .clock: ""
        }
    }

    /// Clock scrambles have a fixed shape, so the length pill is hidden.
    var hasLength: Bool { self != .clock }

    func generate(length: Int) -> [String] {
        switch self {
        case .cube3x3: ScrambleGenerator.generate(length: length)
        case .square1: Square1Scrambler.generate(slices: length)
        case .clock: ClockScrambler.generate()
        }
    }
}
