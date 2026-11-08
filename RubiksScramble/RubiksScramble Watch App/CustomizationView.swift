import SwiftUI

/// Card identity (matched-geometry id and tint) for the Customization card.
enum CustomizationCard {
    static let id = "customization"
    static let color = Color(red: 0.18, green: 0.45, blue: 0.48)
}

/// Persisted customization settings (UserDefaults, watch-local). Add a nested
/// enum of keys + defaults per feature section; screens bind with @AppStorage
/// using these keys, and consumers call `load()` (on appear / slot change,
/// not per crown tick).
enum Ao5Settings {
    static let feedbackKey = "ao5.feedback"
    static let intervalKey = "ao5.feedbackInterval"
    static let stepKey = "ao5.crownStep"
    static let accelKey = "ao5.accelLevel"
    static let stepsKey = "ao5.stepsPerRev"

    static let defaultFeedback = true
    static let defaultInterval = 10
    static let defaultStep = 1
    static let defaultAccel = Ao5Accel.gentle.rawValue
    static let defaultSteps = Ao5CrownMapper.defaultStepsPerRev
    static let intervals = [1, 5, 10, 25, 50, 100, 500]
    static let stepsPerRev = [30, 60, 100, 150, 250, 400, 600, 1000]
    static let steps = [1, 2, 5, 10, 20, 50, 100]

    struct Snapshot {
        var feedback = defaultFeedback
        var interval = defaultInterval
        var step = defaultStep
        var accel = Ao5Accel.gentle
        var stepsPerRev = defaultSteps
    }

    static func load() -> Snapshot {
        let d = UserDefaults.standard
        var s = Snapshot()
        if d.object(forKey: feedbackKey) != nil { s.feedback = d.bool(forKey: feedbackKey) }
        if d.object(forKey: intervalKey) != nil { s.interval = max(1, d.integer(forKey: intervalKey)) }
        if d.object(forKey: stepKey) != nil { s.step = max(1, d.integer(forKey: stepKey)) }
        if d.object(forKey: accelKey) != nil {
            s.accel = Ao5Accel(rawValue: d.integer(forKey: accelKey)) ?? .gentle
        }
        if d.object(forKey: stepsKey) != nil { s.stepsPerRev = max(1, d.integer(forKey: stepsKey)) }
        return s
    }
}

/// Settings screen: one Section per feature, so adding a feature = adding a
/// Section here (and its keys above).
struct CustomizationScreen: View {
    @AppStorage(Ao5Settings.feedbackKey) private var feedback = Ao5Settings.defaultFeedback
    @AppStorage(Ao5Settings.intervalKey) private var interval = Ao5Settings.defaultInterval
    @AppStorage(Ao5Settings.stepKey) private var step = Ao5Settings.defaultStep
    @AppStorage(Ao5Settings.accelKey) private var accel = Ao5Settings.defaultAccel
    @AppStorage(Ao5Settings.stepsKey) private var stepsPerRev = Ao5Settings.defaultSteps

    var body: some View {
        Form {
            Section("Ao5") {
                Picker("Crown speed", selection: $step) {
                    ForEach(Ao5Settings.steps, id: \.self) { ms in
                        Text("\(ms) ms").tag(ms)
                    }
                }
                Picker("Steps per revolution", selection: $stepsPerRev) {
                    ForEach(Ao5Settings.stepsPerRev, id: \.self) { n in
                        Text("\(n)").tag(n)
                    }
                }
                Picker("Acceleration", selection: $accel) {
                    ForEach(Ao5Accel.allCases) { a in
                        Text(a.title).tag(a.rawValue)
                    }
                }
                Toggle("Crown feedback", isOn: $feedback)
                if feedback {
                    Picker("Feedback every", selection: $interval) {
                        ForEach(Ao5Settings.intervals, id: \.self) { ms in
                            Text("\(ms) ms").tag(ms)
                        }
                    }
                }
            }
        }
        .navigationTitle("Customization")
    }
}
