import SwiftUI

struct ContentView: View {
    @AppStorage("puzzle") private var puzzle: Puzzle = .cube3x3
    @State private var lengths = Dictionary(
        uniqueKeysWithValues: Puzzle.allCases.map { ($0, $0.defaultLength) }
    )
    @State private var moves: [String] = []

    var body: some View {
        TabView {
            ScrambleScreen(puzzle: $puzzle, lengths: $lengths, moves: $moves)
            // The net is a 3×3 cube state; Square-1 notation can't be applied to it.
            if puzzle == .cube3x3 {
                CubeMapView(moves: moves)
            }
        }
        .tabViewStyle(.verticalPage)
        .onAppear {
            if moves.isEmpty {
                moves = puzzle.generate(length: lengths[puzzle] ?? puzzle.defaultLength)
            }
        }
    }
}

private struct ScrambleScreen: View {
    @Binding var puzzle: Puzzle
    @Binding var lengths: [Puzzle: Int]
    @Binding var moves: [String]
    @State private var crownLength = Double(ScrambleGenerator.defaultLength)
    // Enum-based focus so `focus = nil` *explicitly* means "no field
    // focused" — a Bool `false` lets SwiftUI auto-restore focus to the
    // only focusable on the page (the length pill), which is what caused
    // tapping the notation to re-activate the pill.
    private enum FocusField: Hashable { case length }
    @FocusState private var focus: FocusField?
    private var lengthFocused: Bool { focus == .length }

    private var length: Int { lengths[puzzle] ?? puzzle.defaultLength }

    /// Group moves into fixed-width rows so the wrap doesn't shift based on
    /// which moves happen to be short. Every token is padded to its puzzle's
    /// widest move — 2 chars for 3×3 (`R'`), 8 for Square-1 (`(-5,-5)/`) —
    /// and each row holds as many as fit across the smallest watch.
    private var scrambleRows: String {
        let (width, perRow) = puzzle == .cube3x3 ? (2, 5) : (8, 2)
        let padded = moves.map { $0.padding(toLength: width, withPad: " ", startingAt: 0) }
        return stride(from: 0, to: padded.count, by: perRow)
            .map { padded[$0..<min($0 + perRow, padded.count)].joined(separator: " ") }
            .joined(separator: "\n")
    }

    private func select(_ newPuzzle: Puzzle) {
        guard newPuzzle != puzzle else { return }
        focus = nil
        puzzle = newPuzzle
        let newLength = lengths[newPuzzle] ?? newPuzzle.defaultLength
        crownLength = Double(newLength)
        moves = newPuzzle.generate(length: newLength)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    HStack(spacing: 6) {
                        ForEach(Puzzle.allCases) { option in
                            Button { select(option) } label: {
                                Text(option.shortName)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(option == puzzle ? Color.black : Color.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule().fill(option == puzzle
                                                       ? Color.accentColor
                                                       : Color.gray.opacity(0.30))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // 3×3: the standard WCA scrambling orientation, with the
                    // green pill + white text echoing the two reference faces.
                    // Square-1: how to read the notation.
                    Text(puzzle == .cube3x3
                         ? "White top · Green front"
                         : "(top, bottom) · / = slice")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.accentColor))

                    Text(scrambleRows)
                        .font(.system(size: puzzle == .cube3x3 ? 19 : 16,
                                      weight: .semibold, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        // Tap the scramble itself to release crown focus —
                        // a reliable dismiss path if the pill's own toggle
                        // misbehaves.
                        .contentShape(Rectangle())
                        .onTapGesture { focus = nil }

                    // Crown-capture pill. Each tap target is one-directional
                    // so there's no toggle race: tap the pill to ACTIVATE
                    // (sets focus true), tap the scramble notation above to
                    // DEACTIVATE. No Button — on watchOS, Button taps move
                    // focus to themselves and would fight with our binding.
                    HStack(spacing: 6) {
                        Image(systemName: lengthFocused
                              ? "dial.medium.fill"
                              : "dial.medium")
                        Text("\(puzzle.lengthLabel) \(length)")
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(lengthFocused ? Color.black : Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .padding(.horizontal, 14)
                    .background(
                        Capsule().fill(lengthFocused
                                       ? Color.accentColor
                                       : Color.gray.opacity(0.30))
                    )
                    .contentShape(Capsule())
                    .focusable()
                    .focused($focus, equals: .length)
                    .onTapGesture { focus = .length }
                    .sensoryFeedback(.selection, trigger: focus)
                    .digitalCrownRotation(
                        $crownLength,
                        from: Double(puzzle.lengthRange.lowerBound),
                        through: Double(puzzle.lengthRange.upperBound),
                        by: 1.0,
                        sensitivity: .medium,
                        isContinuous: false,
                        isHapticFeedbackEnabled: true
                    )
                    .onChange(of: crownLength) { _, v in
                        lengths[puzzle] = Int(v.rounded())
                    }
                    .onAppear { crownLength = Double(length) }

                    Button {
                        moves = puzzle.generate(length: length)
                        focus = nil
                    } label: {
                        Label("New Scramble", systemImage: "shuffle")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 3)
                    }
                    .buttonStyle(.borderedProminent)

                    if puzzle == .cube3x3 {
                        VStack(spacing: 2) {
                            Image(systemName: "chevron.compact.down")
                            Text("Cube map")
                                .font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                    }
                }
                .padding(.horizontal, 4)
            }
            .navigationTitle("Scramble")
        }
    }
}

#Preview {
    ContentView()
}
