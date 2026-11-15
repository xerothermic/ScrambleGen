import SwiftUI
import WatchKit

/// Colour of a Leitner box dot / bar segment (0 = never rated).
private func boxColor(_ box: Int) -> Color {
    switch box {
    case 1: return .red
    case 2: return .orange
    case 3: return .yellow
    case 4: return .mint
    case 5: return .green
    default: return Color.gray.opacity(0.5)
    }
}

private func play(_ type: WKHapticType) {
    WKInterfaceDevice.current().play(type)
}

// MARK: Root menu

/// The Algorithms card: mode menu (Drill, Practice, Learn, Quiz, Cases,
/// Progress) plus the case-set filter.
struct AlgoScreen: View {
    @StateObject private var store = AlgoStore()
    @AppStorage(AlgoCardInfo.filterKey) private var filter: AlgoSet = .all
    @AppStorage(AlgoCardInfo.inverseBonusKey) private var inverseBonus = true

    private var cases: [AlgoCase] { filter.cases(progress: store.progress) }

    private enum Route: Hashable {
        case drill, practice, learn, quiz, cases, set, progress
    }
    @State private var route: Route?

    /// Rows are plain Buttons that set `route` (state-driven navigation), not
    /// NavigationLinks: a Button's tap is known to work under the app's
    /// full-screen touch gestures, with a full-row hit area.
    private func menuButton(_ r: Route, _ title: String, _ sub: String,
                            _ symbol: String) -> some View {
        Button { route = r; play(.click) } label: {
            menuRow(title, sub, symbol)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
    }

    private func bigButton(_ r: Route, _ title: String, _ sub: String,
                           _ symbol: String) -> some View {
        Button { route = r; play(.click) } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 20, weight: .bold))
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.system(size: 19, weight: .bold))
                    Text(sub).font(.caption2).opacity(0.85)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(RoundedRectangle(cornerRadius: 14).fill(AlgoCardInfo.color))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private func destination(_ r: Route) -> some View {
        switch r {
        case .drill: AlgoDrillView(cases: cases, practice: false)
        case .practice: AlgoDrillView(cases: cases, practice: true)
        case .learn: AlgoLearnView(cases: cases)
        case .quiz: AlgoQuizView(cases: cases)
        case .cases: AlgoListView(cases: cases)
        case .set: AlgoFilterView(filter: $filter)
        case .progress: AlgoProgressView()
        }
    }

    var body: some View {
        NavigationStack {
            List {
                bigButton(.drill, "Drill", "\(store.dueCount(in: cases)) due", "timer")
                bigButton(.practice, "Practice", "on your cube", "hand.tap")
                menuButton(.learn, "Learn", "\(cases.count) cases", "book")
                menuButton(.quiz, "Quiz", "picture or name", "questionmark.circle")
                menuButton(.cases, "Cases", "list", "list.bullet")
                menuButton(.set, "Set", filter.label, "line.3.horizontal.decrease.circle")
                menuButton(.progress, "Progress", "best times", "chart.bar")
                Toggle(isOn: $inverseBonus) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Inverse bonus").font(.system(size: 15, weight: .medium))
                        Text("Drill the inverse after Good")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationDestination(item: $route) { destination($0) }
            .modifier(CloseAwareTitle(title: "Algorithms"))
        }
        .environmentObject(store)
    }

    private func menuRow(_ title: String, _ sub: String, _ symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .foregroundStyle(AlgoCardInfo.color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 16, weight: .semibold))
                Text(sub).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: Filter

private struct AlgoFilterView: View {
    @Binding var filter: AlgoSet
    @EnvironmentObject private var store: AlgoStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(AlgoSet.allCases) { option in
                Button {
                    filter = option
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(option.label).font(.system(size: 15, weight: .medium))
                            Text("\(option.cases(progress: store.progress).count) cases")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if option == filter {
                            Image(systemName: "checkmark").foregroundStyle(AlgoCardInfo.color)
                        }
                    }
                }
            }
        }
        .navigationTitle("Set")
    }
}

// MARK: Learn

/// One case: picture, name, alg and the inverse link. Tap flips between the
/// compact page and a big, scrollable alg.
private struct AlgoCasePage: View {
    let algoCase: AlgoCase
    var scrolls = false
    @State private var bigAlg = false
    @State private var showInverse = false

    private var longAlg: Bool { AlgoText.moveCount(algoCase.alg) > 12 }

    private var inverseLine: some View {
        Group {
            if algoCase.isSelfInverse {
                Text("Self-inverse")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if let inv = AlgoLibrary.inverse(of: algoCase) {
                Button { showInverse = true } label: {
                    Text("Inverse: \(inv.name)")
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .navigationDestination(isPresented: $showInverse) {
                    AlgoCaseDetailView(algoCase: inv)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var compact: some View {
        VStack(spacing: 3) {
            AlgoCaseView(algoCase: algoCase, size: longAlg ? 56 : 72)
            Text(algoCase.name)
                .font(.system(size: 15, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if !algoCase.detail.isEmpty {
                Text(algoCase.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text(AlgoText.lines(algoCase.alg, perLine: 4))
                .font(.system(size: 12, design: .monospaced))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
                .lineLimit(6)
            inverseLine
        }
        .padding(.horizontal, 4)
    }

    private var big: some View {
        ScrollView {
            VStack(spacing: 6) {
                Text(algoCase.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(AlgoText.lines(algoCase.alg, perLine: 3))
                    .font(.system(size: AlgoText.algFontSize(algoCase.alg),
                                  weight: .semibold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
                inverseLine
            }
            .padding(.horizontal, 4)
        }
    }

    var body: some View {
        Group {
            if bigAlg {
                big
            } else if scrolls {
                ScrollView { compact }
            } else {
                compact
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { bigAlg.toggle(); play(.click) }
    }
}

/// A single case reached from an inverse link.
private struct AlgoCaseDetailView: View {
    let algoCase: AlgoCase

    var body: some View {
        AlgoCasePage(algoCase: algoCase, scrolls: true)
            .navigationTitle(algoCase.id)
    }
}

private struct AlgoLearnView: View {
    let cases: [AlgoCase]
    @State private var index = 0

    var body: some View {
        Group {
            if cases.isEmpty {
                Text("No cases in this set.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                // Crown pages through the cases in set order.
                TabView(selection: $index) {
                    ForEach(Array(cases.enumerated()), id: \.element.id) { item in
                        AlgoCasePage(algoCase: item.element).tag(item.offset)
                    }
                }
                .tabViewStyle(.verticalPage)
                .onChange(of: index) { _, _ in play(.click) }
            }
        }
        .navigationTitle("Learn")
    }
}

// MARK: Case list

private struct AlgoListView: View {
    let cases: [AlgoCase]
    @EnvironmentObject private var store: AlgoStore
    @State private var openID: String?

    var body: some View {
        List {
            ForEach(cases) { c in
                Button { openID = c.id } label: {
                    HStack(spacing: 6) {
                        AlgoCaseView(algoCase: c, size: 34)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(c.name)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text(c.alg)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 2)
                        Circle()
                            .fill(boxColor(store.entry(c.id).box))
                            .frame(width: 8, height: 8)
                    }
                    .contentShape(Rectangle())
                }
            }
        }
        .navigationDestination(item: $openID) { id in
            if let c = AlgoLibrary.all.first(where: { $0.id == id }) {
                AlgoCaseDetailView(algoCase: c)
            }
        }
        .navigationTitle("Cases")
    }
}

// MARK: Drill / Practice

/// Drill: the next due case (Leitner), its scramble, tap Start, solve, stop by
/// tap or slap (StopDetector), reveal the alg, rate Not yet / Know it.
/// Practice: random cases from the set, same flow, rating Slow / Good.
private struct AlgoDrillView: View {
    let cases: [AlgoCase]
    let practice: Bool

    @EnvironmentObject private var store: AlgoStore
    @AppStorage(AlgoCardInfo.inverseBonusKey) private var inverseBonus = true
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    private enum Phase { case ready, running, reveal }
    @State private var phase: Phase = .ready
    @State private var current: AlgoCase?
    @State private var variant: AlgoAuf?
    @State private var bonus = false
    @State private var lastID: String?
    @State private var done = 0
    @State private var runStart = Date()
    @State private var runStartUptime: TimeInterval = 0
    @State private var finalTime: TimeInterval = 0
    @State private var detector = StopDetector()
    @State private var runtime = RuntimeKeeper()

    // MARK: Flow

    private func show(_ c: AlgoCase, bonus isBonus: Bool) {
        current = c
        let base = AlgoAuf(pre: "", post: "", setup: c.setup, solve: c.solve,
                           cp: c.cp, ep: c.ep)
        variant = ([base] + c.aufs).randomElement()
        bonus = isBonus
        lastID = c.id
        phase = .ready
    }

    private func loadNext() {
        if practice {
            let pool = cases.count > 1 ? cases.filter { $0.id != lastID } : cases
            if let c = pool.randomElement() { show(c, bonus: false) } else { current = nil }
        } else if let c = store.next(in: cases, avoiding: lastID) {
            show(c, bonus: false)
        } else {
            current = nil
        }
    }

    private func start() {
        guard phase == .ready else { return }
        runtime.start()
        let uptime = ProcessInfo.processInfo.systemUptime
        runStart = Date()
        runStartUptime = uptime
        phase = .running
        play(.start)
        detector.start(runStart: uptime) { spike in
            motionStop(atUptime: spike)
        }
    }

    private func motionStop(atUptime spike: TimeInterval) {
        guard phase == .running else { return }
        // Wall-clock based (the uptime clock does not count device sleep).
        let sinceSpike = max(0, ProcessInfo.processInfo.systemUptime - spike)
        let elapsed = Date().timeIntervalSince(runStart) - sinceSpike
        guard elapsed >= TimerCard.startLockout else { return }
        finish(elapsed: elapsed)
    }

    /// Foreground again mid-run (screen slept / clock shown): the run is just
    /// `runStart`, so re-arm the extended session and the slap detector.
    private func resumeRun() {
        guard phase == .running else { return }
        detector.stop()
        runtime.start()
        runStartUptime = ProcessInfo.processInfo.systemUptime
            - max(0, Date().timeIntervalSince(runStart))
        detector.start(runStart: runStartUptime) { spike in
            motionStop(atUptime: spike)
        }
    }

    private func tapStop() {
        let elapsed = Date().timeIntervalSince(runStart)
        // Brief lockout so the tap that started the run can't also stop it.
        guard elapsed > 0.3 else { return }
        finish(elapsed: elapsed)
    }

    private func finish(elapsed: TimeInterval) {
        guard phase == .running else { return }
        detector.stop()
        runtime.stop()
        finalTime = max(0, elapsed)
        phase = .reveal
        play(.stop)
    }

    private func abort() {
        detector.stop()
        runtime.stop()
        if phase == .running { phase = .ready }
    }

    private func rate(good: Bool) {
        guard let c = current else { return }
        store.rate(c.id, good: good, ms: Int((finalTime * 1000).rounded()))
        play(good ? .success : .failure)
        done += 1
        // Inverse bonus: after Good, offer the paired case once.
        if good, inverseBonus, !bonus, let inv = AlgoLibrary.inverse(of: c) {
            show(inv, bonus: true)
        } else {
            loadNext()
        }
    }

    // MARK: Screens

    private var readyView: some View {
        VStack(spacing: 4) {
            ScrollView {
                if let c = current {
                    VStack(spacing: 5) {
                        if bonus {
                            Text("Now its inverse")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(AlgoCardInfo.color)
                        }
                        AlgoCaseView(algoCase: c, variant: variant, size: 84)
                        HStack(spacing: 3) {
                            ForEach(1...5, id: \.self) { i in
                                Circle()
                                    .fill(i <= store.entry(c.id).box
                                          ? boxColor(store.entry(c.id).box)
                                          : Color.gray.opacity(0.3))
                                    .frame(width: 6, height: 6)
                            }
                        }
                        Text(AlgoText.lines(variant?.setup ?? c.setup, perLine: 4))
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .multilineTextAlignment(.leading)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 8)
                                .fill(Color.black.opacity(0.35)))
                        if done > 0 {
                            Text("\(done) done")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 4)
                } else {
                    Text("No cases in this set.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 20)
                }
            }
            // Pinned below the scroll area so it is always on screen, never
            // scrolled off the bottom of a small watch.
            if current != nil {
                Button { start() } label: {
                    Text("Start")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Capsule().fill(Color.accentColor))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 4)
            }
        }
    }

    private var runningView: some View {
        VStack(spacing: 6) {
            if isLuminanceReduced {
                TimelineView(.periodic(from: runStart, by: 1)) { context in
                    Text(TimerCard.format(context.date.timeIntervalSince(runStart),
                                          centis: false))
                        .font(.system(size: 42, weight: .semibold, design: .monospaced))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .foregroundStyle(Color.gray)
                }
            } else {
                TimelineView(.animation) { context in
                    Text(TimerCard.format(context.date.timeIntervalSince(runStart)))
                        .font(.system(size: 42, weight: .semibold, design: .monospaced))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .foregroundStyle(Color.white)
                }
                Text("Slap to stop · or tap")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { tapStop() }
    }

    private var revealView: some View {
        VStack(spacing: 4) {
            ScrollView {
                if let c = current {
                    VStack(spacing: 4) {
                        HStack(spacing: 6) {
                            AlgoCaseView(algoCase: c, variant: variant, size: 40)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(TimerCard.format(finalTime))
                                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                                    .minimumScaleFactor(0.6)
                                    .lineLimit(1)
                                Text(c.name)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            Spacer(minLength: 0)
                        }
                        Text(AlgoText.lines(variant?.solve ?? c.solve, perLine: 3))
                            .font(.system(size: AlgoText.algFontSize(variant?.solve ?? c.solve),
                                          weight: .semibold, design: .monospaced))
                            .multilineTextAlignment(.leading)
                            .minimumScaleFactor(0.6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 4)
                }
            }
            HStack(spacing: 6) {
                ratePill(practice ? "Slow" : "Not yet", color: .orange, good: false)
                ratePill(practice ? "Good" : "Know it", color: .green, good: true)
            }
            .padding(.horizontal, 4)
        }
    }

    private func ratePill(_ title: String, color: Color, good: Bool) -> some View {
        Button { rate(good: good) } label: {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Capsule().fill(color))
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        Group {
            switch phase {
            case .ready: readyView
            case .running: runningView
            case .reveal: revealView
            }
        }
        .navigationTitle(practice ? "Practice" : "Drill")
        .onAppear { if current == nil { loadNext() } }
        .onDisappear { abort() }
        .onChange(of: phase) { _, new in
            if new == .reveal { play(.click) }
        }
        // Without a live extended runtime session, backgrounding only pauses
        // the detector; the run (a start Date) resumes with the right elapsed
        // time when the app is active again.
        .onChange(of: scenePhase) { _, new in
            if new == .active {
                resumeRun()
            } else if phase == .running,
                      !runtime.isRunning, !runtime.isActiveOrStarting {
                detector.stop()
                runtime.stop()
            }
        }
    }
}

// MARK: Quiz

/// Quiz: a picture with four names to pick from, or a name with a 2x2 grid of
/// pictures. Right or wrong updates the Leitner box like a drill rating.
private struct AlgoQuizView: View {
    let cases: [AlgoCase]
    @EnvironmentObject private var store: AlgoStore

    private struct Question {
        let target: AlgoCase
        let options: [AlgoCase]
        let byPicture: Bool
    }

    @State private var question: Question?
    @State private var picked: String?
    @State private var right = 0
    @State private var asked = 0

    private func makeQuestion() {
        guard let target = cases.randomElement() else { question = nil; return }
        let family = target.isPLL
        var pool = cases.filter { $0.isPLL == family && $0.id != target.id }
        if pool.count < 3 {
            pool = AlgoLibrary.all.filter { $0.isPLL == family && $0.id != target.id }
        }
        let options = ([target] + Array(pool.shuffled().prefix(3))).shuffled()
        question = Question(target: target, options: options, byPicture: Bool.random())
        picked = nil
    }

    private func answer(_ c: AlgoCase) {
        guard let q = question, picked == nil else { return }
        picked = c.id
        let good = c.id == q.target.id
        store.rate(q.target.id, good: good)
        asked += 1
        if good { right += 1 }
        play(good ? .success : .failure)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            makeQuestion()
        }
    }

    private func tint(_ c: AlgoCase, target: AlgoCase) -> Color {
        guard let picked = picked else { return Color.gray.opacity(0.3) }
        if c.id == target.id { return Color.green.opacity(0.7) }
        if c.id == picked { return Color.red.opacity(0.7) }
        return Color.gray.opacity(0.2)
    }

    var body: some View {
        Group {
            if let q = question {
                ScrollView {
                    VStack(spacing: 6) {
                        if q.byPicture {
                            AlgoCaseView(algoCase: q.target, size: 84)
                            ForEach(q.options) { option in
                                Button { answer(option) } label: {
                                    Text(option.name)
                                        .font(.system(size: 14, weight: .semibold))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.6)
                                        .frame(maxWidth: .infinity, minHeight: 32)
                                        .background(RoundedRectangle(cornerRadius: 10)
                                            .fill(tint(option, target: q.target)))
                                }
                                .buttonStyle(.plain)
                            }
                        } else {
                            Text(q.target.name)
                                .font(.system(size: 17, weight: .bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            let rows = [Array(q.options.prefix(2)), Array(q.options.dropFirst(2))]
                            ForEach(0..<rows.count, id: \.self) { r in
                                HStack(spacing: 6) {
                                    ForEach(rows[r]) { option in
                                        Button { answer(option) } label: {
                                            AlgoCaseView(algoCase: option, size: 62)
                                                .padding(4)
                                                .background(RoundedRectangle(cornerRadius: 10)
                                                    .fill(tint(option, target: q.target)))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        Text("\(right) / \(asked)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)
                }
            } else {
                Text("No cases in this set.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Quiz")
        .onAppear { if question == nil { makeQuestion() } }
    }
}

// MARK: Progress

private struct AlgoProgressView: View {
    @EnvironmentObject private var store: AlgoStore
    @State private var confirmReset = false

    private func known(_ cases: [AlgoCase]) -> Int {
        cases.filter { store.entry($0.id).isKnown }.count
    }

    private func bar(_ title: String, _ value: Int, _ total: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(value)/\(total)")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.2))
                    Capsule().fill(AlgoCardInfo.color)
                        .frame(width: max(4, geo.size.width * CGFloat(value) / CGFloat(max(total, 1))))
                }
            }
            .frame(height: 5)
        }
    }

    var body: some View {
        let oll = AlgoLibrary.all.filter { $0.kind == "oll" }
        let pll = AlgoLibrary.all.filter { $0.isPLL }
        let counts = (0...5).map { box in
            AlgoLibrary.all.filter { store.entry($0.id).box == box }.count
        }
        let timed = AlgoLibrary.all.filter { store.entry($0.id).bestMs != nil }
        ScrollView {
            VStack(spacing: 8) {
                bar("OLL known", known(oll), oll.count)
                bar("PLL known", known(pll), pll.count)
                HStack(spacing: 3) {
                    ForEach(1...5, id: \.self) { box in
                        VStack(spacing: 1) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(boxColor(box))
                                .frame(height: 6)
                            Text("\(counts[box])")
                                .font(.system(size: 10, design: .monospaced))
                        }
                    }
                }
                Text("Box 1-5 · unseen \(counts[0]) · due \(store.dueCount(in: AlgoLibrary.all))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if !timed.isEmpty {
                    Text("Best times")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.top, 4)
                    ForEach(timed) { c in
                        HStack {
                            Text(c.name)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            Spacer(minLength: 4)
                            Text(TimerCard.format(
                                TimeInterval(store.entry(c.id).bestMs ?? 0) / 1000))
                                .foregroundStyle(.secondary)
                        }
                        .font(.system(size: 12, design: .monospaced))
                    }
                }
                Button("Reset progress", role: .destructive) { confirmReset = true }
                    .font(.system(size: 14, weight: .medium))
                    .padding(.top, 4)
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Progress")
        .confirmationDialog("Reset all progress?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { store.reset() }
        }
    }
}
