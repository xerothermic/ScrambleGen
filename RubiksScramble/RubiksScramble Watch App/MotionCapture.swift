import Foundation
import CoreMotion
import os

/// Buffers device motion for one solve. Fed from StopDetector's existing 50 Hz
/// stream (same CMMotionManager, nothing extra is started) AFTER the stop logic
/// has processed each sample, so recording cannot change when a solve stops.
/// Thread-safe: samples arrive on the detector's queue, finish() on main.
final class MotionRecorder {
    /// Hard cap: 3 minutes at 50 Hz. Longer solves keep their first 3 minutes.
    static let maxSamples = 9000

    private let lock = NSLock()
    private var t0: TimeInterval = 0
    private var buf: [Float] = []
    private var active = false

    func begin(runStart: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        t0 = runStart
        buf.removeAll(keepingCapacity: true)
        buf.reserveCapacity(MotionFile.floatsPerSample * 3200)
        active = true
    }

    func append(_ m: CMDeviceMotion) {
        lock.lock(); defer { lock.unlock() }
        guard active, buf.count < Self.maxSamples * MotionFile.floatsPerSample else { return }
        let t = m.timestamp - t0
        guard t >= 0 else { return }
        let a = m.userAcceleration, r = m.rotationRate
        buf.append(contentsOf: [Float(t), Float(a.x), Float(a.y), Float(a.z),
                                Float(r.x), Float(r.y), Float(r.z)])
    }

    /// Stops recording and hands over the samples (nil if nothing was active).
    func finish() -> [Float]? {
        lock.lock(); defer { lock.unlock() }
        guard active else { return nil }
        active = false
        let out = buf
        buf = []
        return out
    }

    func cancel() {
        lock.lock(); defer { lock.unlock() }
        active = false
        buf = []
    }
}

/// Compact binary file, little-endian:
///   "SGM1" | UInt32 sample count | UInt32 rate Hz | Float32 solve time (s)
///   then count x 7 Float32: t (s since run start), userAcceleration x y z (g),
///   rotationRate x y z (rad/s).
/// 28 bytes per sample: a 30 s solve is about 42 KB.
enum MotionFile {
    static let floatsPerSample = 7
    static let headerSize = 16
    static let magic: [UInt8] = Array("SGM1".utf8)

    struct Decoded {
        var elapsed: TimeInterval
        var samples: [Float]
        var count: Int { samples.count / MotionFile.floatsPerSample }
    }

    static func encode(samples: [Float], elapsed: TimeInterval) -> Data {
        var d = Data(magic)
        func put(_ v: UInt32) { var le = v.littleEndian; withUnsafeBytes(of: &le) { d.append(contentsOf: $0) } }
        put(UInt32(samples.count / floatsPerSample))
        put(UInt32(Int(1 / TimerCard.sampleInterval)))
        put(Float(elapsed).bitPattern)
        samples.withUnsafeBufferPointer { p in
            for f in p { put(f.bitPattern) }
        }
        return d
    }

    static func decode(_ data: Data) -> Decoded? {
        guard data.count >= headerSize, Array(data.prefix(4)) == magic else { return nil }
        func get(_ offset: Int) -> UInt32 {
            data.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self)) }
        }
        let count = Int(get(4))
        guard count >= 0, data.count >= headerSize + count * floatsPerSample * 4 else { return nil }
        let elapsed = TimeInterval(Float(bitPattern: get(12)))
        var out = [Float]()
        out.reserveCapacity(count * floatsPerSample)
        for i in 0..<(count * floatsPerSample) {
            out.append(Float(bitPattern: get(headerSize + i * 4)))
        }
        return Decoded(elapsed: elapsed, samples: out)
    }
}

/// Raw motion files, one per solve, in Application Support/Motion. At most
/// `maxFiles` are kept; the oldest go first (SolveStore applies the policy).
final class MotionStore {
    static let shared = MotionStore()
    static let maxFiles = 200

    let directory: URL
    private let log = Logger(subsystem: "com.pcintaiwan.scramblegen.watch", category: "motion")

    private init() {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        directory = base.appendingPathComponent("Motion", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func url(for id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).sgm") }

    func write(_ data: Data, for id: UUID) {
        do { try data.write(to: url(for: id), options: .atomic) }
        catch { log.error("motion write failed: \(String(describing: error), privacy: .public)") }
    }

    func read(_ id: UUID) -> MotionFile.Decoded? {
        guard let d = try? Data(contentsOf: url(for: id)) else { return nil }
        return MotionFile.decode(d)
    }

    func delete(_ id: UUID) { try? FileManager.default.removeItem(at: url(for: id)) }

    func deleteAll() {
        for f in files() { try? FileManager.default.removeItem(at: f) }
    }

    func files() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "sgm" }
    }

    /// (file count, total bytes)
    func usage() -> (count: Int, bytes: Int) {
        let fs = files()
        let bytes = fs.reduce(0) { sum, u in
            sum + ((try? FileManager.default.attributesOfItem(atPath: u.path)[.size] as? Int) ?? 0)
        }
        return (fs.count, bytes)
    }

    /// Deletes files whose solve id is not in `keep`.
    func prune(keeping keep: Set<UUID>) {
        for f in files() {
            let id = UUID(uuidString: f.deletingPathExtension().lastPathComponent)
            if id == nil || !keep.contains(id!) { try? FileManager.default.removeItem(at: f) }
        }
    }

    /// DEBUG builds only: logs what is on disk so the raw files can be pulled
    /// for offline validation (Xcode > Window > Devices and Simulators >
    /// Watch Scramble > Download Container, folder Library/Application
    /// Support/Motion; format in MotionFile). No network, nothing leaves the
    /// watch by itself. Release/TestFlight builds do not log this.
    func debugDump() {
        #if DEBUG
        let u = usage()
        log.info("motion files: \(u.count, privacy: .public), \(u.bytes, privacy: .public) bytes at \(self.directory.path, privacy: .public)")
        #endif
    }
}
