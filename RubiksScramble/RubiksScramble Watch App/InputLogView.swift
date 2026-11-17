import SwiftUI

// Input log card (debug tool): the last ~30 input events (taps, drags, crown,
// settings changes) with timestamps. Only listed with Debug mode on, and
// DebugLog.log is a no-op with Debug off. The last 200 lines persist in
// UserDefaults "debug.log" so they survive a relaunch.

enum InputLogCard {
    static let id = "inputlog"
    static let color = Color(red: 0.45, green: 0.30, blue: 0.70)
}

@Observable
final class DebugLog {
    static let shared = DebugLog()
    static let key = "debug.log"
    static let maxStored = 200
    static let maxShown = 30

    private(set) var lines: [String]   // oldest first
    private var lastCrown = 0.0

    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private init() {
        lines = UserDefaults.standard.stringArray(forKey: Self.key) ?? []
    }

    static var enabled: Bool { UserDefaults.standard.bool(forKey: GeneralSettings.debugKey) }

    /// Appends a timestamped line. No-op (cheap) when Debug mode is off.
    static func log(_ text: String) {
        guard enabled else { return }
        shared.add(text)
    }

    static func setting<T>(_ key: String, _ old: T, _ new: T) {
        log("set \(key) \(old) -> \(new)")
    }

    /// Crown events are rate limited to ~4/s so they do not flood the log.
    static func crown(_ value: Double, delta: Double) {
        guard enabled else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - shared.lastCrown >= 0.25 else { return }
        shared.lastCrown = now
        shared.add(String(format: "crown %.2f d%+.2f", value, delta))
    }

    private func add(_ text: String) {
        lines.append("\(Self.fmt.string(from: Date())) \(text)")
        if lines.count > Self.maxStored { lines.removeFirst(lines.count - Self.maxStored) }
        UserDefaults.standard.set(lines, forKey: Self.key)
    }

    func clear() {
        lines = []
        UserDefaults.standard.removeObject(forKey: Self.key)
    }
}

extension View {
    /// Logs a tap without consuming it.
    func logTap(_ name: String) -> some View {
        simultaneousGesture(TapGesture().onEnded { DebugLog.log("tap \(name)") })
    }
}

struct InputLogScreen: View {
    private let log = DebugLog.shared

    var body: some View {
        List {
            Button(role: .destructive) { log.clear() } label: {
                Text("Clear").font(.system(size: 11))
            }
            .controlSize(.mini)
            ForEach(Array(log.lines.suffix(DebugLog.maxShown).reversed().enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 9, design: .monospaced))
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 2))
            }
        }
        .navigationTitle("Input log")
        .onAppear { DebugLog.log("Input log opened") }
    }
}
