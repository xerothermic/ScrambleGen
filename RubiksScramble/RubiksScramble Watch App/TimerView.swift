import SwiftUI
import CoreMotion
import WatchKit
import os

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

/// Logging for the Timer card (Console: subsystem com.pcintaiwan.scramblegen.watch,
/// category timer).
let timerLog = Logger(subsystem: "com.pcintaiwan.scramblegen.watch", category: "timer")

/// Single owner of the extended runtime session. Keeps the app running with the
/// wrist down while the timer counts down and runs. Needs WKBackgroundModes in
/// the watch app's Info.plist (BuildInfo.plist). Exactly one fresh session per
/// run; the old one is invalidated and its delegate cleared first; callbacks
/// from any session other than the current one are ignored. Never dismisses or
/// exits anything.
final class RuntimeKeeper: NSObject, WKExtendedRuntimeSessionDelegate {
    private var session: WKExtendedRuntimeSession?
    /// True while a run wants a session (between start() and stop()).
    private var wanted = false
    private var retries = 0
    private static let maxRetries = 2

    var isRunning: Bool { session?.state == .running }
    /// A session exists that is starting or running.
    var isActiveOrStarting: Bool {
        guard let s = session else { return false }
        return s.state == .running || s.state == .scheduled
    }

    /// Call on the main thread, with the app active.
    func start() {
        wanted = true
        retries = 0
        launch()
    }

    private func launch() {
        discardSession()
        let s = WKExtendedRuntimeSession()
        s.delegate = self
        session = s
        s.start()
        timerLog.info("runtime session start requested")
    }

    /// Call on the main thread.
    func stop() {
        wanted = false
        retries = 0
        if session != nil { timerLog.info("runtime session stop") }
        discardSession()
    }

    private func discardSession() {
        guard let s = session else { return }
        session = nil
        s.delegate = nil
        if s.state == .running || s.state == .scheduled { s.invalidate() }
    }

    func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let current = self.session === extendedRuntimeSession
            timerLog.info("runtime session did start (current: \(current, privacy: .public))")
        }
    }

    func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let current = self.session === extendedRuntimeSession
            timerLog.info("runtime session will expire (current: \(current, privacy: .public))")
        }
    }

    func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession,
                                didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
                                error: Error?) {
        let code = reason.rawValue
        let desc = error.map { "\($0)" } ?? "none"
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard self.session === extendedRuntimeSession else {
                timerLog.info("ignored stale session invalidation, reason \(code, privacy: .public)")
                return
            }
            timerLog.error("current runtime session invalidated, reason \(code, privacy: .public), error \(desc, privacy: .public)")
            self.session = nil
            // Lost the session while a run still wants one: try a fresh one
            // (only possible while the app is in the foreground).
            if self.wanted, self.retries < Self.maxRetries {
                self.retries += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self = self, self.wanted, self.session == nil else { return }
                    timerLog.info("retrying runtime session, attempt \(self.retries, privacy: .public)")
                    self.launch()
                }
            }
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
        guard phase == .idle || phase == .done else { return }
        countdownTask?.cancel()
        countdownTask = nil
        detector.stop()
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
        guard phase == .countdown || phase == .idle || phase == .done else { return }
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
        timerLog.info("reset")
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
                    .font(.system(size: 46, weight: .bold, design: .rounded))
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
            // Big Start button: >= 44 pt tall and wide (the whole screen also
            // starts it); the digits are 46 pt so it still fits a 40 mm screen.
            Button { beginCountdown() } label: {
                Text("Start")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 110, minHeight: 44)
                    .background(Capsule().fill(Color.accentColor))
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
            // Wrist Flick drops the app back to the clock mid-solve.
            Text("Tip: for solving, turn off Settings > Gestures > Wrist Flick.")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
                .lineLimit(2)
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
            if isLuminanceReduced {
                TimelineView(.periodic(from: countdownEnd, by: 1)) { context in
                    Text("\(Int(max(0, countdownEnd.timeIntervalSince(context.date)).rounded(.up)))")
                        .font(.system(size: 80, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.gray)
                }
            } else {
                TimelineView(.animation) { context in
                    let remaining = max(0, countdownEnd.timeIntervalSince(context.date))
                    Text("\(Int(remaining.rounded(.up)))")
                        .font(.system(size: 80, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(remaining <= 3 ? Color.orange : Color.white)
                }
            }
            Button("Cancel") { reset() }
                .font(.system(size: 14, weight: .medium))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var runningView: some View {
        VStack(spacing: 6) {
            // Always On: the UI only keeps updating through a TimelineView, and
            // dimmed it is limited to about 1 Hz, so drop the sub-second digits
            // and tick on whole seconds since the start.
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
        .onChange(of: phase) { old, new in
            timerLog.info("phase \(String(describing: old), privacy: .public) -> \(String(describing: new), privacy: .public)")
        }
        // Leaving the card (close, swipe, deep link) stops everything.
        .onDisappear { reset() }
        // Backgrounding aborts a countdown/run, unless the extended runtime
        // session is keeping the app alive (wrist down).
        .onChange(of: scenePhase) { _, new in
            timerLog.info("scenePhase \(String(describing: new), privacy: .public), phase \(String(describing: phase), privacy: .public), runtime running \(runtime.isRunning, privacy: .public)")
            if new != .active, phase == .countdown || phase == .running,
               !runtime.isRunning, !runtime.isActiveOrStarting {
                reset()
            }
        }
    }
}
