import SwiftUI

struct ContentView: View {
    @State private var length = ScrambleGenerator.defaultLength
    @State private var moves = ScrambleGenerator.generate()

    var body: some View {
        TabView {
            ScrambleScreen(length: $length, moves: $moves)
            CubeMapView(moves: moves)
        }
        .tabViewStyle(.verticalPage)
    }
}

private struct ScrambleScreen: View {
    @Binding var length: Int
    @Binding var moves: [String]
    @State private var crownLength = Double(ScrambleGenerator.defaultLength)
    @FocusState private var lengthFocused: Bool

    /// Group moves into fixed-width rows so the wrap doesn't shift based on
    /// which moves happen to be 1 vs 2 chars wide.
    private var scrambleRows: String {
        stride(from: 0, to: moves.count, by: 5)
            .map { moves[$0..<min($0 + 5, moves.count)].joined(separator: "  ") }
            .joined(separator: "\n")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // Standard WCA scrambling orientation reminder. The green
                    // pill + white text echo the two reference faces.
                    Text("White top · Green front")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.accentColor))

                    Text(scrambleRows)
                        .font(.system(size: 19, weight: .semibold, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)

                    // Tap to capture the crown for adjusting length;
                    // tap again to release it back to page navigation.
                    Button {
                        lengthFocused.toggle()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: lengthFocused
                                  ? "checkmark.circle.fill"
                                  : "dial.medium")
                            Text("Length \(length)")
                        }
                        .font(.system(size: 16, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.bordered)
                    .tint(lengthFocused ? Color.accentColor : Color.gray)
                    .focusable()
                    .focused($lengthFocused)
                    .digitalCrownRotation(
                        $crownLength,
                        from: 1.0, through: 50.0, by: 1.0,
                        sensitivity: .medium,
                        isContinuous: false,
                        isHapticFeedbackEnabled: true
                    )
                    .onChange(of: crownLength) { _, v in
                        length = Int(v.rounded())
                    }
                    .onAppear { crownLength = Double(length) }

                    Button {
                        moves = ScrambleGenerator.generate(length: length)
                        lengthFocused = false
                    } label: {
                        Label("New Scramble", systemImage: "shuffle")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 3)
                    }
                    .buttonStyle(.borderedProminent)

                    VStack(spacing: 2) {
                        Image(systemName: "chevron.compact.down")
                        Text("Cube map")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
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
