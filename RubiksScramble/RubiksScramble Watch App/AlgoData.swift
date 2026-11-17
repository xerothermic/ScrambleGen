import SwiftUI

/// Constants for the Algorithms card (Wallet-stack card + its screens).
enum AlgoCardInfo {
    static let id = "algos"
    static let color = Color(red: 0.58, green: 0.33, blue: 0.90)
    static let progressKey = "algoProgress"
    static let filterKey = "algoFilter"
    static let inverseBonusKey = "algoInverseBonus"
}

/// One pre/post-AUF variant of a case: its own scramble, solution and (PLL)
/// arrows. OLL variants keep the case picture.
struct AlgoAuf: Decodable {
    let pre: String
    let post: String
    let setup: String
    let solve: String
    let cp: String?
    let ep: String?
}

/// One OLL, PLL or edge-orientation-step case, as stored in AlgoCases.json
/// (generated and verified by scripts/verify_algos.py).
struct AlgoCase: Decodable, Identifiable {
    let id: String
    let kind: String          // "oll", "pll" or "edge"
    let name: String
    let mnemonic: String
    let alg: String
    let pic: String?          // OLL / edge: 21 chars of 0/1
    let cp: String?           // PLL corner arrows
    let ep: String?           // PLL edge arrows
    let desc: String?
    let twoLook: Bool
    let setup: String
    let solve: String
    let aufs: [AlgoAuf]
    let inverseOf: String?
    let inverseKind: String?  // "self" or "pair"

    enum CodingKeys: String, CodingKey {
        case id, kind, name, mnemonic, alg, pic, cp, ep, desc
        case twoLook = "two_look"
        case setup, solve, aufs, inverseOf, inverseKind
    }

    var isPLL: Bool { kind == "pll" }
    var isSelfInverse: Bool { inverseKind == "self" }

    /// Second line under the name: the mnemonic, else the generated description.
    var detail: String {
        mnemonic.isEmpty ? (desc ?? "") : mnemonic
    }
}

/// The bundled case list and the sets drills and lists are filtered by.
enum AlgoLibrary {
    static let all: [AlgoCase] = {
        guard let url = Bundle.main.url(forResource: "AlgoCases", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let cases = try? JSONDecoder().decode([AlgoCase].self, from: data)
        else { return [] }
        return cases
    }()

    static let byID: [String: AlgoCase] =
        Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    /// The inverse case, nil for a self-inverse one.
    static func inverse(of c: AlgoCase) -> AlgoCase? {
        guard c.inverseKind == "pair", let id = c.inverseOf else { return nil }
        return byID[id]
    }

    /// True when A's inverse is B and B's inverse is A (both directions).
    static func isMutualPair(_ c: AlgoCase) -> Bool {
        guard let other = inverse(of: c) else { return false }
        return other.inverseOf == c.id
    }
}

/// Case sets for the filter (stored in @AppStorage as the raw value).
enum AlgoSet: String, CaseIterable, Identifiable {
    case all, oll, pll, twoLookOLL, twoLookPLL, inversePairs, weak

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "All"
        case .oll: "OLL"
        case .pll: "PLL"
        case .twoLookOLL: "2-look OLL"
        case .twoLookPLL: "2-look PLL"
        case .inversePairs: "Inverse pairs"
        case .weak: "Weak list"
        }
    }

    func contains(_ c: AlgoCase, progress: [String: AlgoProgress]) -> Bool {
        switch self {
        case .all: return true
        case .oll: return c.kind == "oll"
        case .pll: return c.isPLL
        case .twoLookOLL: return c.kind == "edge" || (c.kind == "oll" && c.twoLook)
        case .twoLookPLL: return c.isPLL && c.twoLook
        case .inversePairs: return AlgoLibrary.isMutualPair(c)
        case .weak: return progress[c.id]?.isWeak ?? false
        }
    }

    func cases(progress: [String: AlgoProgress]) -> [AlgoCase] {
        AlgoLibrary.all.filter { contains($0, progress: progress) }
    }
}

/// Leitner state and times for one case.
struct AlgoProgress: Codable {
    /// 0 = never rated, 1...5 = Leitner box.
    var box = 0
    /// Day number the case is due again.
    var due = 0
    var last = 0
    var bestMs: Int?
    var lastMs: Int?
    /// True when the latest rating was "Not yet" / "Slow".
    var notYet = false

    /// Weak list: boxes 1-2, or "Not yet" on the last try (rated cases only).
    var isWeak: Bool { box >= 1 && (box <= 2 || notYet) }
    var isKnown: Bool { box >= 4 }
}

/// Persisted progress for all cases (UserDefaults, one JSON blob, ~10 KB).
final class AlgoStore: ObservableObject {
    @Published private(set) var progress: [String: AlgoProgress]

    /// Days until due, per box (index = box).
    static let intervals = [0, 0, 1, 2, 4, 8, 16]

    init() {
        if let data = UserDefaults.standard.data(forKey: AlgoCardInfo.progressKey),
           let saved = try? JSONDecoder().decode([String: AlgoProgress].self, from: data) {
            progress = saved
        } else {
            progress = [:]
        }
    }

    /// Local calendar day number.
    static var today: Int {
        Int((Date().timeIntervalSince1970 + Double(TimeZone.current.secondsFromGMT())) / 86400)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(progress) {
            UserDefaults.standard.set(data, forKey: AlgoCardInfo.progressKey)
        }
    }

    func entry(_ id: String) -> AlgoProgress { progress[id] ?? AlgoProgress() }

    /// Rating: Know it / Good moves up one box (cap 5, unseen goes to 2), Not
    /// yet / Slow goes back to box 1. A time (ms) is stored as `lastMs`, and as
    /// `bestMs` when it is the fastest rated Good/Know it.
    func rate(_ id: String, good: Bool, ms: Int? = nil) {
        var p = entry(id)
        p.box = good ? min(5, max(p.box, 1) + 1) : 1
        p.due = Self.today + Self.intervals[p.box]
        p.last = Self.today
        p.notYet = !good
        if let ms = ms {
            p.lastMs = ms
            if good, ms < (p.bestMs ?? Int.max) { p.bestMs = ms }
        }
        progress[id] = p
        save()
    }

    func reset() {
        progress = [:]
        UserDefaults.standard.removeObject(forKey: AlgoCardInfo.progressKey)
    }

    func dueCount(in cases: [AlgoCase]) -> Int {
        let today = Self.today
        return cases.filter { entry($0.id).box == 0 || entry($0.id).due <= today }.count
    }

    /// The next case to drill: the earliest due (unseen counts as due today),
    /// random among ties and never the same case twice in a row; when nothing
    /// is due, the lowest box.
    func next(in cases: [AlgoCase], avoiding last: String?) -> AlgoCase? {
        guard !cases.isEmpty else { return nil }
        let pool = cases.count > 1 ? cases.filter { $0.id != last } : cases
        let today = Self.today
        func dueDay(_ c: AlgoCase) -> Int {
            let p = entry(c.id)
            return p.box == 0 ? today : p.due
        }
        let due = pool.filter { dueDay($0) <= today }
        if !due.isEmpty {
            let earliest = due.map(dueDay).min() ?? today
            return due.filter { dueDay($0) == earliest }.randomElement()
        }
        let lowest = pool.map { entry($0.id).box }.min() ?? 0
        return pool.filter { entry($0.id).box == lowest }.randomElement()
    }
}

/// Text layout helpers for algs and scrambles.
enum AlgoText {
    /// Moves grouped `perLine` to a line, never splitting a move.
    static func lines(_ alg: String, perLine: Int) -> String {
        let moves = alg.split(separator: " ").map(String.init)
        return stride(from: 0, to: moves.count, by: perLine)
            .map { moves[$0..<min($0 + perLine, moves.count)].joined(separator: " ") }
            .joined(separator: "\n")
    }

    static func moveCount(_ alg: String) -> Int {
        alg.split(separator: " ").count
    }

    /// Font size for an alg block so the longest still fits the screen.
    static func algFontSize(_ alg: String) -> CGFloat {
        let n = moveCount(alg)
        return n <= 12 ? 20 : (n <= 18 ? 16 : 14)
    }
}
