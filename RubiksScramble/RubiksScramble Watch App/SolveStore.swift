import Foundation
import Combine
import os

/// One finished solve. Pause fields are filled only for solves recorded with
/// Motion insights on (experimental, see PauseAnalyzer).
struct SolveRecord: Codable, Identifiable, Equatable {
    var id: UUID
    var time: TimeInterval
    var date: Date
    var note: String?
    /// Session number; Reset on the Timer result screen starts a new one.
    var session: Int
    /// True when a raw motion file for this solve exists.
    var hasMotion: Bool?
    /// True for solves imported from the old last-20 list (date unknown).
    var imported: Bool?

    var pauseCount: Int?
    var quietTotal: TimeInterval?
    var longestPause: TimeInterval?
    var quietRatio: Double?
    /// Seconds from "go" to the first wrist movement.
    var startLatency: TimeInterval?
}

/// Averages. WCA-style aoN: drop the single best and worst of the last N, mean
/// of the rest. No DNFs exist in this app, so every time counts.
enum SolveStats {
    static func ao(_ n: Int, _ times: [TimeInterval]) -> TimeInterval? {
        guard n >= 3, times.count >= n else { return nil }
        let window = times.suffix(n)
        let sum = window.reduce(0, +) - (window.min() ?? 0) - (window.max() ?? 0)
        return sum / Double(n - 2)
    }

    /// Rolling aoN at every index (nil until N solves exist).
    static func rollingAo(_ n: Int, _ times: [TimeInterval]) -> [TimeInterval?] {
        times.indices.map { i in
            i + 1 >= n ? ao(n, Array(times[(i + 1 - n)...i])) : nil
        }
    }

    static func mean(_ times: [TimeInterval]) -> TimeInterval? {
        times.isEmpty ? nil : times.reduce(0, +) / Double(times.count)
    }

    static func bestAo(_ n: Int, _ times: [TimeInterval]) -> TimeInterval? {
        rollingAo(n, times).compactMap { $0 }.min()
    }

    /// Indices whose time was a new best single when it was set.
    static func recordIndices(_ times: [TimeInterval]) -> [Int] {
        var best = TimeInterval.infinity
        var out: [Int] = []
        for (i, t) in times.enumerated() where t < best {
            best = t
            out.append(i)
        }
        return out
    }
}

/// Persistent solve history: a JSON file in Application Support, oldest first,
/// capped at `cap` solves (oldest dropped). Everything stays on this watch.
@MainActor
final class SolveStore: ObservableObject {
    static let shared = SolveStore()
    static let cap = 5000

    @Published private(set) var records: [SolveRecord] = []

    private let fileURL: URL
    private let ioQueue = DispatchQueue(label: "solvestore.io", qos: .utility)
    private let log = Logger(subsystem: "com.pcintaiwan.scramblegen.watch", category: "history")

    private init() {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("History", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("solves.json")
        load()
        migrateLegacyIfNeeded()
        pruneMotion()
    }

    var session: Int {
        get { max(1, UserDefaults.standard.integer(forKey: "timerSessionID")) }
        set { UserDefaults.standard.set(newValue, forKey: "timerSessionID") }
    }

    var times: [TimeInterval] { records.map(\.time) }

    // MARK: Mutation

    @discardableResult
    func add(time: TimeInterval, hasMotion: Bool) -> SolveRecord {
        let r = SolveRecord(id: UUID(), time: time, date: Date(), note: nil,
                            session: session, hasMotion: hasMotion ? true : nil, imported: nil)
        records.append(r)
        trimToCap()
        pruneMotion()
        save()
        return r
    }

    func update(_ id: UUID, _ change: (inout SolveRecord) -> Void) {
        guard let i = records.firstIndex(where: { $0.id == id }) else { return }
        change(&records[i])
        save()
    }

    func delete(_ id: UUID) {
        records.removeAll { $0.id == id }
        MotionStore.shared.delete(id)
        save()
    }

    func deleteAll() {
        records.removeAll()
        MotionStore.shared.deleteAll()
        save()
    }

    func startNewSession() { session += 1 }

    /// Keeps raw motion files for the newest `MotionStore.maxFiles` solves that
    /// have one; older files are deleted (their pause stats stay on the record).
    func pruneMotion() {
        var kept = 0
        var keep = Set<UUID>()
        for i in records.indices.reversed() where records[i].hasMotion == true {
            if kept < MotionStore.maxFiles {
                kept += 1
                keep.insert(records[i].id)
            } else {
                records[i].hasMotion = nil
            }
        }
        MotionStore.shared.prune(keeping: keep)
    }

    private func trimToCap() {
        if records.count > Self.cap { records.removeFirst(records.count - Self.cap) }
    }

    // MARK: Disk

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601
            records = try dec.decode([SolveRecord].self, from: data)
        } catch {
            // Keep the unreadable file for inspection instead of overwriting it.
            log.error("history decode failed: \(String(describing: error), privacy: .public)")
            let bad = fileURL.deletingLastPathComponent().appendingPathComponent("solves.corrupt.json")
            try? FileManager.default.removeItem(at: bad)
            try? FileManager.default.moveItem(at: fileURL, to: bad)
        }
    }

    private func save() {
        let snapshot = records
        let url = fileURL
        ioQueue.async {
            let enc = JSONEncoder()
            enc.dateEncodingStrategy = .iso8601
            guard let data = try? enc.encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    /// One-time import of the old UserDefaults last-20 list. The legacy key is
    /// left in place (the Timer card still uses it for its session list), and
    /// the flag stops a second import.
    private func migrateLegacyIfNeeded() {
        let flag = "historyMigratedFromDefaults"
        let ud = UserDefaults.standard
        guard !ud.bool(forKey: flag) else { return }
        defer { ud.set(true, forKey: flag) }
        guard records.isEmpty else { return }
        let old = (ud.array(forKey: TimerCard.solvesKey) as? [Double]) ?? []
        guard !old.isEmpty else { return }
        // Real dates are unknown: space them one minute apart ending now.
        let now = Date()
        records = old.enumerated().map { i, t in
            SolveRecord(id: UUID(), time: t,
                        date: now.addingTimeInterval(-60 * Double(old.count - 1 - i)),
                        note: nil, session: session, hasMotion: nil, imported: true)
        }
        save()
        log.info("migrated \(old.count, privacy: .public) solves from UserDefaults")
    }
}
