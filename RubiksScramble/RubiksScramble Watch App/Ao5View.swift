import SwiftUI
import WatchKit

/// Card identity (matched-geometry id and tint) for the card stack.
enum Ao5Card {
    static let id = "ao5"
    static let color = Color(red: 0.55, green: 0.25, blue: 0.80)
}

/// Dialled time + pending penalty. Observation tracks per-property reads, so
/// only the small views that read these re-render on a crown tick; the
/// Ao5Screen body never reads them (it uses them imperatively).
@Observable
final class Ao5Dial {
    private(set) var millis = 0
    private(set) var penalty: Ao5Penalty = .none
    /// Stored (not computed) so the Set button only re-renders when it flips.
    private(set) var canSet = false

    static let maxMillis = 59 * 60_000 + 59_999   // 59:59.999

    func set(millis c: Int, penalty p: Ao5Penalty) {
        let cc = min(max(c, 0), Self.maxMillis)
        if cc != millis { millis = cc }
        if p != penalty { penalty = p }
        let can = p == .dnf || cc > 0
        if can != canSet { canSet = can }
    }

    /// Crown step. Plays ONE haptic tick when the value crosses a multiple of
    /// 0.5 s in either direction (integer compare of millis / 500; a fast
    /// spin that crosses several still ticks once). No allocations.
    func add(_ delta: Int) {
        let old = millis
        set(millis: millis + delta, penalty: penalty)
        if old / Self.tickMillis != millis / Self.tickMillis {
            WKInterfaceDevice.current().play(.click)
        }
    }

    static let tickMillis = 500

    func toggle(_ p: Ao5Penalty) { set(millis: millis, penalty: penalty == p ? .none : p) }
}

/// The dialled time. Owns the Digital Crown binding so that a crown tick
/// invalidates only this one Text, not the whole screen.
private struct Ao5DialTime: View {
    let dial: Ao5Dial
    let selected: Int
    @State private var crown = Ao5DialTime.crownMid
    @FocusState private var focused: Bool

    private static let crownMid = 500_000.0

    var body: some View {
        let dnf = dial.penalty == .dnf
        Text(dnf ? "DNF" : AverageOfFive.format(dial.millis))
            .font(.system(size: 32, weight: .bold, design: .monospaced))
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .foregroundStyle(dial.millis == 0 && !dnf ? Color.secondary : Color.white)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .topLeading) {
                Text("#\(selected + 1)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .focusable()
            .focused($focused)
            .digitalCrownRotation($crown, from: 0, through: Self.crownMid * 2, by: 1,
                                  sensitivity: .high, isContinuous: false,
                                  isHapticFeedbackEnabled: false)
            .onChange(of: crown) { old, new in
                // Half the old sensitivity: 1 detent = 5 ms; a fast spin
                // (3+ detents at once) = 50 ms each.
                let d = Int((new - old).rounded())
                guard d != 0 else { return }
                dial.add(abs(d) >= 3 ? d * 50 : d * 5)
            }
            .onAppear { focused = true }
    }
}

/// +2 / DNF / Set row. Re-renders only when the penalty or canSet changes.
private struct Ao5Actions: View {
    let dial: Ao5Dial
    let onSet: () -> Void

    private func penaltyButton(_ title: String, _ p: Ao5Penalty) -> some View {
        let on = dial.penalty == p
        return Button {
            dial.toggle(p)
            WKInterfaceDevice.current().play(.click)
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(on ? Color.white : Color.secondary)
                .frame(maxWidth: .infinity, minHeight: 28)
                .background(Capsule().fill(on ? Color.accentColor : Color.white.opacity(0.15)))
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        HStack(spacing: 4) {
            penaltyButton("+2", .plus2)
            penaltyButton("DNF", .dnf)
            Button(action: onSet) {
                Text("Set")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .background(Capsule().fill(dial.canSet ? Color.accentColor
                                                           : Color.white.opacity(0.15)))
            }
            .buttonStyle(.plain)
            .disabled(!dial.canSet)
        }
    }
}

/// Average-of-5 calculator: set five competition times, get the WCA Ao5.
/// Its own top-level card in the card stack (`Ao5Card`).
/// The Digital Crown dials the time (5 ms steps; a fast spin jumps 50 ms per
/// step; one haptic tick each time it crosses a multiple of 0.5 s). Tapping a slot selects that solve (loading its time if already set);
/// "Set" stores the dialled time, with the +2 / DNF toggles, in the selected
/// slot and moves on to the next empty one. The best single and the average
/// (once all five are set) update live. Nothing is saved; leaving the screen
/// discards the entries.
///
/// Performance: the dialled value lives in `Ao5Dial` (@Observable) and is read
/// only by `Ao5DialTime` / `Ao5Actions`, so crown ticks never re-evaluate this
/// body. The layout fits without a ScrollView so the crown is not contested.
struct Ao5Screen: View {
    /// The five solves; nil = not set yet.
    @State private var entries: [Ao5Solve?] = Array(repeating: nil, count: AverageOfFive.count)
    /// Selected slot (0...4).
    @State private var selected = 0
    @State private var dial = Ao5Dial()

    private func select(_ i: Int) {
        selected = i
        if let s = entries[i] {
            dial.set(millis: s.millis, penalty: s.penalty)
        } else {
            dial.set(millis: 0, penalty: .none)
        }
        WKInterfaceDevice.current().play(.click)
    }

    private func setCurrent() {
        guard dial.canSet else { return }
        entries[selected] = Ao5Solve(millis: dial.millis, penalty: dial.penalty)
        WKInterfaceDevice.current().play(.success)
        // Next empty slot after this one (wrapping); stay put when all are set.
        let n = AverageOfFive.count
        if let next = (1..<n).map({ (selected + $0) % n }).first(where: { entries[$0] == nil }) {
            selected = next
            dial.set(millis: 0, penalty: .none)
        }
    }

    private func restart() {
        entries = Array(repeating: nil, count: AverageOfFive.count)
        selected = 0
        dial.set(millis: 0, penalty: .none)
    }

    private func summary(result: Ao5Result?) -> some View {
        let count = entries.reduce(0) { $0 + ($1 == nil ? 0 : 1) }
        let best = entries.compactMap { $0?.effectiveMillis }.min()
        let done = result != nil || count == AverageOfFive.count
        return HStack(spacing: 4) {
            Text(done ? AverageOfFive.format(result?.averageMillis)
                      : "Ao5 \(count)/\(AverageOfFive.count)")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
            Spacer(minLength: 0)
            Text(best != nil ? "Best \(AverageOfFive.format(best))" : "Best --")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .minimumScaleFactor(0.5)
        .lineLimit(1)
    }

    private func slot(_ i: Int, dropped: Bool) -> some View {
        Button { select(i) } label: {
            Group {
                if let s = entries[i] {
                    Text(AverageOfFive.label(s, parenthesized: dropped))
                        .foregroundStyle(dropped ? Color.secondary : Color.white)
                } else {
                    Text("--").foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 12, design: .monospaced))
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 24)
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(i == selected ? Color.white.opacity(0.28) : Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        let all = entries.compactMap { $0 }
        let result = all.count == AverageOfFive.count ? AverageOfFive.compute(all) : nil
        VStack(spacing: 3) {
            summary(result: result)
            Ao5DialTime(dial: dial, selected: selected)
            Ao5Actions(dial: dial, onSet: setCurrent)
            Grid(horizontalSpacing: 3, verticalSpacing: 3) {
                GridRow {
                    ForEach(0..<3, id: \.self) { i in
                        slot(i, dropped: result?.dropped.contains(i) ?? false)
                    }
                }
                GridRow {
                    ForEach(3..<5, id: \.self) { i in
                        slot(i, dropped: result?.dropped.contains(i) ?? false)
                    }
                    Button { restart() } label: {
                        Text("New")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 24)
                            .background(RoundedRectangle(cornerRadius: 6)
                                .fill(Color.accentColor.opacity(0.6)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 4)
        .navigationTitle("")   // no title: reclaim the header height
    }
}
