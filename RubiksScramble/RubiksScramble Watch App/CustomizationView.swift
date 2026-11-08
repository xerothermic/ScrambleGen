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
/// General (non-feature) settings; `debugKey` gates debug-only tools such as
/// the Calibrate card.
enum GeneralSettings {
    static let debugKey = "debug.enabled"
    static let defaultDebug = false
}

enum Ao5Settings {
    static let feedbackKey = "ao5.feedback"
    static let intervalKey = "ao5.feedbackInterval"
    static let stepKey = "ao5.crownStep"
    static let accelKey = "ao5.accelLevel"
    static let stepsKey = "ao5.stepsPerRev"
    static let unitsKey = "ao5.unitsPerRev"
    static let accel1Key = "ao5.accelT1"
    static let accel2Key = "ao5.accelT2"
    static let accel3Key = "ao5.accelT3"

    static let defaultFeedback = true
    static let defaultInterval = 10
    static let defaultStep = 1
    static let defaultAccel = Ao5Accel.gentle.rawValue
    static let defaultSteps = Ao5CrownMapper.defaultStepsPerRev
    static let defaultUnits = Int(Ao5CrownMapper.defaultUnitsPerRev)
    static let defaultAccel1 = 25
    static let defaultAccel2 = 60
    static let defaultAccel3 = 130

    static let intervalRange = 1...1000
    static let stepRange = 1...100
    static let stepsRange = 10...2000
    static let unitsRange = 100...1500
    static let accelRange = 1...1000

    struct Snapshot {
        var feedback = defaultFeedback
        var interval = defaultInterval
        var step = defaultStep
        var accel = Ao5Accel.gentle
        var stepsPerRev = defaultSteps
        var unitsPerRev = Double(defaultUnits)
        var accelThresholds = (Double(defaultAccel1), Double(defaultAccel2), Double(defaultAccel3))
    }

    private static func int(_ d: UserDefaults, _ key: String, _ def: Int, _ range: ClosedRange<Int>) -> Int {
        guard d.object(forKey: key) != nil else { return def }
        return min(max(d.integer(forKey: key), range.lowerBound), range.upperBound)
    }

    static func load() -> Snapshot {
        let d = UserDefaults.standard
        var s = Snapshot()
        if d.object(forKey: feedbackKey) != nil { s.feedback = d.bool(forKey: feedbackKey) }
        s.interval = int(d, intervalKey, defaultInterval, intervalRange)
        s.step = int(d, stepKey, defaultStep, stepRange)
        if d.object(forKey: accelKey) != nil {
            s.accel = Ao5Accel(rawValue: d.integer(forKey: accelKey)) ?? .gentle
        }
        s.stepsPerRev = int(d, stepsKey, defaultSteps, stepsRange)
        s.unitsPerRev = Double(int(d, unitsKey, defaultUnits, unitsRange))
        let t1 = int(d, accel1Key, defaultAccel1, accelRange)
        let t2 = max(t1, int(d, accel2Key, defaultAccel2, accelRange))
        let t3 = max(t2, int(d, accel3Key, defaultAccel3, accelRange))
        s.accelThresholds = (Double(t1), Double(t2), Double(t3))
        return s
    }

    /// Removes every Ao5 key so all defaults apply.
    static func resetToDefaults() {
        let d = UserDefaults.standard
        for k in [feedbackKey, intervalKey, stepKey, accelKey, stepsKey, unitsKey,
                  accel1Key, accel2Key, accel3Key] {
            d.removeObject(forKey: k)
        }
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
    @AppStorage(Ao5Settings.unitsKey) private var units = Ao5Settings.defaultUnits
    @AppStorage(Ao5Settings.accel1Key) private var accel1 = Ao5Settings.defaultAccel1
    @AppStorage(Ao5Settings.accel2Key) private var accel2 = Ao5Settings.defaultAccel2
    @AppStorage(Ao5Settings.accel3Key) private var accel3 = Ao5Settings.defaultAccel3

    @AppStorage(GeneralSettings.debugKey) private var debug = GeneralSettings.defaultDebug

    var body: some View {
        Form {
            Section("Ao5") {
                Stepper(value: $step, in: Ao5Settings.stepRange) {
                    Text("Crown speed \(step) ms")
                }
                Stepper(value: $stepsPerRev, in: Ao5Settings.stepsRange, step: 10) {
                    Text("Steps per rev \(stepsPerRev)")
                }
                Stepper(value: $units, in: Ao5Settings.unitsRange, step: 10) {
                    Text("Units per rev \(units)")
                }
                Picker("Acceleration", selection: $accel) {
                    ForEach(Ao5Accel.allCases) { a in
                        Text(a.title).tag(a.rawValue)
                    }
                }
                if accel == Ao5Accel.custom.rawValue {
                    Stepper(value: $accel1, in: Ao5Settings.accelRange) {
                        Text("10 ms from \(accel1)/s")
                    }
                    Stepper(value: $accel2, in: Ao5Settings.accelRange) {
                        Text("100 ms from \(accel2)/s")
                    }
                    Stepper(value: $accel3, in: Ao5Settings.accelRange) {
                        Text("1 s from \(accel3)/s")
                    }
                }
                Toggle("Crown feedback", isOn: $feedback)
                if feedback {
                    Stepper(value: $interval, in: Ao5Settings.intervalRange) {
                        Text("Feedback every \(interval) ms")
                    }
                }
                Button("Reset to defaults", role: .destructive) {
                    Ao5Settings.resetToDefaults()
                    feedback = Ao5Settings.defaultFeedback
                    interval = Ao5Settings.defaultInterval
                    step = Ao5Settings.defaultStep
                    accel = Ao5Settings.defaultAccel
                    stepsPerRev = Ao5Settings.defaultSteps
                    units = Ao5Settings.defaultUnits
                    accel1 = Ao5Settings.defaultAccel1
                    accel2 = Ao5Settings.defaultAccel2
                    accel3 = Ao5Settings.defaultAccel3
                }
            }
            Section("Developer") {
                Toggle("Debug mode", isOn: $debug)
            }
        }
        .navigationTitle("Customization")
    }
}
