import Foundation
import CoreMotion

/// Shake-for-new-scramble. Raw accelerometer (includes gravity) at 25 Hz; a
/// sample whose magnitude differs from 1 g by `threshold` or more counts as a
/// shake, then `cooldown` seconds of deaf time so one shake fires once and
/// ordinary handling (turning the cube, setting the wrist down) does not.
/// Runs only between start() and stop(); the scramble screen calls start()
/// while it is visible and the app is active.
/// (MotionCapture.swift is not reused: it records solve data from the Timer's
/// device-motion stream; this needs its own light accelerometer stream.)
final class ShakeDetector {
    /// Deviation from 1 g that counts as a shake. Wrist flicks are ~0.5-1 g,
    /// a deliberate shake is 2+ g. THE constant to tune.
    static let threshold = 1.8
    static let cooldown: TimeInterval = 1.0
    static let sampleInterval: TimeInterval = 1.0 / 25.0

    private let manager = CMMotionManager()
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        return q
    }()
    private var lastFire: TimeInterval = 0   // touched on `queue` only
    private var running = false              // touched on main only

    /// `onShake` is called on the main queue.
    func start(onShake: @escaping () -> Void) {
        guard !running, manager.isAccelerometerAvailable else { return }
        running = true
        lastFire = ProcessInfo.processInfo.systemUptime   // ignore the first second
        manager.accelerometerUpdateInterval = Self.sampleInterval
        manager.startAccelerometerUpdates(to: queue) { [weak self] data, _ in
            guard let self, let a = data?.acceleration else { return }
            let mag = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
            guard abs(mag - 1) >= Self.threshold else { return }
            let now = data!.timestamp
            guard now - self.lastFire >= Self.cooldown else { return }
            self.lastFire = now
            DispatchQueue.main.async { onShake() }
        }
    }

    func stop() {
        guard running else { return }
        running = false
        manager.stopAccelerometerUpdates()
    }

    deinit { manager.stopAccelerometerUpdates() }
}
