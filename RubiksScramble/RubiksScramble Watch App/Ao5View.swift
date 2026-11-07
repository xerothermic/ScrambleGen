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
    private(set) var centis = 0
    private(set) var penalty: Ao5Penalty = .none
    /// Stored (not computed) so the Set button only re-renders when it flips.
    private(set) var canSet = false

    static let maxCentis = 59 * 6000 + 5999   // 59:59.99

    func set(centis c: Int, penalty p: Ao5Penalty) {
        let cc = min(max(c, 0), Self.maxCentis)
        if cc != centis { centis = cc }
        if p != penalty { penalty = p }
        let can = p == .dnf || cc > 0
        if can != canSet { canSet = can }
    }

    func add(_ delta: Int) { set(centis: centis + delta, penalty: penalty) }

    func toggle(_ p: Ao5Penalty) { set(centis: centis, penalty: penalty == p ? .none : p) }
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
        Text(dnf ? "DNF" : AverageOfFive.format(dial.centis))
            .font(.system(size: 32, weight: .bold, design: .monospaced))
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .foregroundStyle(dial.centis == 0 && !dnf ? Color.secondary : Color.white)
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
                // 1 detent = 0.01 s; a fast spin (3+ detents at once) = 0.10 s each.
                let d = Int((new - old).rounded())
                guard d != 0 else { return }
                dial.add(abs(d) >= 3 ? d * 10 : d)
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
/// The Digital Crown dials the time (0.01 s steps; a fast spin jumps 0.10 s per
/// step). Tapping a slot selects that solve (loading its time if already set);
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
            dial.set(centis: s.centis, penalty: s.penalty)
        } else {
            dial.set(centis: 0, penalty: .none)
        }
        WKInterfaceDevice.current().play(.click)
    }

    private func setCurrent() {
        guard dial.canSet else { return }
        entries[selected] = Ao5Solve(centis: dial.centis, penalty: dial.penalty)
        WKInterfaceDevice.current().play(.success)
        // Next empty slot after this one (wrapping); stay put when all are set.
        let n = AverageOfFive.count
        if let next = (1..<n).map({ (selected + $0) % n }).first(where: { entries[$0] == nil }) {
            selected = next
            dial.set(centis: 0, penalty: .none)
        }
    }

    private func restart() {
        entries = Array(repeating: nil, count: AverageOfFive.count)
        selected = 0
        dial.set(centis: 0, penalty: .none)
    }

    private func summary(result: Ao5Result?) -> some View {
        let count = entries.reduce(0) { $0 + ($1 == nil ? 0 : 1) }
        let best = entries.compactMap { $0?.effectiveCentis }.min()
        let done = result != nil || count == AverageOfFive.count
        return VStack(spacing: 0) {
            Text(done ? AverageOfFive.format(result?.averageCentis)
                      : "Ao5 \(count)/\(AverageOfFive.count)")
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(best != nil ? "Best \(AverageOfFive.format(best))" : "Best --")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
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
        VStack(spacing: 4) {
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
        .modifier(CloseAwareTitle(title: "Ao5"))
    }
}
