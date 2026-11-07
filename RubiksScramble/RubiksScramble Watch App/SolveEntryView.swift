import SwiftUI

/// Constants for the Averages card (Wallet-stack card + the entry screen).
enum AveragesCard {
    static let id = "averages"
    static let color = Color(red: 0.55, green: 0.25, blue: 0.80)

    static let slots = 5
    static let solvesKey = "averageSolves"

    /// Slots saved by an earlier launch; nil = empty slot.
    static func load() -> [SolveTime?] {
        let saved = UserDefaults.standard.stringArray(forKey: solvesKey) ?? []
        var slots = saved.prefix(Self.slots).map { SolveTime(stored: $0) }
        while slots.count < Self.slots { slots.append(nil) }
        return slots
    }

    static func save(_ slots: [SolveTime?]) {
        UserDefaults.standard.set(slots.map { $0?.stored ?? "" }, forKey: solvesKey)
    }
}

/// Five slots for competition solve times, with the Average of 5 (drop best and
/// worst) once all five are in and the Mean of 3 as soon as the first three are.
/// Tap a slot to enter or change its time on a number pad.
struct SolveEntryScreen: View {
    @State private var slots: [SolveTime?] = AveragesCard.load()
    @State private var editing: Int?

    private var filled: [SolveTime] { slots.compactMap { $0 } }

    private var ao5: AverageResult? {
        filled.count == AveragesCard.slots ? SolveAverages.averageOf5(filled) : nil
    }

    /// Mo3 of the first three slots, once those are filled.
    private var mo3: AverageResult? {
        let first = slots.prefix(3).compactMap { $0 }
        return first.count == 3 ? SolveAverages.meanOf3(first) : nil
    }

    private func rowText(_ i: Int) -> String {
        guard let s = slots[i] else { return "–" }
        if let r = ao5 { return SolveAverages.displayTimes(filled, dropped: r.dropped)[i] }
        return s.text
    }

    private func set(_ i: Int, to value: SolveTime?) {
        slots[i] = value
        AveragesCard.save(slots)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Ao5")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(ao5?.text ?? "–")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("Mo3")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(mo3?.text ?? "–")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                ForEach(0..<AveragesCard.slots, id: \.self) { i in
                    Button { editing = i } label: {
                        HStack {
                            Text("\(i + 1)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(rowText(i))
                                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                                .minimumScaleFactor(0.6)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(i == editing ? 0.28 : 0.12)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Solve \(i + 1), \(slots[i]?.text ?? "empty")")
                }
                if !filled.isEmpty {
                    Button("Clear all") {
                        slots = Array(repeating: nil, count: AveragesCard.slots)
                        AveragesCard.save(slots)
                    }
                    .font(.system(size: 14, weight: .medium))
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 30)
            .padding(.bottom, 10)
        }
        .sheet(item: Binding(get: { editing.map(SlotID.init) },
                             set: { editing = $0?.index })) { slot in
            TimePad(title: "Solve \(slot.index + 1)", initial: slots[slot.index]) { value in
                set(slot.index, to: value)
            }
        }
    }
}

private struct SlotID: Identifiable {
    let index: Int
    var id: Int { index }
}

/// Number-pad entry: digits fill in from the right, so 1 2 3 4 reads 12.34 and
/// 1 0 2 3 4 reads 1:02.34. +2 and DNF toggle; the check saves, Clear empties
/// the slot.
private struct TimePad: View {
    let title: String
    let onDone: (SolveTime?) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var digits: String
    @State private var plusTwo: Bool
    @State private var dnf: Bool

    init(title: String, initial: SolveTime?, onDone: @escaping (SolveTime?) -> Void) {
        self.title = title
        self.onDone = onDone
        // Back to the typed digits (m ss cc, no leading zeros), penalty removed.
        var text = ""
        if let t = initial, let total = t.centis {
            let c = total - (t.plusTwo ? 200 : 0)
            let n = (c / 6000) * 10000 + ((c / 100) % 60) * 100 + c % 100
            text = n == 0 ? "" : String(n)
        }
        _digits = State(initialValue: text)
        _plusTwo = State(initialValue: initial?.plusTwo ?? false)
        _dnf = State(initialValue: initial?.isDNF ?? false)
    }

    private var value: SolveTime? {
        if dnf { return .dnf }
        return SolveTime.fromDigits(digits.isEmpty ? "0" : digits, plusTwo: plusTwo)
    }

    private var display: String {
        if dnf { return "DNF" }
        guard let v = value else { return "–" }
        // Show the typed time without the penalty folded in; +2 has its own chip.
        return SolveTime.format(centis: (v.centis ?? 0) - (plusTwo ? 200 : 0)) + (plusTwo ? " +2" : "")
    }

    private func key(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.18)))
        }
        .buttonStyle(.plain)
    }

    private func type(_ d: String) {
        dnf = false
        guard digits.count < 6 else { return }
        if digits.isEmpty && d == "0" { return }
        digits += d
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 4) {
                Text(display)
                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(value == nil ? Color.red : Color.white)
                ForEach([["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]], id: \.self) { row in
                    HStack(spacing: 4) {
                        ForEach(row, id: \.self) { d in key(d) { type(d) } }
                    }
                }
                HStack(spacing: 4) {
                    key("⌫") { dnf = false; if !digits.isEmpty { digits.removeLast() } }
                    key("0") { type("0") }
                    key("✓") { onDone(value); dismiss() }
                }
                HStack(spacing: 4) {
                    key(plusTwo ? "+2 ✓" : "+2") { plusTwo.toggle(); dnf = false }
                    key(dnf ? "DNF ✓" : "DNF") { dnf.toggle() }
                }
                Button("Empty slot") { onDone(nil); dismiss() }
                    .font(.system(size: 13))
                    .padding(.top, 2)
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle(title)
    }
}
