import XCTest
@testable import Scramble333Core

/// Deterministic generator so failures reproduce.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Independent verifier: maps a cubie-level cube to the app's 54-facelet
/// layout (same geometry as scripts/verify_cube.py), so scrambles can be
/// replayed on the shipping `CubeState` engine and compared to the target.
private enum Facelets {
    struct Key: Hashable { let pos: [Int]; let normal: [Int] }

    static let normals: [Character: [Int]] = [
        "U": [0, 1, 0], "D": [0, -1, 0], "R": [1, 0, 0],
        "L": [-1, 0, 0], "F": [0, 0, 1], "B": [0, 0, -1],
    ]

    static let corners = ["URF", "UFL", "ULB", "UBR", "DFR", "DLF", "DBL", "DRB"]
    static let edges = ["UR", "UF", "UL", "UB", "DR", "DF", "DL", "DB", "FR", "FL", "BL", "BR"]

    static func posNormal(_ face: Character, _ r: Int, _ c: Int) -> Key {
        switch face {
        case "U": return Key(pos: [c - 1, 1, r - 1], normal: [0, 1, 0])
        case "D": return Key(pos: [c - 1, -1, 1 - r], normal: [0, -1, 0])
        case "F": return Key(pos: [c - 1, 1 - r, 1], normal: [0, 0, 1])
        case "B": return Key(pos: [1 - c, 1 - r, -1], normal: [0, 0, -1])
        case "L": return Key(pos: [-1, 1 - r, c - 1], normal: [-1, 0, 0])
        default:  return Key(pos: [1, 1 - r, 1 - c], normal: [1, 0, 0])   // R
        }
    }

    /// Facelet index for each (position, normal); face order U D F B L R as in CubeState.
    static let lookup: [Key: Int] = {
        var d: [Key: Int] = [:]
        for (fi, f) in "UDFBLR".enumerated() {
            for r in 0..<3 { for c in 0..<3 { d[posNormal(f, r, c)] = fi * 9 + r * 3 + c } }
        }
        return d
    }()

    static func slot(_ name: String) -> [Int] {
        var pos = [0, 0, 0]
        for ch in name { for a in 0..<3 { pos[a] += normals[ch]![a] } }
        return name.map { lookup[Key(pos: pos, normal: normals[$0]!)]! }
    }

    static func from(_ cube: Cubie) -> [Int] {
        var out = [Int](repeating: 0, count: 54)
        for f in 0..<6 { out[f * 9 + 4] = f }
        for s in 0..<8 {
            let sf = slot(corners[s]), hf = slot(corners[cube.cp[s]])
            for j in 0..<3 { out[sf[(j + cube.co[s]) % 3]] = hf[j] / 9 }
        }
        for s in 0..<12 {
            let sf = slot(edges[s]), hf = slot(edges[cube.ep[s]])
            for j in 0..<2 { out[sf[(j + cube.eo[s]) % 2]] = hf[j] / 9 }
        }
        return out
    }
}

final class RandomState333Tests: XCTestCase {
    func testCubieMovesMatchFaceletEngine() {
        for (i, name) in RandomState333.moveNames.enumerated() {
            var engine = CubeState()
            engine.apply(move: name)
            let cubie = Cubie.solved.applying(RandomState333.moves[i])
            XCTAssertEqual(engine.facelets, Facelets.from(cubie), "move \(name)")
        }
    }

    func testMoveIdentities() {
        func run(_ seq: String) -> Cubie {
            seq.split(separator: " ").reduce(Cubie.solved) { c, m in
                c.applying(RandomState333.moves[RandomState333.moveNames.firstIndex(of: String(m))!])
            }
        }
        XCTAssertEqual(run(String(repeating: "R U R' U' ", count: 6)), .solved)
        XCTAssertNotEqual(run("R U R' U'"), .solved)
        XCTAssertTrue(run("R U F2 L' D B2").isSolvable)
    }

    func testSolvedCubeNeedsNoMoves() {
        XCTAssertEqual(RandomState333.scramble(for: .solved), [])
    }

    func testKnownScrambleRoundTrips() {
        let moves = "R U R' U' F2 D L' B2 U2 R2".split(separator: " ").map(String.init)
        var cube = Cubie.solved
        for m in moves {
            cube = cube.applying(RandomState333.moves[RandomState333.moveNames.firstIndex(of: m)!])
        }
        let scramble = RandomState333.scramble(for: cube)
        XCTAssertLessThanOrEqual(scramble.count, 21)
        XCTAssertEqual(CubeState.scrambled(by: scramble).facelets, Facelets.from(cube))
    }

    func testRandomStateScramblesReachTheTargetState() {
        var rng = SplitMix64(state: 333)
        var lengths: [Int] = []
        for trial in 0..<25 {
            let target = RandomState333.randomCube(using: &rng)
            XCTAssertTrue(target.isSolvable, "trial \(trial)")
            let scramble = RandomState333.scramble(for: target)

            // Shipping 54-facelet engine.
            XCTAssertEqual(CubeState.scrambled(by: scramble).facelets, Facelets.from(target),
                           "trial \(trial): \(scramble.joined(separator: " "))")
            // Cubie model.
            var cube = Cubie.solved
            for m in scramble {
                cube = cube.applying(RandomState333.moves[RandomState333.moveNames.firstIndex(of: m)!])
            }
            XCTAssertEqual(cube, target, "trial \(trial)")
            XCTAssertTrue(cube.isSolvable)

            XCTAssertLessThanOrEqual(scramble.count, 25, "trial \(trial)")
            for (a, b) in zip(scramble, scramble.dropFirst()) {
                XCTAssertNotEqual(a.first, b.first, "same face twice: \(scramble)")
            }
            lengths.append(scramble.count)
        }
        let mean = Double(lengths.reduce(0, +)) / Double(lengths.count)
        XCTAssertGreaterThan(mean, 17)
        XCTAssertLessThan(mean, 22.5)
    }

    func testRandomCubeInvariants() {
        var rng = SplitMix64(state: 7)
        for _ in 0..<2000 {
            XCTAssertTrue(RandomState333.randomCube(using: &rng).isSolvable)
        }
    }

    func testPrepareIsIdempotent() {
        RandomState333.prepare()
        XCTAssertTrue(RandomState333.isReady)
        XCTAssertFalse(RandomState333.randomScramble().isEmpty)
    }
}
