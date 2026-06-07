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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Text(moves.joined(separator: "  "))
                        .font(.system(.headline, design: .monospaced))
                        .multilineTextAlignment(.center)
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
                        .frame(maxWidth: .infinity)
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
                            .frame(maxWidth: .infinity)
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
