import Foundation

/// One entered solve time, stored in whole centiseconds (WCA resolution).
/// `centis == nil` is a DNF. A +2 penalty is already included in `centis`;
/// `plusTwo` only remembers that it was applied so it can be shown and undone.
/// Pure Foundation, no UI types, so it is unit-tested on Linux (see Package.swift).
struct SolveTime: Equatable {
    var centis: Int?
    var plusTwo: Bool

    static let dnf = SolveTime(centis: nil)

    static func time(_ centis: Int, plusTwo: Bool = false) -> SolveTime {
        SolveTime(centis: centis + (plusTwo ? 200 : 0), plusTwo: plusTwo)
    }

    var isDNF: Bool { centis == nil }

    /// "12.34", "1:02.34", "12.34+2" (time shown includes the penalty), "DNF".
    var text: String {
        guard let c = centis else { return "DNF" }
        return SolveTime.format(centis: c) + (plusTwo ? "+" : "")
    }

    /// Typed text -> time. Accepts "12.34", "12.3", "12", "1:02.34", "DNF"
    /// (any case, or "D"), and a "+2" suffix ("12.34+2", "12.34 +2", or "+2"
    /// alone is not valid). Returns nil for anything else.
    static func parse(_ raw: String) -> SolveTime? {
        var s = raw.trimmingCharacters(in: .whitespaces).uppercased()
        if s == "DNF" || s == "D" { return .dnf }
        var penalty = false
        if s.hasSuffix("+2") {
            penalty = true
            s = String(s.dropLast(2)).trimmingCharacters(in: .whitespaces)
        }
        guard !s.isEmpty, let base = parseClock(s) else { return nil }
        return .time(base, plusTwo: penalty)
    }

    /// Compact form for UserDefaults: "1234", "1434+" (penalty applied), "DNF".
    var stored: String {
        guard let c = centis else { return "DNF" }
        return "\(c)" + (plusTwo ? "+" : "")
    }

    init(centis: Int?, plusTwo: Bool = false) {
        self.centis = centis
        self.plusTwo = plusTwo
    }

    init?(stored: String) {
        if stored == "DNF" { self = .dnf; return }
        let plus = stored.hasSuffix("+")
        let digits = plus ? String(stored.dropLast()) : stored
        guard let c = Int(digits), c >= 0 else { return nil }
        self.init(centis: c, plusTwo: plus)
    }

    /// Number-pad entry, csTimer style: digits fill in from the right as
    /// centiseconds, so "1234" is 12.34, "5" is 0.05, "10234" is 1:02.34.
    /// Up to 6 digits (99:59.99). Empty or non-digit input gives nil.
    static func fromDigits(_ digits: String, plusTwo: Bool = false) -> SolveTime? {
        guard !digits.isEmpty, digits.count <= 6,
              digits.allSatisfy({ $0.isASCII && $0.isNumber }),
              let n = Int(digits) else { return nil }
        let minutes = n / 10000
        let secs = (n / 100) % 100
        let cs = n % 100
        guard secs < 60 else { return nil }
        return .time(minutes * 6000 + secs * 100 + cs, plusTwo: plusTwo)
    }

    /// "[m:]s[.cc]" -> centiseconds. Seconds may exceed 59 only without minutes.
    private static func parseClock(_ s: String) -> Int? {
        let parts = s.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return nil }
        var minutes = 0
        var secPart = parts[parts.count - 1]
        if parts.count == 2 {
            guard let m = Int(parts[0]), parts[0].allSatisfy({ $0.isASCII && $0.isNumber })
            else { return nil }
            minutes = m
            secPart = parts[1]
        }
        let sp = secPart.split(separator: ".", omittingEmptySubsequences: false)
        guard sp.count <= 2, let whole = sp.first, !whole.isEmpty,
              whole.allSatisfy({ $0.isASCII && $0.isNumber }),
              let secs = Int(whole) else { return nil }
        if parts.count == 2 && secs >= 60 { return nil }
        var cs = 0
        if sp.count == 2 {
            let frac = sp[1]
            guard !frac.isEmpty, frac.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            // Typed precision beyond centiseconds is truncated, like a timer display.
            let padded = (String(frac) + "00").prefix(2)
            cs = Int(padded) ?? 0
        }
        return minutes * 6000 + secs * 100 + cs
    }

    /// "8.42", "1:02.42" for a centisecond count.
    static func format(centis: Int) -> String {
        let total = max(0, centis)
        let m = total / 6000
        let s = (total / 100) % 60
        let c = total % 100
        return m > 0
            ? String(format: "%d:%02d.%02d", m, s, c)
            : String(format: "%d.%02d", s, c)
    }
}

/// Result of an Average of 5 or Mean of 3.
struct AverageResult: Equatable {
    /// Centiseconds, rounded half up per WCA; nil = DNF.
    var centis: Int?
    /// Indexes (into the input) of the dropped fastest and slowest; empty for a mean.
    var dropped: [Int]

    var isDNF: Bool { centis == nil }
    var text: String { centis.map { SolveTime.format(centis: $0) } ?? "DNF" }
}

enum SolveAverages {
    /// WCA Average of 5: drop the fastest and the slowest, mean of the middle 3.
    /// A DNF is the slowest; one DNF is simply the dropped worst, two or more
    /// make the average a DNF. Ties drop the earliest. Needs exactly 5 solves.
    static func averageOf5(_ solves: [SolveTime]) -> AverageResult? {
        guard solves.count == 5 else { return nil }
        // Sort key: DNF after every real time; the index keeps ties stable.
        let order = solves.indices.sorted { a, b in
            let ka = solves[a].centis ?? Int.max
            let kb = solves[b].centis ?? Int.max
            return ka != kb ? ka < kb : a < b
        }
        let best = order[0], worst = order[4]
        let dnfs = solves.filter(\.isDNF).count
        let dropped = [best, worst]
        if dnfs >= 2 { return AverageResult(centis: nil, dropped: dropped) }
        let sum = order[1...3].reduce(0) { $0 + (solves[$1].centis ?? 0) }
        return AverageResult(centis: roundedMean(sum: sum, count: 3), dropped: dropped)
    }

    /// WCA Mean of 3: plain mean, any DNF makes it a DNF. Needs exactly 3 solves.
    static func meanOf3(_ solves: [SolveTime]) -> AverageResult? {
        guard solves.count == 3 else { return nil }
        if solves.contains(where: \.isDNF) { return AverageResult(centis: nil, dropped: []) }
        let sum = solves.reduce(0) { $0 + ($1.centis ?? 0) }
        return AverageResult(centis: roundedMean(sum: sum, count: 3), dropped: [])
    }

    /// sum / count rounded half up to a whole centisecond, in exact integer
    /// arithmetic: floor((2 sum + count) / (2 count)).
    static func roundedMean(sum: Int, count: Int) -> Int {
        (2 * sum + count) / (2 * count)
    }

    /// Each solve as text, the dropped ones in parentheses: "(9.99)", "(DNF)".
    static func displayTimes(_ solves: [SolveTime], dropped: [Int]) -> [String] {
        solves.enumerated().map { i, s in
            dropped.contains(i) ? "(\(s.text))" : s.text
        }
    }
}
