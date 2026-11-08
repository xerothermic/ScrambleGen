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
    static let speedUpKey = "ao5.speedUp"

    static let defaultFeedback = true
    static let defaultInterval = 10
    static let defaultStep = 1
    static let defaultSpeedUp = true
    static let intervals = [1, 5, 10, 25, 50, 100, 500]
    static let steps = [1, 2, 5, 10]

    struct Snapshot {
        var feedback = defaultFeedback
        var interval = defaultInterval
        var step = defaultStep
        var speedUp = defaultSpeedUp
    }

    static func load() -> Snapshot {
        let d = UserDefaults.standard
        var s = Snapshot()
        if d.object(forKey: feedbackKey) != nil { s.feedback = d.bool(forKey: feedbackKey) }
        if d.object(forKey: intervalKey) != nil { s.interval = max(1, d.integer(forKey: intervalKey)) }
        if d.object(forKey: stepKey) != nil { s.step = max(1, d.integer(forKey: stepKey)) }
        if d.object(forKey: speedUpKey) != nil { s.speedUp = d.bool(forKey: speedUpKey) }
        return s
    }
}

/// Settings screen: one Section per feature, so adding a feature = adding a
/// Section here (and its keys above).
struct CustomizationScreen: View {
    @AppStorage(Ao5Settings.feedbackKey) private var feedback = Ao5Settings.defaultFeedback
    @AppStorage(Ao5Settings.intervalKey) private var interval = Ao5Settings.defaultInterval
    @AppStorage(Ao5Settings.stepKey) private var step = Ao5Settings.defaultStep
    @AppStorage(Ao5Settings.speedUpKey) private var speedUp = Ao5Settings.defaultSpeedUp
    @AppStorage(ScrambleSource.randomStateKey) private var randomState = ScrambleSource.defaultRandomState

    var body: some View {
        Form {
            Section("3x3 scramble") {
                Toggle("Random-state (WCA-style)", isOn: $randomState)
                    .onChange(of: randomState) { _, on in
                        if on { ScrambleSource.prewarm() }
                    }
            }
            Section("Ao5") {
                Picker("Crown speed", selection: $step) {
                    ForEach(Ao5Settings.steps, id: \.self) { ms in
                        Text("\(ms) ms").tag(ms)
                    }
                }
                Toggle("Fast-spin acceleration", isOn: $speedUp)
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
