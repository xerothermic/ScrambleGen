import Foundation

/// WCA average of 5 (Ao5) calculation. Pure Foundation, no UI, so it is unit
/// tested off-device (Tests/Ao5, `swift test` on a Mac) and mirrored by
/// scripts/verify_ao5.py. All times are integer centiseconds.

enum Ao5Penalty: Equatable {
    case none
    case plus2   // +2 s added to the time
    case dnf     // did not finish
}

struct Ao5Solve: Equatable {
    /// The time as shown on the timer, in centiseconds (before any penalty).
    var centis: Int
    var penalty: Ao5Penalty = .none

    var isDNF: Bool { penalty == .dnf }

    /// The time that counts: +2 applied; nil for a DNF.
    var effectiveCentis: Int? {
        switch penalty {
        case .none: return centis
        case .plus2: return centis + 200
        case .dnf: return nil
        }
    }
}

struct Ao5Result: Equatable {
    /// Indices (0...4) of the two dropped solves: the fastest and the slowest.
    let dropped: Set<Int>
    /// Average in centiseconds; nil = DNF (two or more DNFs).
    let averageCentis: Int?
    /// Best single in centiseconds (with +2 applied); nil if every solve is DNF.
    let bestCentis: Int?
}

enum AverageOfFive {
    static let count = 5

    /// nil unless exactly 5 solves are given.
    ///
    /// Rank solves fastest to slowest (a DNF is slower than any time). The
    /// fastest and slowest are dropped and the middle three averaged. Ties are
    /// broken by solve order (stable sort), so the dropped pair is always two
    /// different solves, even when all five times are equal. Two or more DNFs
    /// make the average a DNF. The mean is rounded to the nearest centisecond
    /// (the exact value is never a half, because it is a sum divided by 3).
    static func compute(_ solves: [Ao5Solve]) -> Ao5Result? {
        guard solves.count == count else { return nil }
        let ranked = solves.indices.sorted { a, b in
            let ta = solves[a].effectiveCentis ?? Int.max
            let tb = solves[b].effectiveCentis ?? Int.max
            return ta != tb ? ta < tb : a < b
        }
        let dropped = Set([ranked[0], ranked[count - 1]])
        let middle = ranked[1..<(count - 1)].map { solves[$0].effectiveCentis }
        let average: Int?
        if solves.filter({ $0.isDNF }).count >= 2 || middle.contains(where: { $0 == nil }) {
            average = nil
        } else {
            let sum = middle.reduce(0) { $0 + ($1 ?? 0) }
            average = (2 * sum + 3) / 6   // round(sum / 3), half up
        }
        let best = solves.compactMap { $0.effectiveCentis }.min()
        return Ao5Result(dropped: dropped, averageCentis: average, bestCentis: best)
    }

    /// "8.42", "1:02.42", "DNF" for nil.
    static func format(_ centis: Int?) -> String {
        guard let c = centis else { return "DNF" }
        let total = max(0, c)
        let m = total / 6000
        let s = (total / 100) % 60
        let cc = total % 100
        return m > 0
            ? String(format: "%d:%02d.%02d", m, s, cc)
            : String(format: "%d.%02d", s, cc)
    }

    /// One solve as shown in the list: "8.42", "10.42+" for +2 (shows the
    /// time including the penalty), "DNF". `parenthesized` marks dropped times.
    static func label(_ solve: Ao5Solve, parenthesized: Bool = false) -> String {
        var text = format(solve.effectiveCentis)
        if solve.penalty == .plus2 { text += "+" }
        return parenthesized ? "(\(text))" : text
    }

    /// Centiseconds from typed digits, entered right to left like a stopwatch
    /// ("1234" = 12.34, "10234" = 1:02.34). Seconds above 59 carry into
    /// minutes ("7599" = 75.99 s = 1:15.99). Non-digits are ignored.
    static func centis(fromDigits digits: String) -> Int {
        let ds = digits.filter { $0 >= "0" && $0 <= "9" }.suffix(6)
        guard let value = Int(ds) else { return 0 }
        let cc = value % 100
        let rest = value / 100
        let seconds = rest % 100 + (rest / 100) * 60
        return seconds * 100 + cc
    }
}
