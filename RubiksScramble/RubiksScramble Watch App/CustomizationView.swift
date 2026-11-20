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
    /// Beta features (Algorithms card, Clock scrambles, Premium history/stats/
    /// motion insights): unpolished, hidden unless this is on.
    // v2 key: everyone starts with beta off again (a stored "on" under the old key is ignored).
    static let betaKey = "beta.enabled2"
    static let defaultBeta = false
    /// Hide the system time of day (top right of the navigation bar) where the
    /// API allows: `.toolbar(.hidden, for: .navigationBar)` via `HideTimeModifier`.
    static let hideTimeKey = "display.hideTime"
    static let defaultHideTime = false
    /// Orientation pill above the scramble ("White top · Green front" for 3x3,
    /// the notation hints for Square-1 and Clock). Shared by all puzzles.
    static let hintKey = "scramble.orientationHint"
    static let defaultHint = false
    /// Shake the watch on the scramble screen for a new scramble.
    static let shakeKey = "scramble.shakeNew"
    static let defaultShake = false
    /// 3x3 map page as a live 3D cube rotated by the gyroscope.
    static let cube3DKey = "map.cube3DGyro"
    static let defaultCube3D = false
    /// 3D cube follows wrist tilt (finger drag always works).
    static let cube3DTiltKey = "map.cube3DTilt"
    static let defaultCube3DTilt = true
}

enum Ao5Settings {
    static let feedbackKey = "ao5.feedback"
    static let intervalKey = "ao5.feedbackInterval2"  // v2: unit changed ms -> cs in build 80; old stored values ignored
    static let stepKey = "ao5.crownStep2"  // v2: old values (ms meaning) ignored; default 1
    static let accelKey = "ao5.accelLevel"
    static let stepsKey = "ao5.stepsPerRev"
    static let unitsKey = "ao5.unitsPerRev"
    static let accel1Key = "ao5.accelT1v2"   // v2: scale changed in build 86 (150 detents = 1 rev); old low values (25) ignored

    static let defaultFeedback = true
    static let defaultInterval = 1
    static let defaultStep = 1
    static let defaultAccel = Ao5Accel.gentle.rawValue
    static let defaultSteps = Ao5CrownMapper.defaultStepsPerRev
    static let defaultUnits = Int(Ao5CrownMapper.defaultUnitsPerRev)
    static let defaultAccel1 = Int(Ao5CrownMapper.defaultCustomThreshold)

    static let intervalRange = 1...100
    static let stepRange = 1...100
    static let stepsRange = 10...2000
    static let unitsRange = 100...1500
    static let accelRange = 10...2000

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

    /// Crown speed tuning was removed from Customization: only feedback settings are read; speed always uses defaults.
    static func load() -> Snapshot {
        let d = UserDefaults.standard
        var s = Snapshot()
        if d.object(forKey: feedbackKey) != nil { s.feedback = d.bool(forKey: feedbackKey) }
        s.interval = int(d, intervalKey, defaultInterval, intervalRange)
        return s
    }

    /// Removes every Ao5 key so all defaults apply.
    static func resetToDefaults() {
        let d = UserDefaults.standard
        for k in ["ao5.feedbackInterval", "ao5.crownStep", "ao5.accelT1", feedbackKey, intervalKey, stepKey, accelKey, stepsKey, unitsKey,
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

/// Hides the navigation bar (title, time of day) when Customization > Display >
/// "Hide time" is on. Apply INSIDE a NavigationStack. `when` lets a screen keep
/// the bar while it needs the bar's toolbar buttons.
struct HideTimeModifier: ViewModifier {
    var when = true
    @AppStorage(GeneralSettings.hideTimeKey) private var hideTime = GeneralSettings.defaultHideTime
    func body(content: Content) -> some View {
        content.toolbar(hideTime && when ? .hidden : .automatic, for: .navigationBar)
    }
}

extension View {
    func hidingTime(when: Bool = true) -> some View { modifier(HideTimeModifier(when: when)) }
}

/// Settings screen: one Section per feature, so adding a feature = adding a
/// Section here (and its keys above).
struct CustomizationScreen: View {
    @AppStorage(Ao5Settings.feedbackKey) private var feedback = Ao5Settings.defaultFeedback
    @AppStorage(Ao5Settings.intervalKey) private var interval = Ao5Settings.defaultInterval

    @AppStorage(GeneralSettings.debugKey) private var debug = GeneralSettings.defaultDebug
    @AppStorage(GeneralSettings.betaKey) private var beta = GeneralSettings.defaultBeta
    @AppStorage(GeneralSettings.hideTimeKey) private var hideTime = GeneralSettings.defaultHideTime
    @AppStorage(GeneralSettings.hintKey) private var hint = GeneralSettings.defaultHint
    @AppStorage(GeneralSettings.shakeKey) private var shakeNew = GeneralSettings.defaultShake
    @AppStorage(GeneralSettings.cube3DKey) private var cube3D = GeneralSettings.defaultCube3D
    @AppStorage(GeneralSettings.cube3DTiltKey) private var cube3DTilt = GeneralSettings.defaultCube3DTilt
    @AppStorage(ScrambleSource.randomStateKey) private var randomState = ScrambleSource.defaultRandomState
    @AppStorage(ScrambleSource.square1RandomStateKey) private var square1RandomState = ScrambleSource.defaultSquare1RandomState

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $hideTime) { Text("Hide time").font(.system(size: 11)) }
                    .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
                    .logTap("hide time toggle")
            } header: {
                sectionHeader("Display")
            }
            Section {
                Toggle(isOn: $hint) { Text("Orientation hint").font(.system(size: 11)) }
                    .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
                    .logTap("hint toggle")
                Toggle(isOn: $shakeNew) { Text("Shake for new scramble").font(.system(size: 11)) }
                    .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
                    .logTap("shake toggle")
                Toggle(isOn: $cube3D) { Text("3D cube / Sq-1 map").font(.system(size: 11)) }
                    .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
                    .logTap("3d toggle")
                Toggle(isOn: $cube3DTilt) { Text("3D: tilt wrist").font(.system(size: 11)) }
                    .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
                    .logTap("3d tilt toggle")
            } header: {
                sectionHeader("Scramble")
            }
            Section {
                Toggle(isOn: $randomState) { Text("3x3 random-state").font(.system(size: 11)) }
                    .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
                    .onChange(of: randomState) { _, on in
                        if on { ScrambleSource.prewarm() }
                    }
            } header: {
                sectionHeader("3x3 scramble")
            }
            Section {
                Toggle(isOn: $square1RandomState) { Text("Square-1 random-state").font(.system(size: 11)) }
                    .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
                    .onChange(of: square1RandomState) { _, on in
                        if on { ScrambleSource.prewarmSquare1() }
                    }
            } header: {
                sectionHeader("Square-1 scramble")
            }
            Section {
                Toggle(isOn: $feedback) { Text("Crown feedback").font(.system(size: 11)) }
                    .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
                if feedback {
                    TuneRow("Feedback every", value: $interval, range: Ao5Settings.intervalRange, step: 1)
                }
            } header: {
                sectionHeader("Ao5")
            }
            Section {
                Toggle(isOn: $debug) { Text("Debug mode").font(.system(size: 11)) }
                    .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
                    .logTap("debug toggle")
                Toggle(isOn: $beta) { Text("Beta features").font(.system(size: 11)) }
                    .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
                    .logTap("beta toggle")
            } header: {
                sectionHeader("Developer")
            }
        }
        .font(.system(size: 11))
        .navigationTitle("Customization")
        .onAppear { DebugLog.log("Customization appeared (container drags gated off)") }
        .onChange(of: interval) { DebugLog.setting("interval", $0, $1) }
        .onChange(of: feedback) { DebugLog.setting("feedback", $0, $1) }
        .onChange(of: debug) { DebugLog.setting("debug", $0, $1) }
        .onChange(of: beta) { DebugLog.setting("beta", $0, $1) }
        .onChange(of: hint) { DebugLog.setting("hint", $0, $1) }
        .onChange(of: shakeNew) { DebugLog.setting("shakeNew", $0, $1) }
        .onChange(of: cube3D) { DebugLog.setting("cube3D", $0, $1) }
        .onChange(of: cube3DTilt) { DebugLog.setting("cube3DTilt", $0, $1) }
    }
}
