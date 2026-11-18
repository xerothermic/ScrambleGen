import XCTest
@testable import Square1RandomStateCore

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

/// Replays tokens the way the app's Square1State does (Square1MapView.swift,
/// which needs SwiftUI/WatchKit and so cannot be linked here), on the cell
/// model, checking that no slice cuts through a corner.
private func replay(_ tokens: [String], from start: [Int]) -> [Int]? {
    var s = start
    for token in tokens {
        let turn = token
            .trimmingCharacters(in: CharacterSet(charactersIn: "()/ "))
            .split(separator: ",")
            .compactMap { Int($0) }
        if turn.count == 2 { s = Square1RandomState.turned(s, turn[0], turn[1]) }
        if token.hasSuffix("/") {
            if !Square1RandomState.isLegal(s) { return nil }
            s = Square1RandomState.sliced(s)
        }
    }
    return s
}

final class Square1RandomStateTests: XCTestCase {
    func testTableSizes() {
        let t = Square1RandomState.prepare()
        XCTAssertEqual(t.shapeCount, 3678)
        XCTAssertFalse(t.shapeDist.contains(255))
        XCTAssertEqual(t.shapeDist.max(), 8)
        XCTAssertEqual(t.cornerDist.max(), 6)
        XCTAssertEqual(t.edgeDist.max(), 6)
        XCTAssertEqual(t.cornerDist.filter { $0 == 0 }.count, 16)
        var deepest = 0
        var zeros = 0
        for i in 0..<(Square1RandomState.permCount * Square1RandomState.setCount) {
            let d = Square1RandomState.nibble(t.cornerSetDist, i)
            if d > deepest { deepest = d }
            if d == 0 { zeros += 1 }
        }
        XCTAssertEqual(deepest, 7)
        XCTAssertEqual(zeros, 16)
    }

    func testPermRankRoundTrips() {
        for n in [0, 1, 5039, 5040, 12345, 40319] {
            XCTAssertEqual(Square1RandomState.permRank(Square1RandomState.permUnrank(n)), n)
        }
        XCTAssertEqual(Square1RandomState.permUnrank(0), [0, 1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(Square1RandomState.permUnrank(40319), [7, 6, 5, 4, 3, 2, 1, 0])
    }

    func testRandomStateScramblesReachTheTargetState() {
        let t = Square1RandomState.prepare()
        // The app's solved state: the internal one with the bottom turned by +1.
        let start = Square1RandomState.turned(Square1RandomState.solvedCells(), 0, 1)
        XCTAssertTrue(Square1RandomState.isLegal(start))
        var rng = SplitMix64(state: 1)
        var slices: [Int] = []
        for trial in 0..<200 {
            let target = Square1RandomState.randomState(t, using: &rng)
            XCTAssertTrue(Square1RandomState.isLegal(target.cells), "trial \(trial)")
            guard let tokens = Square1RandomState.scramble(t, state: target.cells, shape: target.shape,
                                                           using: &rng) else {
                XCTFail("trial \(trial): no scramble")
                continue
            }
            XCTAssertEqual(replay(tokens, from: start), target.cells,
                           "trial \(trial): \(tokens.joined(separator: " "))")
            for (n, token) in tokens.enumerated() {
                XCTAssertLessThanOrEqual(token.count, 8, token)
                if token == "/" { XCTAssertEqual(n, 0, "bare / after the first token") }
                if !token.hasSuffix("/") { XCTAssertEqual(n, tokens.count - 1, token) }
                XCTAssertNotEqual(token, "(0,0)/")
            }
            slices.append(tokens.filter { $0.hasSuffix("/") }.count)
        }
        let mean = Double(slices.reduce(0, +)) / Double(slices.count)
        XCTAssertGreaterThan(mean, 11.5)
        XCTAssertLessThan(mean, 14)
        XCTAssertLessThanOrEqual(slices.max() ?? 0, 18)
    }
}
