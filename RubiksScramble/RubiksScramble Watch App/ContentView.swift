import SwiftUI

struct ContentView: View {
    @AppStorage("puzzle") private var puzzle: Puzzle = .cube3x3
    @State private var lengths = Dictionary(
        uniqueKeysWithValues: Puzzle.allCases.map { ($0, $0.defaultLength) }
    )
    @State private var moves: [Puzzle: [String]] = [:]
    // Which vertical page (0 = scramble, 1 = map) each puzzle is showing.
    @State private var pages: [Puzzle: Int] = [:]

    // nil = the Wallet-style card stack; otherwise the open puzzle.
    @State private var openPuzzle: Puzzle?
    @Namespace private var cardSpace

    // Close affordance: invisible until the screen is touched, then a small
    // xmark that fades out again ~3 s after the last touch.
    @State private var showClose = false
    @State private var touching = false
    @State private var hideTask: Task<Void, Never>?

    private static let spring = Animation.spring(response: 0.45, dampingFraction: 0.82)

    private func close() {
        hideTask?.cancel()
        showClose = false
        withAnimation(Self.spring) { openPuzzle = nil }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.5)) { showClose = false }
        }
    }

    private func touchBegan() {
        guard !touching else { return }
        touching = true
        hideTask?.cancel()
        withAnimation(.easeIn(duration: 0.15)) { showClose = true }
    }

    private func touchEnded() {
        touching = false
        scheduleHide()
    }

    var body: some View {
        Group {
            if let open = openPuzzle {
                PuzzlePage(puzzle: open, lengths: $lengths, moves: $moves,
                           page: Binding(get: { pages[open] ?? 0 },
                                         set: { pages[open] = $0 }))
                    .background(
                        // The tapped card grows into this tinted full-screen panel.
                        RoundedRectangle(cornerRadius: 18)
                            .fill(open.cardColor.opacity(0.35))
                            .matchedGeometryEffect(id: open, in: cardSpace)
                            .ignoresSafeArea()
                    )
                    // Any touch reveals the close button. simultaneousGesture
                    // keeps the puzzle's own taps and paging working.
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in touchBegan() }
                            .onEnded { _ in touchEnded() }
                    )
                    // Rightward swipe that starts at the left edge also closes.
                    // Vertical paging and taps are unaffected.
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 20)
                            .onEnded { g in
                                if g.startLocation.x < 28,
                                   g.translation.width > 50,
                                   abs(g.translation.height) < 40 { close() }
                            }
                    )
                    .overlay(alignment: .topLeading) {
                        Button { close() } label: {
                            ZStack {
                                Circle().fill(.ultraThinMaterial)
                                Image(systemName: "xmark")
                                    .font(.system(size: 20, weight: .bold))
                            }
                            .frame(width: 42, height: 42)
                            // Inset so the circle clears the rounded screen corner.
                            .padding(8)
                            .opacity(showClose ? 1 : 0)
                            .frame(width: 70, height: 70, alignment: .topLeading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close")
                        .ignoresSafeArea()
                    }
                    .transition(.opacity)
            } else {
                CardStack(lastUsed: puzzle, space: cardSpace) { option in
                    puzzle = option
                    withAnimation(Self.spring) { openPuzzle = option }
                }
                .transition(.opacity)
            }
        }
        .onAppear {
            for option in Puzzle.allCases where moves[option] == nil {
                moves[option] = option.generate(
                    length: lengths[option] ?? option.defaultLength)
            }
        }
    }
}

/// Wallet-style stack of overlapping cards, one per puzzle. Tap a card to open it.
private struct CardStack: View {
    let lastUsed: Puzzle
    let space: Namespace.ID
    let onPick: (Puzzle) -> Void

    private let cardHeight: CGFloat = 120
    private let peek: CGFloat = 64

    private func color(_ option: Puzzle) -> Color { option.cardColor }

    /// Tiny solved-state map of the puzzle, reusing the real map drawing code.
    @ViewBuilder
    private func preview(_ option: Puzzle) -> some View {
        switch option {
        case .cube3x3:
            let cube = CubeState()
            let cell: CGFloat = 3.5
            let face: CGFloat = cell * 3 + 1
            VStack(spacing: 1) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: 1) {
                        ForEach(0..<4, id: \.self) { col in
                            if let f = Self.net[row][col] {
                                miniFace(cube, f, cell: cell)
                            } else {
                                Color.clear.frame(width: face, height: face)
                            }
                        }
                    }
                }
            }
        case .square1:
            let state = Square1State()
            Canvas { context, size in
                Square1Drawing.draw(state, in: &context, size: size)
            }
            .frame(width: 26, height: 50)
        }
    }

    private static let net: [[CubeFace?]] = [
        [nil, .up, nil, nil],
        [.left, .front, .right, .back],
        [nil, .down, nil, nil],
    ]

    private func miniFace(_ cube: CubeState, _ face: CubeFace, cell: CGFloat) -> some View {
        VStack(spacing: 0.5) {
            ForEach(0..<3, id: \.self) { r in
                HStack(spacing: 0.5) {
                    ForEach(0..<3, id: \.self) { c in
                        Rectangle()
                            .fill(cube.color(face: face, row: r, col: c))
                            .frame(width: cell, height: cell)
                    }
                }
            }
        }
    }

    var body: some View {
        // Crown / touch scrolls the stack. Cards overlap via negative spacing,
        // later cards on top; scrollTransition tilts each card in perspective
        // (like Wallet) as it nears the top or bottom edge.
        ScrollView {
            VStack(spacing: peek - cardHeight) {
                ForEach(Puzzle.allCases, id: \.self) { option in
                    Button {
                        onPick(option)
                    } label: {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.name)
                                    .font(.system(size: 20, weight: .bold))
                                Text(option == lastUsed ? "Last used" : "Scramble")
                                    .font(.caption2)
                                    .opacity(0.8)
                                Spacer()
                            }
                            Spacer(minLength: 4)
                            preview(option)
                        }
                        .foregroundStyle(.white)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: cardHeight)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(LinearGradient(
                                    colors: [color(option), color(option).opacity(0.75)],
                                    startPoint: .top, endPoint: .bottom))
                                .matchedGeometryEffect(id: option, in: space)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 18))
                        // Two layers: tight contact shadow + soft ambient one,
                        // which also separates overlapping cards.
                        .shadow(color: .black.opacity(0.55), radius: 2, x: 0, y: 1)
                        .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: -3)
                    }
                    .buttonStyle(.plain)
                    .scrollTransition(axis: .vertical) { content, phase in
                        content
                            .rotation3DEffect(.degrees(phase.value * -22),
                                              axis: (x: 1, y: 0, z: 0),
                                              anchor: .center, perspective: 0.6)
                            .scaleEffect(1 - abs(phase.value) * 0.06)
                            .opacity(1 - abs(phase.value) * 0.25)
                    }
                    .accessibilityLabel("\(option.name) scramble")
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
        }
    }
}

extension Puzzle {
    /// Card / panel colour for this puzzle.
    var cardColor: Color {
        switch self {
        case .cube3x3: Color(red: 0.19, green: 0.82, blue: 0.35)  // cube green
        case .square1: Color(red: 0.81, green: 0.13, blue: 0.16)  // WCA front red
        }
    }
}

private struct PuzzlePage: View {
    let puzzle: Puzzle
    @Binding var lengths: [Puzzle: Int]
    @Binding var moves: [Puzzle: [String]]
    @Binding var page: Int

    var body: some View {
        // Scramble on top; swipe down for the puzzle's state after it.
        TabView(selection: $page) {
            ScrambleScreen(puzzle: puzzle, lengths: $lengths, moves: $moves)
                .tag(0)
            switch puzzle {
            case .cube3x3: CubeMapView(moves: moves[puzzle] ?? []).tag(1)
            case .square1: Square1MapView(moves: moves[puzzle] ?? []).tag(1)
            }
        }
        .tabViewStyle(.verticalPage)
    }
}

private struct ScrambleScreen: View {
    let puzzle: Puzzle
    @Binding var lengths: [Puzzle: Int]
    @Binding var moves: [Puzzle: [String]]
    @State private var crownLength = Double(ScrambleGenerator.defaultLength)
    // Single source of truth for "pill selected" is `isSelected`, toggled only
    // by taps. Focus is just the mechanism that routes the crown to the pill:
    // the pill is focusable only while selected, so otherwise the crown
    // belongs to the ScrollView. Visuals follow `isSelected`, never focus.
    private enum FocusField: Hashable { case length }
    @FocusState private var focus: FocusField?
    @State private var isSelected = false
    private var lengthFocused: Bool { isSelected }

    private var length: Int { lengths[puzzle] ?? puzzle.defaultLength }

    /// Where `length` sits within the puzzle's range, 0...1, for the meter.
    private var lengthFraction: Double {
        let r = puzzle.lengthRange
        return Double(length - r.lowerBound) / Double(r.upperBound - r.lowerBound)
    }

    /// Group moves into fixed-width rows so the wrap doesn't shift based on
    /// which moves happen to be short. Every token is padded to its puzzle's
    /// widest move — 2 chars for 3×3 (`R'`), 8 for Square-1 (`(-5,-5)/`) —
    /// and each row holds as many as fit across the smallest watch.
    private var scrambleRows: String {
        let (width, perRow) = puzzle == .cube3x3 ? (2, 5) : (8, 2)
        let padded = (moves[puzzle] ?? []).map {
            (puzzle == .square1 ? Self.aligned($0) : $0)
                .padding(toLength: width, withPad: " ", startingAt: 0)
        }
        return stride(from: 0, to: padded.count, by: perRow)
            .map { padded[$0..<min($0 + perRow, padded.count)].joined(separator: " ") }
            .joined(separator: "\n")
    }

    /// Right-align each Square-1 number in a 2-char column, so `(1,0)/` reads
    /// `( 1, 0)/` and `(-3,3)/` reads `(-3, 3)/`: the commas, parentheses and
    /// slashes of every token line up in the monospaced rows. Bare `/` is left as is.
    private static func aligned(_ token: String) -> String {
        let parts = token.dropFirst().prefix { $0 != ")" }.split(separator: ",")
        guard token.hasPrefix("("), parts.count == 2 else { return token }
        let cols = parts.map { String(repeating: " ", count: max(0, 2 - $0.count)) + $0 }
        return "(\(cols[0]),\(cols[1]))/"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
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
                        .multilineTextAlignment(.leading)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        // Tap the scramble itself to release crown focus —
                        // a reliable dismiss path if the pill's own toggle
                        // misbehaves.
                        .contentShape(Rectangle())
                        .onTapGesture { isSelected = false }

                    // Crown-capture pill. Tap toggles focus (tap the scramble
                    // notation above also deactivates). No Button — on watchOS, Button taps move
                    // focus to themselves and would fight with our binding.
                    VStack(spacing: 5) {
                        HStack(spacing: 6) {
                            Image(systemName: lengthFocused
                                  ? "dial.medium.fill"
                                  : "dial.medium")
                            Text("\(puzzle.lengthLabel) \(length)")
                        }
                        // Thermometer: count within the puzzle's range.
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill((lengthFocused ? Color.black : Color.white).opacity(0.25))
                                Capsule()
                                    .fill(lengthFocused ? Color.black : Color.accentColor)
                                    .frame(width: max(4, geo.size.width * lengthFraction))
                            }
                        }
                        .frame(height: 4)
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(lengthFocused ? Color.black : Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 14)
                    .background(
                        Capsule().fill(lengthFocused
                                       ? Color.accentColor
                                       : Color.gray.opacity(0.30))
                    )
                    .contentShape(Capsule())
                    .focusable(isSelected)
                    .focused($focus, equals: .length)
                    // Tap toggles: first tap selects (crown adjusts the
                    // count), second tap deselects (crown scrolls the page).
                    .onTapGesture { isSelected.toggle() }
                    .sensoryFeedback(.selection, trigger: isSelected)
                    .onChange(of: isSelected) { _, selected in
                        // Hand the crown to / take it from the pill. Deferred
                        // a tick so focusable(true) has been applied first.
                        Task { @MainActor in focus = selected ? .length : nil }
                    }
                    // Focus lost externally (user scrolled the page, swiped
                    // away): deselect. Only reacts to losing an actual focus,
                    // so the not-yet-focused moment after selecting is ignored.
                    .onChange(of: focus) { old, new in
                        if old == .length, new == nil, isSelected { isSelected = false }
                    }
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
                        moves[puzzle] = puzzle.generate(length: length)
                        isSelected = false
                    } label: {
                        Label("New Scramble", systemImage: "shuffle")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 3)
                    }
                    .buttonStyle(.borderedProminent)

                    VStack(spacing: 2) {
                        Image(systemName: "chevron.compact.down")
                        Text(puzzle == .cube3x3 ? "Cube map" : "Square-1 map")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                }
                .padding(.horizontal, 4)
            }
            .navigationTitle(puzzle.name)
        }
        // Swiping to the other puzzle shouldn't leave the crown bound here.
        .onDisappear { isSelected = false }
    }
}

#Preview {
    ContentView()
}
