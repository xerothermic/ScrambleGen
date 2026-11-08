import Foundation

/// WCA average of 5 (Ao5) calculation. Pure Foundation, no UI, so it is unit
/// tested off-device (Tests/Ao5, `swift test` on a Mac) and mirrored by
/// scripts/verify_ao5.py. All times are integer milliseconds.

enum Ao5Penalty: Equatable {
    case none
    case plus2   // +2 s added to the time
    case dnf     // did not finish
}

struct Ao5Solve: Equatable {
    /// The time as shown on the timer, in milliseconds (before any penalty).
    var millis: Int
    var penalty: Ao5Penalty = .none

    var isDNF: Bool { penalty == .dnf }

    /// The time that counts: +2 applied; nil for a DNF.
    var effectiveMillis: Int? {
        switch penalty {
        case .none: return millis
        case .plus2: return millis + 2000
        case .dnf: return nil
        }
    }
}

struct Ao5Result: Equatable {
    /// Indices (0...4) of the two dropped solves: the fastest and the slowest.
    let dropped: Set<Int>
    /// Average in milliseconds; nil = DNF (two or more DNFs).
    let averageMillis: Int?
    /// Best single in milliseconds (with +2 applied); nil if every solve is DNF.
    let bestMillis: Int?
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
    /// (times are shown with two decimals; the crown moves in whole centiseconds).
    static func compute(_ solves: [Ao5Solve]) -> Ao5Result? {
        guard solves.count == count else { return nil }
        let ranked = solves.indices.sorted { a, b in
            let ta = solves[a].effectiveMillis ?? Int.max
            let tb = solves[b].effectiveMillis ?? Int.max
            return ta != tb ? ta < tb : a < b
        }
        let dropped = Set([ranked[0], ranked[count - 1]])
        let middle = ranked[1..<(count - 1)].map { solves[$0].effectiveMillis }
        let average: Int?
        if solves.filter({ $0.isDNF }).count >= 2 || middle.contains(where: { $0 == nil }) {
            average = nil
        } else {
            let sum = middle.reduce(0) { $0 + ($1 ?? 0) }
            average = (sum + 15) / 30 * 10   // round(sum / 3) to the nearest centisecond, half up
        }
        let best = solves.compactMap { $0.effectiveMillis }.min()
        return Ao5Result(dropped: dropped, averageMillis: average, bestMillis: best)
    }

    /// "8.42", "1:02.34", "DNF" for nil. Centiseconds, truncated (as the WCA
    /// does for single times); milliseconds are never shown.
    static func format(_ millis: Int?) -> String {
        guard let c = millis else { return "DNF" }
        let total = max(0, c) / 10   // centiseconds
        let m = total / 6000
        let s = (total / 100) % 60
        let cs = total % 100
        return m > 0
            ? String(format: "%d:%02d.%02d", m, s, cs)
            : String(format: "%d.%02d", s, cs)
    }

    /// One solve as shown in the list: "8.420", "10.420+" for +2 (shows the
    /// time including the penalty), "DNF". `parenthesized` marks dropped times.
    static func label(_ solve: Ao5Solve, parenthesized: Bool = false) -> String {
        var text = format(solve.effectiveMillis)
        if solve.penalty == .plus2 { text += "+" }
        return parenthesized ? "(\(text))" : text
    }

    /// Milliseconds from typed digits, entered right to left like a stopwatch,
    /// the last two digits being centiseconds ("1234" = 12.34, "10234" = 1:02.34).
    /// Seconds above 59 carry into minutes ("7599" = 75.99 s = 1:15.99). Clamped to `maxMillis` (10:00.000).
    /// Non-digits are ignored.
    /// Longest time the Ao5 calculator accepts: 10:00.000. Everything entered or
    /// dialled is clamped to this.
    static let maxMillis = 600_000

    static func millis(fromDigits digits: String) -> Int {
        let ds = digits.filter { $0 >= "0" && $0 <= "9" }.suffix(6)
        guard let value = Int(ds) else { return 0 }
        let cs = value % 100
        let rest = value / 100
        let seconds = rest % 100 + (rest / 100) * 60
        return min(seconds * 1000 + cs * 10, maxMillis)
    }
}

/// Fast-spin acceleration mode: one detents/s threshold above which the step is x10.
/// Raw value is persisted (0...2 unchanged; custom added).
enum Ao5Accel: Int, CaseIterable, Identifiable {
    case off = 0, gentle = 1, normal = 2, custom = 3
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .off: return "Off"
        case .gentle: return "Gentle"
        case .normal: return "Normal"
        case .custom: return "Custom"
        }
    }
    /// Next/previous mode, wrapping (used by the '<' '>' buttons).
    func cycled(by delta: Int) -> Ao5Accel {
        let all = Ao5Accel.allCases
        let i = all.firstIndex(of: self) ?? 0
        return all[((i + delta) % all.count + all.count) % all.count]
    }
    /// Preset x10 threshold (detents/s); nil for Off, and for Custom (user value applies).
    var threshold: Double? {
        switch self {
        case .off, .custom: return nil
        case .gentle: return 50
        case .normal: return 25
        }
    }
    /// Threshold actually applied: preset, or the user's value for Custom; nil for Off.
    func resolvedThreshold(custom: Double) -> Double? {
        self == .custom ? custom : threshold
    }
}

/// Digital Crown delta -> steps (the Ao5 dial treats one step as one centisecond). Pure (time is passed in) so it is
/// unit-testable. The crown binding is a Double; calibrated on device
/// (`by: nil`, `.high`), ONE revolution = `unitsPerRev` (default 524, measured ~524.24; a setting) binding
/// units. `stepsPerRev` turns that into detents (default 150, ~2.4
/// degrees each): detents = delta / unitsPerRev * stepsPerRev. Fractional detents are CARRIED, never
/// truncated, so slow turns always add up; every whole detent is worth at
/// least the base step (>= 1 ms). Speed (detents/s, smoothed, restarting
/// after a 0.3 s pause) only raises the step when acceleration is on.
struct Ao5CrownMapper {
    static let defaultStepsPerRev = 150
    static let defaultUnitsPerRev = 524.0   // crown binding units per physical revolution (measured 524.24)
    var unitsPerRev = defaultUnitsPerRev
    var stepsPerRev = defaultStepsPerRev
    /// x10 threshold (detents/s) in Custom mode.
    var customThreshold = 25.0

    var baseStep = 1
    var accel = Ao5Accel.gentle
    private(set) var carry = 0.0           // fractional detents not yet applied
    private var speed = 0.0                // smoothed detents per second
    private var lastTime: Double?

    mutating func reset() { carry = 0; speed = 0; lastTime = nil }

    /// ms per detent for a turn speed. Slow = base step, never suppressed.
    static func step(forSpeed v: Double, base: Int, accel: Ao5Accel,
                     custom: Double = 25) -> Int {
        guard let t = accel.resolvedThreshold(custom: custom) else { return base }
        return max(base, v < t ? 1 : 10)
    }

    /// `delta` = change of the crown binding since the last event (any size,
    /// including tiny fractions); `now` = monotonic seconds. Returns signed ms.
    mutating func millis(forDelta delta: Double, now: Double) -> Int {
        guard delta != 0 else { return 0 }
        var detents = delta / max(1, unitsPerRev) * Double(max(1, stepsPerRev))
        if (detents > 0 && carry < 0) || (detents < 0 && carry > 0) { carry = 0 }   // reversal
        if let t = lastTime, now - t <= 0.3 {
            let inst = abs(detents) / max(now - t, 0.01)
            speed = speed == 0 ? inst : speed * 0.5 + inst * 0.5
        } else {
            speed = 0
        }
        lastTime = now
        detents += carry
        let whole = (detents + (detents < 0 ? -1e-9 : 1e-9)).rounded(.towardZero)   // absorb float dust (524 slow units must give exactly 150)
        carry = detents - whole
        return Int(whole) * Self.step(forSpeed: speed, base: max(1, baseStep), accel: accel,
                                         custom: customThreshold)
    }
}

/// Haptic detent decision for the Ao5 crown (pure, tested). `millis` = new value, `interval` = detent width
/// in ms (setting in cs * 10), `hapticIdx` = detent index last clicked/synced. Click when the value crossed up
/// into a higher detent, or fell back by more than interval/4 below the clicked detent's lower edge
/// (hysteresis on reversal). Returns the new index when a click is due, else nil.
enum Ao5Haptic {
    static func clickIndex(millis: Int, interval: Int, hapticIdx: Int) -> Int? {
        let iv = max(1, interval)
        let idx = millis / iv
        if idx > hapticIdx { return idx }
        if idx < hapticIdx && millis + iv / 4 < hapticIdx * iv { return idx }
        return nil
    }
}
