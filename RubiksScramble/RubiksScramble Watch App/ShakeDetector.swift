import Foundation
import CoreMotion

/// Shake-for-new-scramble. Device-motion user acceleration (gravity removed)
/// at 50 Hz; a sample whose magnitude is `threshold` g or more counts as a
/// shake, then `cooldown` seconds of deaf time so one shake fires once and
/// ordinary handling (turning the cube, setting the wrist down) does not.
/// Runs only between start() and stop(); the scramble screen calls start()
/// while it is visible and the app is active.
/// (MotionCapture.swift is not reused: it records solve data from the Timer's
/// device-motion stream; this needs its own light accelerometer stream.)
final class ShakeDetector {
    /// User-acceleration magnitude (g, gravity removed) that counts as a
    /// shake. Was 1.8 g of raw deviation in 1.4 (1), too insensitive on a
    /// Watch SE2. THE constant to tune.
    static let threshold = 1.15
    static let cooldown: TimeInterval = 0.7
    static let sampleInterval: TimeInterval = 1.0 / 50.0

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
        guard !running, manager.isDeviceMotionAvailable else { return }
        running = true
        lastFire = ProcessInfo.processInfo.systemUptime   // ignore the first second
        manager.deviceMotionUpdateInterval = Self.sampleInterval
        manager.startDeviceMotionUpdates(to: queue) { [weak self] data, _ in
            guard let self, let data else { return }
            let a = data.userAcceleration
            let mag = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
            guard mag >= Self.threshold else { return }
            let now = data.timestamp
            guard now - self.lastFire >= Self.cooldown else { return }
            self.lastFire = now
            DispatchQueue.main.async { onShake() }
        }
    }

    func stop() {
        guard running else { return }
        running = false
        manager.stopDeviceMotionUpdates()
    }

    deinit { manager.stopDeviceMotionUpdates() }
}
