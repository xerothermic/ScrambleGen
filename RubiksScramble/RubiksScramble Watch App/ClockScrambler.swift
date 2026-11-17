import Foundation

/// Random-move Rubik's Clock scrambles in WCA notation (Regulations
/// 12g): `UR# DR# DL# UL# U# R# D# L# ALL# y2 U# R# D# L# ALL#`, ending at the
/// last `ALL` move (no trailing pin list). Each `#` is a dial turn written as its
/// magnitude and sign, from `5-` through `6+` (clock positions -5...6; zero
/// is always written `0+`), matching TNoodle's output.
enum ClockScrambler {
    static let frontMoves = ["UR", "DR", "DL", "UL", "U", "R", "D", "L", "ALL"]
    static let backMoves = ["U", "R", "D", "L", "ALL"]
    static let turnRange = -5...6

    /// Dial turn as a token suffix: `3+`, `4-`, `0+`.
    static func format(_ turn: Int) -> String {
        "\(abs(turn))" + (turn < 0 ? "-" : "+")
    }

    /// 9 front moves, `y2`, then 5 back moves (15 tokens).
    static func generate() -> [String] {
        var tokens = frontMoves.map { $0 + format(Int.random(in: turnRange)) }
        tokens.append("y2")
        tokens += backMoves.map { $0 + format(Int.random(in: turnRange)) }
        return tokens
    }
}

/// State of the nine clocks after a scramble. `dial[r*3+c]` is the hour position
/// (0...11, 0 = 12 o'clock) of the clock at row r, column c as seen from the
/// FRONT; the back of the same clock shows the mirrored column with the
/// mirrored hand (hour -h).
///
/// A move names the pins that are up. Each up pin couples the 2x2 block of
/// clocks around it, and the dial turn moves every clock in the union of those
/// blocks: UR/DR/DL/UL = one block, U/R/D/L = the two blocks on that side
/// (6 clocks), ALL = all nine. Back moves use the back view's own pin names,
/// so their columns are mirrored and a clockwise turn there is
/// counter-clockwise as seen from the front. Mirrored by scripts/verify_clock.py.
struct ClockState: Equatable {
    private(set) var dial = [Int](repeating: 0, count: 9)

    /// Rows/columns (inclusive 2x2 block origin) each pin couples: (row, col).
    private static let pinBlock: [String: [(Int, Int)]] = [
        "UL": [(0, 0)], "UR": [(0, 1)], "DL": [(1, 0)], "DR": [(1, 1)],
        "U": [(0, 0), (0, 1)], "D": [(1, 0), (1, 1)],
        "L": [(0, 0), (1, 0)], "R": [(0, 1), (1, 1)],
        "ALL": [(0, 0), (0, 1), (1, 0), (1, 1)],
    ]

    static func scrambled(by tokens: [String]) -> ClockState {
        var state = ClockState()
        var back = false
        for token in tokens {
            if token == "y2" { back = true; continue }
            let name = String(token.prefix { $0.isLetter })
            let rest = token.dropFirst(name.count)
            guard let blocks = pinBlock[name], let sign = rest.last,
                  let n = Int(rest.dropLast()) else { continue }
            state.turn(blocks: blocks, by: sign == "-" ? -n : n, back: back)
        }
        return state
    }

    private mutating func turn(blocks: [(Int, Int)], by n: Int, back: Bool) {
        var hit = Set<Int>()
        for (r0, c0) in blocks {
            for r in r0...(r0 + 1) {
                for c in c0...(c0 + 1) {
                    hit.insert(r * 3 + (back ? 2 - c : c))
                }
            }
        }
        let delta = back ? -n : n
        for i in hit { dial[i] = ((dial[i] + delta) % 12 + 12) % 12 }
    }

    /// Hour positions of the face seen from the front, row-major.
    var front: [Int] { dial }
    /// Hour positions of the face seen from the back, row-major in the back view.
    var backFace: [Int] {
        (0..<9).map { i in (12 - dial[(i / 3) * 3 + 2 - i % 3]) % 12 }
    }
}
