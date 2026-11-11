import Foundation

/// Random-move Rubik's Clock scrambles in WCA notation (Regulations
/// 12g): `UR# DR# DL# UL# U# R# D# L# ALL# y2 U# R# D# L# ALL#` plus the pins
/// that end up (`UR DR DL UL` subset). Each `#` is a dial turn written as its
/// magnitude and sign, from `5-` through `6+` (clock positions -5...6; zero
/// is always written `0+`), matching TNoodle's output.
enum ClockScrambler {
    static let frontMoves = ["UR", "DR", "DL", "UL", "U", "R", "D", "L", "ALL"]
    static let backMoves = ["U", "R", "D", "L", "ALL"]
    static let pinNames = ["UR", "DR", "DL", "UL"]
    static let turnRange = -5...6

    /// Dial turn as a token suffix: `3+`, `4-`, `0+`.
    static func format(_ turn: Int) -> String {
        "\(abs(turn))" + (turn < 0 ? "-" : "+")
    }

    /// 9 front moves, `y2`, 5 back moves, then the pins left up (0-4 tokens).
    static func generate() -> [String] {
        var tokens = frontMoves.map { $0 + format(Int.random(in: turnRange)) }
        tokens.append("y2")
        tokens += backMoves.map { $0 + format(Int.random(in: turnRange)) }
        tokens += pinNames.filter { _ in Bool.random() }
        return tokens
    }
}
