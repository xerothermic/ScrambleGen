import Foundation

struct EnvelopePoint: Identifiable {
    var t: Double
    var e: Double
    var id: Double { t }
}

struct PauseSpan: Equatable, Identifiable {
    var id: Double { start }
    var start: TimeInterval
    var end: TimeInterval
    var length: TimeInterval { end - start }
}

/// Result of the experimental "quiet time" analysis. Wrist stillness of 0.3 s
/// or more; a proxy for pausing, not a measurement of look-ahead.
struct PauseResult: Equatable {
    var spans: [PauseSpan]
    var count: Int { spans.count }
    var total: TimeInterval { spans.reduce(0) { $0 + $1.length } }
    var longest: TimeInterval { spans.map(\.length).max() ?? 0 }
    var ratio: Double
    /// Seconds from "go" to the first movement.
    var startLatency: TimeInterval

    /// "Quiet time 18% · 5 pauses"
    var summaryLine: String {
        "Quiet time \(Int((ratio * 100).rounded()))% · \(count) pause\(count == 1 ? "" : "s")"
    }
}

/// Quiet-time detector (Fable design, section 3):
///  - activity envelope e(t) = RMS over an 80 ms window of
///    sqrt(|a|^2 + k * |omega|^2)  (userAcceleration in g, rotationRate in rad/s)
///  - adaptive threshold theta = 25% of the median envelope over the solve
///  - a pause is e < theta for >= 300 ms, with hysteresis (leaves the pause when
///    e > 1.5 theta); pauses closer than 80 ms are merged
///  - start and stop are ignored: quiet time before the first movement is
///    "start latency", and a quiet stretch still open at the end is dropped.
/// All constants are tuning knobs for the validation week.
enum PauseAnalyzer {
    static let window: TimeInterval = 0.08
    static let gyroWeight = 0.02
    static let thresholdFraction = 0.25
    static let releaseFactor = 1.5
    static let minGap: TimeInterval = 0.3
    static let mergeGap: TimeInterval = 0.08
    static let minSamples = 25

    /// Envelope value for each sample, from the raw interleaved samples.
    static func envelope(_ d: MotionFile.Decoded) -> (t: [Double], e: [Double]) {
        let n = min(d.count, MotionFile.maxIndex(d.samples, upTo: d.elapsed))
        let k = MotionFile.floatsPerSample
        let s = d.samples
        var ts = [Double](), power = [Double]()
        ts.reserveCapacity(n); power.reserveCapacity(n)
        for i in 0..<n {
            let o = i * k
            let a2 = Double(s[o + 1] * s[o + 1] + s[o + 2] * s[o + 2] + s[o + 3] * s[o + 3])
            let g2 = Double(s[o + 4] * s[o + 4] + s[o + 5] * s[o + 5] + s[o + 6] * s[o + 6])
            ts.append(Double(s[o]))
            power.append(a2 + gyroWeight * g2)
        }
        var env = [Double](repeating: 0, count: n)
        var lo = 0
        var sum = 0.0
        for i in 0..<n {
            sum += power[i]
            while ts[i] - ts[lo] >= window { sum -= power[lo]; lo += 1 }
            env[i] = (max(0, sum) / Double(i - lo + 1)).squareRoot()
        }
        return (ts, env)
    }

    static func analyze(_ d: MotionFile.Decoded) -> PauseResult? {
        let (ts, env) = envelope(d)
        guard ts.count >= minSamples, d.elapsed > 1 else { return nil }
        let median = env.sorted()[env.count / 2]
        guard median > 1e-4 else { return nil }
        let theta = thresholdFraction * median

        var raw: [PauseSpan] = []
        var open: TimeInterval?
        var openFromStart = false
        var startLatency: TimeInterval = 0
        for i in 0..<ts.count {
            if let s = open {
                if env[i] > theta * releaseFactor {
                    if openFromStart { startLatency = ts[i] } else { raw.append(PauseSpan(start: s, end: ts[i])) }
                    open = nil
                    openFromStart = false
                }
            } else if env[i] < theta {
                open = ts[i]
                openFromStart = (i == 0)
            }
        }
        // A pause still open at the end is the stop, not a pause: dropped.

        var merged: [PauseSpan] = []
        for s in raw {
            if var last = merged.last, s.start - last.end < mergeGap {
                last.end = s.end
                merged[merged.count - 1] = last
            } else {
                merged.append(s)
            }
        }
        let spans = merged.filter { $0.length >= minGap }
        let total = spans.reduce(0) { $0 + $1.length }
        return PauseResult(spans: spans, ratio: min(1, total / d.elapsed), startLatency: startLatency)
    }

    /// Envelope reduced to at most `points` (max of each bucket) for plotting.
    static func downsampled(_ t: [Double], _ e: [Double], points: Int = 120) -> [EnvelopePoint] {
        guard !t.isEmpty else { return [] }
        let step = max(1, t.count / points)
        return stride(from: 0, to: t.count, by: step).map { i in
            let hi = min(t.count, i + step)
            return EnvelopePoint(t: t[i], e: e[i..<hi].max() ?? e[i])
        }
    }
}

extension MotionFile {
    /// Number of leading samples with t <= elapsed (the stop slap's own time).
    static func maxIndex(_ samples: [Float], upTo elapsed: TimeInterval) -> Int {
        let count = samples.count / floatsPerSample
        var n = 0
        while n < count, Double(samples[n * floatsPerSample]) <= elapsed { n += 1 }
        return n
    }
}
