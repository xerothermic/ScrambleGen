import SwiftUI
import CoreMotion
import WatchKit

/// Constants for the Timer card (Wallet-stack card + the timer screen).
enum TimerCard {
    static let id = "timer"
    static let color = Color(red: 0.04, green: 0.45, blue: 0.92)

    // Inspection countdown (Digital Crown, persisted in @AppStorage).
    static let defaultCountdown = 15
    static let countdownRange = 0...30
    /// Seconds-remaining marks that get a haptic tick (zero gets the strong one).
    static let hapticTicks = [8, 3, 2, 1]

    /// TUNE ME: the stop gesture's spike. Peak userAcceleration magnitude, in g
    /// (gravity removed), that counts as the "slap" of the hand on the cube or
    /// table. Lower = more sensitive (and more false stops); higher = needs a
    /// harder slap.
    static let stopSpikeThreshold = 2.0
    /// Magnitude (g) below which the wrist counts as still after the spike.
    static let stillThreshold = 0.08
    /// How long it must stay still after the spike before the stop is accepted.
    static let stillDuration: TimeInterval = 0.5
    /// Motion is ignored this long after the run starts, so the start tap
    /// itself can't stop the timer.
    static let startLockout: TimeInterval = 1.0
    /// A spike that isn't followed by stillness within this long is forgotten.
    static let spikeTimeout: TimeInterval = 2.0
    /// Motion sampling interval (50 Hz).
    static let sampleInterval: TimeInterval = 1.0 / 50.0

    /// Solve times kept for the session (in memory only).
    static let maxSolves = 20

    /// "8.42", "1:02.42"; without centiseconds (dimmed always-on display):
    /// "8", "1:02".
    static func format(_ time: TimeInterval, centis: Bool = true) -> String {
        let total = Int((max(0, time) * 100).rounded(.down))
        let m = total / 6000
        let s = (total / 100) % 60
        let c = total % 100
        if centis {
            return m > 0
                ? String(format: "%d:%02d.%02d", m, s, c)
                : String(format: "%d.%02d", s, c)
        }
        return m > 0 ? String(format: "%d:%02d", m, s) : "\(s)"
    }
}

/// Watches the accelerometer for the stop pattern: one sharp spike (hand
/// slapping the cube or table), then about half a second of stillness. Reports
/// the time of the spike, not of the stillness. Times are system-uptime seconds,
/// the same clock as CMLogItem.timestamp.
final class StopDetector {
    private lazy var manager = CMMotionManager()
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        return q
    }()

    // Touched only on `queue` once updates are running.
    private var armedAt: TimeInterval = 0
    private var spikeAt: TimeInterval?
    private var lastSpikeAt: TimeInterval = 0
    private var stillSince: TimeInterval?
    private var fired = false

    /// `onStop` runs on the main queue with the spike's uptime timestamp.
    func start(runStart: TimeInterval, onStop: @escaping (TimeInterval) -> Void) {
        stop()
        guard manager.isDeviceMotionAvailable else { return }
        armedAt = runStart + TimerCard.startLockout
        spikeAt = nil
        lastSpikeAt = 0
        stillSince = nil
        fired = false
        manager.deviceMotionUpdateInterval = TimerCard.sampleInterval
        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let self = self, let motion = motion else { return }
            self.process(motion.userAcceleration, at: motion.timestamp, onStop: onStop)
        }
    }

    func stop() {
        guard manager.isDeviceMotionActive else { return }
        manager.stopDeviceMotionUpdates()
    }

    private func process(_ a: CMAcceleration, at t: TimeInterval,
                         onStop: @escaping (TimeInterval) -> Void) {
        guard !fired, t >= armedAt else { return }
        let magnitude = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
        if magnitude >= TimerCard.stopSpikeThreshold {
            // First spike of a cluster is the impact; bounces extend the cluster.
            if spikeAt == nil { spikeAt = t }
            lastSpikeAt = t
            stillSince = nil
        } else if let spike = spikeAt {
            if magnitude < TimerCard.stillThreshold {
                if stillSince == nil { stillSince = t }
                if let since = stillSince, t - since >= TimerCard.stillDuration {
                    fired = true
                    DispatchQueue.main.async { onStop(spike) }
                }
            } else {
                stillSince = nil
                if t - lastSpikeAt > TimerCard.spikeTimeout { spikeAt = nil }
            }
        }
    }
}

/// Keeps the app running with the wrist down while the timer counts down and
/// runs. Needs WKBackgroundModes in the watch app's Info.plist (BuildInfo.plist).
final class RuntimeKeeper: NSObject, WKExtendedRuntimeSessionDelegate {
    private var session: WKExtendedRuntimeSession?

    var isRunning: Bool { session?.state == .running }

    func start() {
        if let s = session, s.state == .running || s.state == .scheduled { return }
        let s = WKExtendedRuntimeSession()
        s.delegate = self
        s.start()
        session = s
    }

    func stop() {
        if let s = session, s.state != .invalid { s.invalidate() }
        session = nil
    }

    func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {}

    func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {}

    func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession,
                                didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
                                error: Error?) {
        DispatchQueue.main.async { [weak self] in
            if self?.session === extendedRuntimeSession { self?.session = nil }
        }
    }
}

private func sleepUntil(until date: Date) async {
    let seconds = date.timeIntervalSinceNow
    if seconds > 0 { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
}

struct TimerScreen: View {
    /// This session's solve times, oldest first (owned by ContentView so they
    /// survive closing and reopening the card).
    @Binding var solves: [TimeInterval]

    @AppStorage("timerCountdown") private var countdown = TimerCard.defaultCountdown
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    private enum Phase { case idle, countdown, running, done }
    @State private var phase: Phase = .idle
    @State private var crown = Double(TimerCard.defaultCountdown)
    @FocusState private var crownFocused: Bool

    @State private var countdownEnd = Date()
    @State private var runStart = Date()
    @State private var runStartUptime: TimeInterval = 0
    @State private var finalTime: TimeInterval = 0
    @State private var countdownTask: Task<Void, Never>?
    @State private var detector = StopDetector()
    @State private var runtime = RuntimeKeeper()

    private var seconds: Int {
        min(max(countdown, TimerCard.countdownRange.lowerBound),
            TimerCard.countdownRange.upperBound)
    }

    private var best: TimeInterval? { solves.min() }

    // MARK: Flow

    private func beginCountdown() {
        let total = seconds
        runtime.start()
        guard total > 0 else { beginRun(); return }
        let end = Date().addingTimeInterval(TimeInterval(total))
        countdownEnd = end
        phase = .countdown
        countdownTask = Task { @MainActor in
            for tick in TimerCard.hapticTicks where tick < total {
                await sleepUntil(until: end.addingTimeInterval(-TimeInterval(tick)))
                if Task.isCancelled { return }
                WKInterfaceDevice.current().play(.click)
            }
            await sleepUntil(until: end)
            if Task.isCancelled { return }
            WKInterfaceDevice.current().play(.notification)
            beginRun()
        }
    }

    private func beginRun() {
        countdownTask = nil
        let startUptime = ProcessInfo.processInfo.systemUptime
        runStart = Date()
        runStartUptime = startUptime
        phase = .running
        detector.start(runStart: startUptime) { spike in
            motionStop(atUptime: spike)
        }
    }

    private func motionStop(atUptime spike: TimeInterval) {
        guard phase == .running,
              spike >= runStartUptime + TimerCard.startLockout else { return }
        finish(elapsed: spike - runStartUptime)
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
        solves.append(finalTime)
        if solves.count > TimerCard.maxSolves {
            solves.removeFirst(solves.count - TimerCard.maxSolves)
        }
        phase = .done
        WKInterfaceDevice.current().play(.stop)
    }

    /// Back to the idle screen; stops the task, the motion manager and the
    /// extended runtime session.
    private func reset() {
        countdownTask?.cancel()
        countdownTask = nil
        detector.stop()
        runtime.stop()
        phase = .idle
    }

    // MARK: Screens

    private var idleView: some View {
        VStack(spacing: 4) {
            Text("Inspection")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(seconds)")
                    .font(.system(size: 60, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("s")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            if let best = best {
                Text("Best \(TimerCard.format(best))")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Text("Tap to start")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.accentColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { beginCountdown() }
        .focusable()
        .focused($crownFocused)
        .digitalCrownRotation(
            $crown,
            from: Double(TimerCard.countdownRange.lowerBound),
            through: Double(TimerCard.countdownRange.upperBound),
            by: 1.0,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: crown) { _, v in countdown = Int(v.rounded()) }
        .onAppear {
            crown = Double(seconds)
            crownFocused = true
        }
    }

    private var countdownView: some View {
        VStack(spacing: 4) {
            Text("Inspection")
                .font(.caption2)
                .foregroundStyle(.secondary)
            TimelineView(.animation) { context in
                let remaining = max(0, countdownEnd.timeIntervalSince(context.date))
                Text("\(Int(remaining.rounded(.up)))")
                    .font(.system(size: 80, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(remaining <= 3 ? Color.orange : Color.white)
            }
            Button("Cancel") { reset() }
                .font(.system(size: 14, weight: .medium))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var runningView: some View {
        VStack(spacing: 6) {
            TimelineView(.animation) { context in
                Text(TimerCard.format(context.date.timeIntervalSince(runStart),
                                      centis: !isLuminanceReduced))
                    .font(.system(size: 42, weight: .semibold, design: .monospaced))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(isLuminanceReduced ? Color.gray : Color.white)
            }
            if !isLuminanceReduced {
                Text("Slap to stop · or tap")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { tapStop() }
    }

    private var doneView: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text(TimerCard.format(finalTime))
                    .font(.system(size: 40, weight: .bold, design: .monospaced))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                if let best = best {
                    Text(finalTime <= best && solves.count > 1
                         ? "New best!"
                         : "Best \(TimerCard.format(best))")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Button {
                    beginCountdown()
                } label: {
                    Text("Again")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3)
                }
                .buttonStyle(.borderedProminent)

                VStack(spacing: 2) {
                    ForEach(Array(solves.suffix(5).reversed().enumerated()), id: \.offset) { item in
                        HStack {
                            Text("\(solves.count - item.offset)")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(TimerCard.format(item.element))
                        }
                        .font(.system(size: 13, design: .monospaced))
                    }
                }
                .padding(.horizontal, 6)

                Button("Reset") {
                    solves = []
                    reset()
                }
                .font(.system(size: 14, weight: .medium))
            }
            .padding(.horizontal, 4)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .idle: idleView
                case .countdown: countdownView
                case .running: runningView
                case .done: doneView
                }
            }
            .modifier(CloseAwareTitle(title: "Timer"))
        }
        // Leaving the card (close, swipe, deep link) stops everything.
        .onDisappear { reset() }
        // Backgrounding aborts a countdown/run, unless the extended runtime
        // session is keeping the app alive (wrist down).
        .onChange(of: scenePhase) { _, new in
            if new != .active, phase == .countdown || phase == .running,
               !runtime.isRunning {
                reset()
            }
        }
    }
}
