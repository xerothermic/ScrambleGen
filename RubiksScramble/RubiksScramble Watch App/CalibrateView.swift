import SwiftUI
import WatchKit

// TEMPORARY: Calibrate card, a Digital Crown measuring tool. Remove the card
// (ContentView) and this file once steps-per-revolution is calibrated.

enum CalibrateCard {
    static let id = "calibrate"
    static let color = Color(red: 0.90, green: 0.45, blue: 0.10)
}

/// Raw crown statistics. Observation tracks per-property reads, so only the
/// small stats view re-renders on a crown event.
@Observable
final class CrownProbe {
    private(set) var raw = 0.0
    private(set) var delta = 0.0
    private(set) var events = 0
    private(set) var minAbs = 0.0          // smallest nonzero |delta|
    private(set) var maxAbs = 0.0
    private(set) var meanAbs = 0.0
    private(set) var travel = 0.0          // signed
    private(set) var absTravel = 0.0
    private(set) var rate = 0.0            // events per second (smoothed)
    private(set) var lastEvent = 0.0       // systemUptime of last event
    // Marks (one-revolution measurement).
    private(set) var markRaw: Double?
    private(set) var markEvents = 0
    private(set) var revUnits: Double?
    private(set) var revEvents: Int?

    private var prev: Double?

    func record(_ value: Double) {
        let now = ProcessInfo.processInfo.systemUptime
        defer { prev = value; raw = value }
        guard let p = prev else { return }
        let d = value - p
        guard d != 0 else { return }
        delta = d
        events += 1
        let a = abs(d)
        if minAbs == 0 || a < minAbs { minAbs = a }
        if a > maxAbs { maxAbs = a }
        meanAbs += (a - meanAbs) / Double(events)
        travel += d
        absTravel += a
        if lastEvent > 0, now > lastEvent {
            let inst = 1 / (now - lastEvent)
            rate = rate == 0 ? inst : rate * 0.7 + inst * 0.3
        }
        lastEvent = now
    }

    func reset() {
        delta = 0; events = 0; minAbs = 0; maxAbs = 0; meanAbs = 0
        travel = 0; absTravel = 0; rate = 0; lastEvent = 0
        markRaw = nil; markEvents = 0; revUnits = nil; revEvents = nil
    }

    func mark() {
        if let start = markRaw {
            revUnits = abs(raw - start)
            revEvents = events - markEvents
            markRaw = nil
        } else {
            markRaw = raw
            markEvents = events
            revUnits = nil
            revEvents = nil
        }
    }

    var marking: Bool { markRaw != nil }
}

private struct CrownStats: View {
    let probe: CrownProbe
    let stepsPerRev: Int

    private func f(_ v: Double) -> String { String(format: "%.6f", v) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("raw   \(f(probe.raw))")
            Text("delta \(f(probe.delta))")
            Text("min|d| \(f(probe.minAbs))")
            Text("max|d| \(f(probe.maxAbs))")
            Text("mean|d| \(f(probe.meanAbs))")
            Text("events \(probe.events)  \(String(format: "%.0f", probe.rate))/s")
            Text("travel \(f(probe.travel))")
            Text("abs    \(f(probe.absTravel))")
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                let idle = probe.lastEvent > 0
                    ? ProcessInfo.processInfo.systemUptime - probe.lastEvent : 0
                Text("idle \(String(format: "%.2f", idle)) s")
            }
            if probe.marking {
                Text("MARKED: turn 1 rev, tap Mark")
            } else if let u = probe.revUnits, let e = probe.revEvents {
                Text("rev \(f(u)) units, \(e) ev")
                Text("= \(String(format: "%.1f", u / Ao5CrownMapper.unitsPerRev * Double(stepsPerRev))) steps at \(stepsPerRev)/rev")
            } else {
                Text("map \(String(format: "%.0f", Ao5CrownMapper.unitsPerRev)) u/rev, \(stepsPerRev) steps")
            }
        }
        .font(.system(size: 9, design: .monospaced))
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CalibrateScreen: View {
    @State private var probe = CrownProbe()
    @State private var crown = 0.0
    @FocusState private var focused: Bool
    @State private var stepsPerRev = Ao5Settings.load().stepsPerRev

    var body: some View {
        VStack(spacing: 3) {
            CrownStats(probe: probe, stepsPerRev: stepsPerRev)
                .focusable()
                .focused($focused)
                .digitalCrownRotation($crown, from: -1_000_000, through: 1_000_000, by: nil,
                                      sensitivity: .high, isContinuous: true,
                                      isHapticFeedbackEnabled: false)
                .onChange(of: crown) { _, new in probe.record(new) }
            HStack(spacing: 4) {
                Button { probe.mark(); WKInterfaceDevice.current().play(.click) } label: {
                    Text("Mark")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 26)
                        .background(Capsule().fill(CalibrateCard.color))
                }
                .buttonStyle(.plain)
                Button { probe.reset() } label: {
                    Text("Reset")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 26)
                        .background(Capsule().fill(Color.white.opacity(0.2)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
        .navigationTitle("")
        .onAppear {
            focused = true
            stepsPerRev = Ao5Settings.load().stepsPerRev
        }
    }
}
