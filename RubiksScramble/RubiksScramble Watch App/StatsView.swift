import SwiftUI
import Charts

/// Entry point from the Timer card's toolbar: stats, history, settings.
struct StatsHubView: View {
    @ObservedObject private var store = SolveStore.shared
    @AppStorage(MotionInsights.key) private var motionOn = false

    var body: some View {
        List {
            if PremiumFeatures.isUnlocked {
                NavigationLink {
                    StatsView()
                } label: {
                    Label("Stats", systemImage: "chart.xyaxis.line")
                }
                NavigationLink {
                    SolveListView()
                } label: {
                    Label("History", systemImage: "list.number")
                }
                if motionOn {
                    NavigationLink {
                        QuietTimeView()
                    } label: {
                        Label("Quiet time", systemImage: "waveform.path.ecg")
                    }
                }
            } else {
                Text("Stats and history are part of Premium.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Motion insights", isOn: $motionOn)
                Text(MotionInsights.explanation + " Experimental.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Section {
                Text("\(store.records.count) solves saved on this watch.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Stats")
    }
}

/// Averages plus the trend chart.
struct StatsView: View {
    @ObservedObject private var store = SolveStore.shared

    private static let window = 40

    private func fmt(_ t: TimeInterval?) -> String { t.map { TimerCard.format($0) } ?? "-" }

    var body: some View {
        let all = store.times
        ScrollView {
            VStack(spacing: 8) {
                if all.isEmpty {
                    Text("No solves yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 3) {
                        row("Best", fmt(all.min()), "")
                        row("ao5", fmt(SolveStats.ao(5, all)), "best " + fmt(SolveStats.bestAo(5, all)))
                        row("ao12", fmt(SolveStats.ao(12, all)), "best " + fmt(SolveStats.bestAo(12, all)))
                        row("Mean", fmt(SolveStats.mean(all)), "\(all.count) solves")
                    }
                    TrendChart(times: all, window: Self.window)
                        .frame(height: 110)
                    legend
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Stats")
    }

    private func row(_ name: String, _ value: String, _ extra: String) -> some View {
        GridRow {
            Text(name).foregroundStyle(.secondary)
            Text(value).fontWeight(.semibold)
            Text(extra).foregroundStyle(.secondary).font(.system(size: 10))
        }
        .font(.system(size: 13, design: .monospaced))
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    private var legend: some View {
        HStack(spacing: 8) {
            Label("Solve", systemImage: "circle.fill").foregroundStyle(.gray)
            Label("ao5", systemImage: "minus").foregroundStyle(TrendChart.ao5Color)
            Label("ao12", systemImage: "minus").foregroundStyle(TrendChart.ao12Color)
            Label("Best", systemImage: "star.fill").foregroundStyle(.yellow)
        }
        .font(.system(size: 9))
        .labelStyle(.titleAndIcon)
        .minimumScaleFactor(0.7)
    }
}

/// Single times as dots with a faint line, ao5 / ao12 overlaid, stars on
/// solves that were a best single when set. x = solve number.
struct TrendChart: View {
    static let ao5Color = Color(red: 0.35, green: 0.65, blue: 1.0)
    static let ao12Color = Color.orange

    private struct Point: Identifiable {
        let id: Int
        let single: TimeInterval
        let ao5: TimeInterval?
        let ao12: TimeInterval?
        let isRecord: Bool
    }

    private let points: [Point]
    private let yDomain: ClosedRange<Double>

    init(times: [TimeInterval], window: Int) {
        let a5 = SolveStats.rollingAo(5, times)
        let a12 = SolveStats.rollingAo(12, times)
        let records = Set(SolveStats.recordIndices(times))
        let start = max(0, times.count - window)
        points = (start..<times.count).map {
            Point(id: $0 + 1, single: times[$0], ao5: a5[$0], ao12: a12[$0], isRecord: records.contains($0))
        }
        let shown = points.flatMap { [$0.single] + [$0.ao5, $0.ao12].compactMap { $0 } }
        let lo = shown.min() ?? 0, hi = shown.max() ?? 1
        let pad = max(0.5, (hi - lo) * 0.08)
        yDomain = max(0, lo - pad)...(hi + pad)
    }

    var body: some View {
        Chart {
            ForEach(points) { p in
                LineMark(x: .value("Solve", p.id), y: .value("Time", p.single),
                         series: .value("Series", "single"))
                    .foregroundStyle(Color.gray.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(x: .value("Solve", p.id), y: .value("Time", p.single))
                    .foregroundStyle(Color.gray)
                    .symbolSize(10)
                if let v = p.ao5 {
                    LineMark(x: .value("Solve", p.id), y: .value("Time", v),
                             series: .value("Series", "ao5"))
                        .foregroundStyle(Self.ao5Color)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                }
                if let v = p.ao12 {
                    LineMark(x: .value("Solve", p.id), y: .value("Time", v),
                             series: .value("Series", "ao12"))
                        .foregroundStyle(Self.ao12Color)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                }
                if p.isRecord {
                    PointMark(x: .value("Solve", p.id), y: .value("Time", p.single))
                        .foregroundStyle(Color.yellow)
                        .symbol(.diamond)
                        .symbolSize(40)
                }
            }
        }
        .chartYScale(domain: yDomain)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let d = value.as(Double.self) {
                        Text(TimerCard.format(d, centis: false)).font(.system(size: 9))
                    }
                }
            }
        }
    }
}

/// Most recent solves first; tap for the note / delete.
struct SolveListView: View {
    @ObservedObject private var store = SolveStore.shared
    @State private var confirmClear = false

    var body: some View {
        List {
            ForEach(Array(store.records.suffix(100).reversed())) { r in
                NavigationLink {
                    SolveDetailView(id: r.id)
                } label: {
                    HStack {
                        Text(TimerCard.format(r.time))
                            .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        Spacer()
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(r.date, format: .dateTime.month(.abbreviated).day())
                            if r.note?.isEmpty == false { Image(systemName: "note.text") }
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    }
                }
            }
            if !store.records.isEmpty {
                Button("Delete all history", role: .destructive) { confirmClear = true }
                    .font(.system(size: 14))
            }
        }
        .navigationTitle("History")
        .confirmationDialog("Delete all \(store.records.count) solves?",
                            isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Delete all", role: .destructive) { store.deleteAll() }
        }
    }
}

struct SolveDetailView: View {
    let id: UUID
    @ObservedObject private var store = SolveStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""

    var body: some View {
        if let r = store.records.first(where: { $0.id == id }) {
            ScrollView {
                VStack(spacing: 6) {
                    Text(TimerCard.format(r.time))
                        .font(.system(size: 34, weight: .bold, design: .monospaced))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text(r.date, format: .dateTime.year().month().day().hour().minute())
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    if r.imported == true {
                        Text("Imported, date approximate")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    TextField("Note", text: $note)
                        .onSubmit { store.update(id) { $0.note = note.isEmpty ? nil : note } }
                    if let ratio = r.quietRatio, let n = r.pauseCount {
                        Text("Quiet time \(Int((ratio * 100).rounded()))% · \(n) pause\(n == 1 ? "" : "s") (experimental)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Button("Delete", role: .destructive) {
                        store.delete(id)
                        dismiss()
                    }
                }
                .padding(.horizontal, 4)
            }
            .onAppear { note = r.note ?? "" }
            .navigationTitle("Solve")
        }
    }
}

/// Experimental: timeline of the last motion-recorded solve (wrist activity
/// with quiet stretches shaded) and the quiet-time trend. Wrist stillness of
/// 0.3 s or more; says nothing about what the eyes or the cube are doing.
struct QuietTimeView: View {
    @ObservedObject private var store = SolveStore.shared
    @State private var timeline: [EnvelopePoint] = []
    @State private var result: PauseResult?

    private var lastMotionSolve: SolveRecord? {
        store.records.last { $0.hasMotion == true }
    }

    private struct Loaded {
        let timeline: [EnvelopePoint]
        let result: PauseResult?
    }

    private struct TrendPoint: Identifiable {
        let n: Int
        let pct: Double
        var id: Int { n }
    }

    private var trend: [TrendPoint] {
        let ratios = store.records.compactMap(\.quietRatio)
        return ratios.suffix(30).enumerated().map { TrendPoint(n: $0.offset + 1, pct: $0.element * 100) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("Experimental")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.orange)
                if let rec = lastMotionSolve, !timeline.isEmpty {
                    Text("Last solve \(TimerCard.format(rec.time))")
                        .font(.system(size: 12, design: .monospaced))
                    timelineChart(elapsed: rec.time)
                        .frame(height: 90)
                    if let r = result {
                        Text(r.summaryLine)
                            .font(.system(size: 12, weight: .medium))
                        Text("Longest \(String(format: "%.1f", r.longest)) s · first move \(String(format: "%.1f", r.startLatency)) s")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("No motion solve yet. Time a solve with Motion insights on.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if trend.count >= 2 {
                    Text("Quiet time per solve (%)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Chart {
                        ForEach(trend) { p in
                            LineMark(x: .value("Solve", p.n), y: .value("Quiet %", p.pct))
                                .foregroundStyle(Color.orange)
                            PointMark(x: .value("Solve", p.n), y: .value("Quiet %", p.pct))
                                .foregroundStyle(Color.orange)
                                .symbolSize(14)
                        }
                    }
                    .chartXAxis(.hidden)
                    .chartYScale(domain: 0...max(30, (trend.map(\.pct).max() ?? 30) * 1.1))
                    .frame(height: 70)
                }
                Text("Wrist stillness of 0.3 s or more. The watch sees your wrist, not the cube; this is not a look-ahead measurement.")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                let u = MotionStore.shared.usage()
                Text("\(u.count) recording\(u.count == 1 ? "" : "s") · \(u.bytes / 1024) KB on this watch")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Quiet time")
        .task(id: lastMotionSolve?.id) { await load() }
        .onAppear { MotionStore.shared.debugDump() }
    }

    private func timelineChart(elapsed: TimeInterval) -> some View {
        let top = (timeline.map(\.e).max() ?? 1) * 1.1
        return Chart {
            ForEach(result?.spans ?? []) { s in
                RectangleMark(xStart: .value("From", s.start), xEnd: .value("To", s.end),
                              yStart: .value("Lo", 0), yEnd: .value("Hi", top))
                    .foregroundStyle(Color.orange.opacity(0.35))
            }
            ForEach(timeline) { p in
                AreaMark(x: .value("Time", p.t), y: .value("Motion", p.e))
                    .foregroundStyle(TrendChart.ao5Color.opacity(0.5))
                LineMark(x: .value("Time", p.t), y: .value("Motion", p.e))
                    .foregroundStyle(TrendChart.ao5Color)
            }
        }
        .chartXScale(domain: 0...max(1, elapsed))
        .chartYScale(domain: 0...top)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { v in
                AxisValueLabel {
                    if let d = v.as(Double.self) { Text("\(Int(d))s").font(.system(size: 9)) }
                }
            }
        }
    }

    private func load() async {
        guard let rec = lastMotionSolve else { timeline = []; result = nil; return }
        let id = rec.id
        let loaded: Loaded? =
            await Task.detached(priority: .userInitiated) { () -> Loaded? in
                guard let d = MotionStore.shared.read(id) else { return nil }
                let env = PauseAnalyzer.envelope(d)
                return Loaded(timeline: PauseAnalyzer.downsampled(env.t, env.e),
                              result: PauseAnalyzer.analyze(d))
            }.value
        guard let loaded = loaded else { timeline = []; result = nil; return }
        timeline = loaded.timeline
        result = loaded.result
    }
}
