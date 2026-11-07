import SwiftUI
import WatchKit

/// Card identity (matched-geometry id and tint) for the card stack.
enum Ao5Card {
    static let id = "ao5"
    static let color = Color(red: 0.55, green: 0.25, blue: 0.80)
}

/// Average-of-5 calculator: set five competition times, get the WCA Ao5.
/// Its own top-level card in the card stack (`Ao5Card`).
/// The Digital Crown dials the time (0.01 s steps; a fast spin jumps 0.10 s per
/// step). Tapping a slot selects that solve (loading its time if already set);
/// "Set" stores the dialled time, with the +2 / DNF toggles, in the selected
/// slot and moves on to the next empty one. The best single and the average
/// (once all five are set) update live. Nothing is saved; leaving the screen
/// discards the entries.
struct Ao5Screen: View {
    /// The five solves; nil = not set yet.
    @State private var entries: [Ao5Solve?] = Array(repeating: nil, count: AverageOfFive.count)
    /// Selected slot (0...4).
    @State private var selected = 0
    /// Dialled time in centiseconds, and the pending penalty.
    @State private var centis = 0
    @State private var penalty: Ao5Penalty = .none
    /// Raw Digital Crown position; only its changes matter (see applyCrown).
    @State private var crown = Self.crownMid
    @FocusState private var crownFocused: Bool

    private static let crownMid = 500_000.0
    private static let maxCentis = 59 * 6000 + 5999   // 59:59.99

    private var canSet: Bool { penalty == .dnf || centis > 0 }

    private var allSet: [Ao5Solve]? {
        let all = entries.compactMap { $0 }
        return all.count == AverageOfFive.count ? all : nil
    }

    private var result: Ao5Result? { allSet.flatMap { AverageOfFive.compute($0) } }

    private var best: Int? {
        entries.compactMap { $0?.effectiveCentis }.min()
    }

    // MARK: Actions

    /// Crown detents arrive as changes in `crown`: 1 detent = 0.01 s, a fast
    /// spin (3+ detents at once) = 0.10 s per detent.
    private func applyCrown(from old: Double, to new: Double) {
        let d = Int((new - old).rounded())
        guard d != 0 else { return }
        let step = abs(d) >= 3 ? d * 10 : d
        centis = min(max(centis + step, 0), Self.maxCentis)
    }

    private func toggle(_ p: Ao5Penalty) {
        penalty = penalty == p ? .none : p
        WKInterfaceDevice.current().play(.click)
    }

    private func select(_ i: Int) {
        selected = i
        if let s = entries[i] {
            centis = s.centis
            penalty = s.penalty
        } else {
            penalty = .none
        }
        WKInterfaceDevice.current().play(.click)
    }

    private func setCurrent() {
        guard canSet else { return }
        entries[selected] = Ao5Solve(centis: centis, penalty: penalty)
        WKInterfaceDevice.current().play(.success)
        // Next empty slot after this one (wrapping); stay put when all are set.
        let n = AverageOfFive.count
        if let next = (1..<n).map({ (selected + $0) % n }).first(where: { entries[$0] == nil }) {
            selected = next
            centis = 0
            penalty = .none
        }
    }

    private func restart() {
        entries = Array(repeating: nil, count: AverageOfFive.count)
        selected = 0
        centis = 0
        penalty = .none
    }

    // MARK: Views

    private func penaltyButton(_ title: String, _ p: Ao5Penalty) -> some View {
        Button { toggle(p) } label: {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(penalty == p ? Color.white : Color.secondary)
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(Capsule().fill(penalty == p ? Color.accentColor
                                                         : Color.white.opacity(0.15)))
        }
        .buttonStyle(.plain)
    }

    private var summary: some View {
        let count = entries.compactMap { $0 }.count
        return VStack(spacing: 1) {
            Text(allSet != nil ? "Average of 5" : "Average of 5 (\(count)/\(AverageOfFive.count))")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(allSet != nil ? AverageOfFive.format(result?.averageCentis) : "--")
                .font(.system(size: 30, weight: .bold, design: .monospaced))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(best != nil ? "Best \(AverageOfFive.format(best))" : "Best --")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private var dial: some View {
        VStack(spacing: 4) {
            Text("Solve \(selected + 1): turn the crown")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(penalty == .dnf ? "DNF" : AverageOfFive.format(centis))
                .font(.system(size: 34, weight: .bold, design: .monospaced))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(centis == 0 && penalty != .dnf ? Color.secondary : Color.white)
            HStack(spacing: 6) {
                penaltyButton("+2", .plus2)
                penaltyButton("DNF", .dnf)
            }
            Button { setCurrent() } label: {
                Text("Set")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background(Capsule().fill(canSet ? Color.accentColor
                                                      : Color.white.opacity(0.15)))
            }
            .buttonStyle(.plain)
            .disabled(!canSet)
        }
    }

    private var slots: some View {
        VStack(spacing: 2) {
            ForEach(0..<AverageOfFive.count, id: \.self) { i in
                let dropped = result?.dropped.contains(i) ?? false
                Button { select(i) } label: {
                    HStack {
                        Text("\(i + 1)")
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let s = entries[i] {
                            Text(AverageOfFive.label(s, parenthesized: dropped))
                                .foregroundStyle(dropped ? Color.secondary : Color.white)
                        } else {
                            Text("--").foregroundStyle(.secondary)
                        }
                    }
                    .font(.system(size: 14, design: .monospaced))
                    .padding(.vertical, 3)
                    .padding(.horizontal, 8)
                    .background(RoundedRectangle(cornerRadius: 6)
                        .fill(i == selected ? Color.white.opacity(0.22) : Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Text("Tap a slot to select it. (x) = dropped.")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                summary
                dial
                slots
                Button { restart() } label: {
                    Text("New average")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 4)
        }
        .focusable()
        .focused($crownFocused)
        .digitalCrownRotation($crown, from: 0, through: Self.crownMid * 2, by: 1,
                              sensitivity: .high, isContinuous: false,
                              isHapticFeedbackEnabled: true)
        .onChange(of: crown) { old, new in applyCrown(from: old, to: new) }
        .onAppear { crownFocused = true }
        .modifier(CloseAwareTitle(title: "Ao5"))
    }
}
