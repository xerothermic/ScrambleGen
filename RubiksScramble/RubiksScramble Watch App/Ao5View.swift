import SwiftUI
import WatchKit

/// Card identity (matched-geometry id and tint) for the card stack.
enum Ao5Card {
    static let id = "ao5"
    static let color = Color(red: 0.55, green: 0.25, blue: 0.80)
}

/// Average-of-5 calculator: type five competition times, get the WCA Ao5.
/// Its own top-level card in the card stack (`Ao5Card`).
/// Times are typed like a stopwatch: digits shift in from the right, so 1 2 3 4
/// reads 12.34 and 1 0 2 3 4 reads 1:02.34. Per solve: +2 and DNF toggles.
/// Nothing is saved; leaving the screen discards the entries.
struct Ao5Screen: View {
    /// The five solves; nil = not entered yet.
    @State private var entries: [Ao5Solve?] = Array(repeating: nil, count: AverageOfFive.count)
    /// Index being entered; nil = showing the result.
    @State private var current: Int? = 0
    @State private var digits = ""
    @State private var penalty: Ao5Penalty = .none

    private static let maxDigits = 6

    private var canConfirm: Bool {
        penalty == .dnf || AverageOfFive.centis(fromDigits: digits) > 0
    }

    private var solves: [Ao5Solve]? {
        let all = entries.compactMap { $0 }
        return all.count == AverageOfFive.count ? all : nil
    }

    // MARK: Actions

    private func tap(_ digit: String) {
        guard digits.count < Self.maxDigits else { return }
        if digits.isEmpty && digit == "0" { return }
        digits += digit
        WKInterfaceDevice.current().play(.click)
    }

    private func backspace() {
        guard !digits.isEmpty else { return }
        digits.removeLast()
        WKInterfaceDevice.current().play(.click)
    }

    private func toggle(_ p: Ao5Penalty) {
        penalty = penalty == p ? .none : p
        WKInterfaceDevice.current().play(.click)
    }

    private func confirm() {
        guard let i = current, canConfirm else { return }
        entries[i] = Ao5Solve(centis: AverageOfFive.centis(fromDigits: digits),
                              penalty: penalty)
        advance()
        WKInterfaceDevice.current().play(current == nil ? .success : .directionUp)
    }

    /// Goes to the first solve not entered yet, or to the result.
    private func advance() {
        if let next = entries.firstIndex(where: { $0 == nil }) {
            load(next)
        } else {
            current = nil
        }
    }

    /// Opens solve `i` for entry (fresh or to edit).
    private func load(_ i: Int) {
        current = i
        if let s = entries[i] {
            digits = s.centis > 0 ? String(s.centis) : ""
            penalty = s.penalty
        } else {
            digits = ""
            penalty = .none
        }
    }

    private func restart() {
        entries = Array(repeating: nil, count: AverageOfFive.count)
        load(0)
    }

    // MARK: Entry

    private func keyButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.15)))
        }
        .buttonStyle(.plain)
    }

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

    private func entryView(index: Int) -> some View {
        let centis = AverageOfFive.centis(fromDigits: digits)
        return ScrollView {
            VStack(spacing: 6) {
                Text("Solve \(index + 1) of \(AverageOfFive.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(penalty == .dnf ? "DNF" : AverageOfFive.format(centis))
                    .font(.system(size: 34, weight: .bold, design: .monospaced))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(digits.isEmpty && penalty != .dnf ? Color.secondary
                                                                       : Color.white)
                HStack(spacing: 6) {
                    penaltyButton("+2", .plus2)
                    penaltyButton("DNF", .dnf)
                }
                VStack(spacing: 4) {
                    ForEach([["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]], id: \.self) { row in
                        HStack(spacing: 4) {
                            ForEach(row, id: \.self) { d in keyButton(d) { tap(d) } }
                        }
                    }
                    HStack(spacing: 4) {
                        Button { backspace() } label: {
                            Image(systemName: "delete.left")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity, minHeight: 34)
                                .background(RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.white.opacity(0.15)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Delete digit")
                        keyButton("0") { tap("0") }
                        Button { confirm() } label: {
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 34)
                                .background(RoundedRectangle(cornerRadius: 8)
                                    .fill(canConfirm ? Color.accentColor
                                                     : Color.white.opacity(0.15)))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canConfirm)
                        .accessibilityLabel(index == AverageOfFive.count - 1 ? "Done" : "Next")
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: Result

    private func resultView(_ solves: [Ao5Solve]) -> some View {
        let result = AverageOfFive.compute(solves)
        return ScrollView {
            VStack(spacing: 6) {
                Text("Average of 5")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(AverageOfFive.format(result?.averageCentis))
                    .font(.system(size: 40, weight: .bold, design: .monospaced))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text("Best \(AverageOfFive.format(result?.bestCentis))")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)

                VStack(spacing: 2) {
                    ForEach(solves.indices, id: \.self) { i in
                        let dropped = result?.dropped.contains(i) ?? false
                        Button { load(i) } label: {
                            HStack {
                                Text("\(i + 1)")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(AverageOfFive.label(solves[i], parenthesized: dropped))
                                    .foregroundStyle(dropped ? Color.secondary : Color.white)
                            }
                            .font(.system(size: 14, design: .monospaced))
                            .padding(.vertical, 3)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 6)
                Text("Tap a time to edit. (x) = dropped.")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)

                Button { restart() } label: {
                    Text("New average")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 4)
        }
    }

    var body: some View {
        Group {
            if let i = current {
                entryView(index: i)
            } else if let all = solves {
                resultView(all)
            }
        }
        .modifier(CloseAwareTitle(title: "Ao5"))
    }
}
