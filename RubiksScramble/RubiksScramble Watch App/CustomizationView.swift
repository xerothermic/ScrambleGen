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
    static let intervalKey = "ao5.feedbackInterval2"  // v2: unit changed ms -> cs in build 80; old stored values ignored
    static let stepKey = "ao5.crownStep2"  // v2: old values (ms meaning) ignored; default 1
    static let accelKey = "ao5.accelLevel"
    static let stepsKey = "ao5.stepsPerRev"
    static let unitsKey = "ao5.unitsPerRev"
    static let accel1Key = "ao5.accelT1"

    static let defaultFeedback = true
    static let defaultInterval = 1
    static let defaultStep = 1
    static let defaultAccel = Ao5Accel.gentle.rawValue
    static let defaultSteps = Ao5CrownMapper.defaultStepsPerRev
    static let defaultUnits = Int(Ao5CrownMapper.defaultUnitsPerRev)
    static let defaultAccel1 = 25

    static let intervalRange = 1...100
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
        var accelThreshold = Double(defaultAccel1)
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
        s.accelThreshold = Double(int(d, accel1Key, defaultAccel1, accelRange))
        return s
    }

    /// Removes every Ao5 key so all defaults apply.
    static func resetToDefaults() {
        let d = UserDefaults.standard
        for k in ["ao5.feedbackInterval", "ao5.crownStep", feedbackKey, intervalKey, stepKey, accelKey, stepsKey, unitsKey,
                  accel1Key, "ao5.accelT2", "ao5.accelT3"] {   // T2/T3: removed x100/x1000 tiers, cleaned up
            d.removeObject(forKey: k)
        }
    }
}

/// Compact tunable row: caption label, then "-  value unit  +" on one line.
/// Fits 41/45/49 mm without truncation (single-line, scales down if needed).
struct TuneRow: View {
    let label: String
    let unit: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int

    init(_ label: String, unit: String = "", value: Binding<Int>,
         range: ClosedRange<Int>, step: Int = 1) {
        self.label = label
        self.unit = unit
        self._value = value
        self.range = range
        self.step = step
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            HStack(spacing: 4) {
                Button { value = max(range.lowerBound, value - step) } label: {
                    Image(systemName: "minus").font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(value <= range.lowerBound)
                Text(unit.isEmpty ? "\(value)" : "\(value) \(unit)")
                    .font(.system(size: 12).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity)
                Button { value = min(range.upperBound, value + step) } label: {
                    Image(systemName: "plus").font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(value >= range.upperBound)
            }
        }
        .padding(.vertical, 0)
        .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
    }
}

/// Small section header (the default watchOS header font is large).
private func sectionHeader(_ title: String) -> some View {
    Text(title).font(.system(size: 10, weight: .semibold)).textCase(nil)
}

/// Acceleration row: same control type as TuneRow ('<' and '>' bordered buttons around the mode name).
/// Replaces the NavigationLink/Button-with-HStack-label row that did not respond on device (builds 82/83).
struct AccelRow: View {
    @Binding var selection: Int

    var body: some View {
        let mode = Ao5Accel(rawValue: selection) ?? .gentle
        VStack(alignment: .leading, spacing: 2) {
            Text("Acceleration")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Button {
                    selection = mode.cycled(by: -1).rawValue
                    DebugLog.log("tap accel <")
                } label: {
                    Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                Text(mode.title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                Button {
                    selection = mode.cycled(by: 1).rawValue
                    DebugLog.log("tap accel >")
                } label: {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
        .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
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

    @AppStorage(GeneralSettings.debugKey) private var debug = GeneralSettings.defaultDebug

    var body: some View {
        Form {
            Section {
                TuneRow("Crown speed", value: $step, range: Ao5Settings.stepRange, step: 1)
                TuneRow("Steps per rev", unit: "", value: $stepsPerRev, range: Ao5Settings.stepsRange, step: 10)
                TuneRow("Units per rev", unit: "", value: $units, range: Ao5Settings.unitsRange, step: 10)
                AccelRow(selection: $accel)
                if accel == Ao5Accel.custom.rawValue {
                    TuneRow("x10 from", unit: "/s", value: $accel1, range: Ao5Settings.accelRange, step: 1)
                }
                Toggle(isOn: $feedback) { Text("Crown feedback").font(.system(size: 11)) }
                    .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
                if feedback {
                    TuneRow("Feedback every", value: $interval, range: Ao5Settings.intervalRange, step: 1)
                }
                Button(role: .destructive) {
                    DebugLog.log("tap Reset")
                    Ao5Settings.resetToDefaults()
                    feedback = Ao5Settings.defaultFeedback
                    interval = Ao5Settings.defaultInterval
                    step = Ao5Settings.defaultStep
                    accel = Ao5Settings.defaultAccel
                    stepsPerRev = Ao5Settings.defaultSteps
                    units = Ao5Settings.defaultUnits
                    accel1 = Ao5Settings.defaultAccel1
                } label: {
                    Text("Reset to defaults").font(.system(size: 11))
                }
                .controlSize(.mini)
                .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
            } header: {
                sectionHeader("Ao5")
            }
            Section {
                Toggle(isOn: $debug) { Text("Debug mode").font(.system(size: 11)) }
                    .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
                    .logTap("debug toggle")
            } header: {
                sectionHeader("Developer")
            }
        }
        .font(.system(size: 11))
        .navigationTitle("Customization")
        .onAppear { DebugLog.log("Customization appeared (container drags gated off)") }
        .onChange(of: step) { DebugLog.setting("step", $0, $1) }
        .onChange(of: stepsPerRev) { DebugLog.setting("stepsPerRev", $0, $1) }
        .onChange(of: units) { DebugLog.setting("units", $0, $1) }
        .onChange(of: accel) { DebugLog.setting("accel", $0, $1) }
        .onChange(of: accel1) { DebugLog.setting("accel1", $0, $1) }
        .onChange(of: interval) { DebugLog.setting("interval", $0, $1) }
        .onChange(of: feedback) { DebugLog.setting("feedback", $0, $1) }
        .onChange(of: debug) { DebugLog.setting("debug", $0, $1) }
    }
}
