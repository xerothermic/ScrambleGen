import SwiftUI

/// Card identity (matched-geometry id and tint) for the Customization card.
enum CustomizationCard {
    static let id = "customization"
    static let color = Color(red: 0.18, green: 0.45, blue: 0.48)
}

/// Ao5 crown sensitivity. Raw value is persisted.
enum Ao5Sensitivity: Int, CaseIterable, Identifiable {
    case veryLow = 0, low = 1, medium = 2
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .veryLow: return "Very low"
        case .low: return "Low"
        case .medium: return "Medium"
        }
    }
    /// Crown units (each is 1 ms at divisor 1) needed per millisecond.
    var unitsPerMilli: Int {
        switch self {
        case .veryLow: return 4
        case .low: return 2
        case .medium: return 1
        }
    }
    var crownSensitivity: DigitalCrownRotationalSensitivity {
        self == .medium ? .medium : .low
    }
}

/// Persisted customization settings (UserDefaults, watch-local). Add a nested
/// enum of keys + defaults per feature section; screens bind with @AppStorage
/// using these keys, and consumers call `load()` once (not per crown tick).
enum Ao5Settings {
    static let feedbackKey = "ao5.feedback"
    static let intervalKey = "ao5.feedbackInterval"
    static let sensitivityKey = "ao5.sensitivity"
    static let accelKey = "ao5.accel"

    static let defaultFeedback = true
    static let defaultInterval = 10
    static let defaultSensitivity = Ao5Sensitivity.veryLow.rawValue
    static let defaultAccel = false
    static let intervals = [1, 5, 10, 25, 50, 100, 500]

    struct Snapshot {
        var feedback = defaultFeedback
        var interval = defaultInterval
        var sensitivity = Ao5Sensitivity.veryLow
        var accel = defaultAccel
    }

    static func load() -> Snapshot {
        let d = UserDefaults.standard
        var s = Snapshot()
        if d.object(forKey: feedbackKey) != nil { s.feedback = d.bool(forKey: feedbackKey) }
        if d.object(forKey: intervalKey) != nil { s.interval = max(1, d.integer(forKey: intervalKey)) }
        if d.object(forKey: sensitivityKey) != nil {
            s.sensitivity = Ao5Sensitivity(rawValue: d.integer(forKey: sensitivityKey)) ?? .veryLow
        }
        if d.object(forKey: accelKey) != nil { s.accel = d.bool(forKey: accelKey) }
        return s
    }
}

/// Settings screen: one Section per feature, so adding a feature = adding a
/// Section here (and its keys above).
struct CustomizationScreen: View {
    @AppStorage(Ao5Settings.feedbackKey) private var feedback = Ao5Settings.defaultFeedback
    @AppStorage(Ao5Settings.intervalKey) private var interval = Ao5Settings.defaultInterval
    @AppStorage(Ao5Settings.sensitivityKey) private var sensitivity = Ao5Settings.defaultSensitivity
    @AppStorage(Ao5Settings.accelKey) private var accel = Ao5Settings.defaultAccel

    var body: some View {
        Form {
            Section("Ao5") {
                Toggle("Crown feedback", isOn: $feedback)
                Picker("Feedback every", selection: $interval) {
                    ForEach(Ao5Settings.intervals, id: \.self) { ms in
                        Text("\(ms) ms").tag(ms)
                    }
                }
                .disabled(!feedback)
                Picker("Crown sensitivity", selection: $sensitivity) {
                    ForEach(Ao5Sensitivity.allCases) { s in
                        Text(s.title).tag(s.rawValue)
                    }
                }
                Toggle("Fast-spin acceleration", isOn: $accel)
            }
        }
        .navigationTitle("Customization")
    }
}
