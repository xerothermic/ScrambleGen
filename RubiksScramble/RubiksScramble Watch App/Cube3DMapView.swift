import SwiftUI
import CoreMotion
import simd

/// Live attitude for the 3D cube map. Device motion at 30 Hz; the pose is the
/// rotation since the last recenter, low-pass filtered with a quaternion
/// nlerp so the cube follows the wrist without jitter. Runs only between
/// start() and stop().
final class CubeAttitude: ObservableObject {
    /// Rotation of the device frame relative to the pose at recenter time
    /// (maps recenter-frame vectors to current device-frame vectors).
    @Published private(set) var rotation = matrix_identity_float3x3

    /// Smoothing: weight of the newest sample (1 = no smoothing).
    static let smoothing: Float = 0.25
    /// The wrist rotation is multiplied by this so a ~40 deg tilt turns the
    /// cube ~100 deg (hidden faces come into view), clamped to `maxAngle`.
    static let gain: Float = 2.5
    static let maxAngle: Float = 120 * .pi / 180

    private let manager = CMMotionManager()
    private var reference: simd_float3x3?
    private var smoothed: simd_quatf?
    private var needsRecenter = true

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        needsRecenter = true
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let m = motion else { return }
            let r = m.attitude.rotationMatrix
            let cur = simd_float3x3(columns: (
                SIMD3(Float(r.m11), Float(r.m21), Float(r.m31)),
                SIMD3(Float(r.m12), Float(r.m22), Float(r.m32)),
                SIMD3(Float(r.m13), Float(r.m23), Float(r.m33))))
            if self.needsRecenter || self.reference == nil {
                self.reference = cur
                self.smoothed = nil
                self.needsRecenter = false
            }
            let rel = cur * self.reference!.transpose
            var q = simd_quatf(rel)
            if let prev = self.smoothed {
                if simd_dot(prev.vector, q.vector) < 0 { q = simd_quatf(vector: -q.vector) }
                q = simd_normalize(simd_quatf(vector: prev.vector * (1 - Self.smoothing)
                                                       + q.vector * Self.smoothing))
            }
            self.smoothed = q
            self.rotation = simd_float3x3(Self.amplified(q))
        }
    }

    private static func amplified(_ q: simd_quatf) -> simd_quatf {
        let s = q.real < 0 ? simd_quatf(vector: -q.vector) : q   // shortest arc
        let angle = s.angle
        guard angle > 1e-4 else { return s }
        return simd_quatf(angle: min(angle * gain, maxAngle), axis: s.axis)
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        rotation = matrix_identity_float3x3
    }

    /// Makes the current wrist pose the neutral view.
    func recenter() {
        needsRecenter = true
    }

    deinit { manager.stopDeviceMotionUpdates() }
}

/// Shared 3D map shell: wrist tilt (CubeAttitude), finger drag rotation,
/// double-tap recenter, and starting/stopping motion updates when the page is
/// hidden, the view disappears or the app leaves the foreground. The caller
/// supplies the drawing, which receives the full view rotation (finger *
/// wrist * resting pose) and projects through `Map3DView.projector`.
struct Map3DView: View {
    let title: String
    let active: Bool
    let draw: (inout GraphicsContext, CGSize, simd_float3x3) -> Void

    @StateObject private var attitude = CubeAttitude()
    @AppStorage(GeneralSettings.cube3DTiltKey) private var tilt = GeneralSettings.defaultCube3DTilt
    /// Finger rotation (degrees), added on top of the wrist pose.
    @State private var yaw: Float = 0
    @State private var pitch: Float = 0
    @State private var dragStart: (yaw: Float, pitch: Float)?
    @Environment(\.scenePhase) private var scenePhase

    /// Resting view: tilt toward the viewer 25 deg, turn 35 deg, so the top,
    /// front and right sides show.
    static let base: simd_float3x3 = rotation(pitch: 25, yaw: -35)

    /// View-space rotation: yaw about the screen's vertical axis, pitch about the horizontal.
    static func rotation(pitch: Float, yaw: Float) -> simd_float3x3 {
        let a = pitch * .pi / 180, b = yaw * .pi / 180
        let rx = simd_float3x3(rows: [SIMD3(1, 0, 0), SIMD3(0, cos(a), -sin(a)), SIMD3(0, sin(a), cos(a))])
        let ry = simd_float3x3(rows: [SIMD3(cos(b), 0, sin(b)), SIMD3(0, 1, 0), SIMD3(-sin(b), 0, cos(b))])
        return rx * ry
    }

    /// Perspective projection of model points: camera `camera` units from the
    /// centre, `scale` points per unit.
    static func projector(_ m: simd_float3x3, size: CGSize, scale: Float,
                          camera: Float) -> (SIMD3<Float>) -> CGPoint {
        let cx = Float(size.width) / 2, cy = Float(size.height) / 2
        return { p in
            let q = m * p
            let k = camera / (camera - q.z)
            return CGPoint(x: CGFloat(cx + q.x * scale * k), y: CGFloat(cy - q.y * scale * k))
        }
    }

    /// Back-face test shared by the 3D maps. `n` and `center` are in model
    /// space; both are rotated by `m` and the face is front-facing when its
    /// rotated normal points toward the eye at (0, 0, camera), using the vector
    /// from the face centre to the eye (not just the z component).
    static func isFrontFacing(_ m: simd_float3x3, normal n: SIMD3<Float>,
                              center: SIMD3<Float>, camera: Float) -> Bool {
        let eye = SIMD3<Float>(0, 0, camera)
        return simd_dot(m * n, eye - m * center) > 0.001
    }

    var body: some View {
        NavigationStack {
            Canvas { ctx, size in
                draw(&ctx, size,
                     Self.rotation(pitch: pitch, yaw: yaw) * attitude.rotation * Self.base)
            }
            .contentShape(Rectangle())
            // Finger drag rotates the model (works with the wrist switch off).
            // High priority so the page TabView does not take the vertical
            // drag; the Digital Crown still switches pages.
            .highPriorityGesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { v in
                        let s = dragStart ?? (yaw, pitch)
                        dragStart = s
                        yaw = s.yaw + Float(v.translation.width) * 0.9
                        pitch = max(-90, min(90, s.pitch + Float(v.translation.height) * 0.9))
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .onTapGesture(count: 2) { attitude.recenter(); yaw = 0; pitch = 0 }
            .modifier(CloseAwareTitle(title: title))
            .hidingTime()
        }
        .onAppear { sync() }
        .onDisappear { attitude.stop() }
        .onChange(of: active) { sync() }
        .onChange(of: scenePhase) { sync() }
        .onChange(of: tilt) { sync() }
    }

    private func sync() {
        if active && tilt && scenePhase == .active { attitude.start() } else { attitude.stop() }
    }
}

/// 3x3 map as a perspective 3D cube (three faces visible at rest, whichever
/// are turned toward you as the wrist moves) carrying the scramble state.
struct Cube3DMapView: View {
    let moves: [String]
    let active: Bool

    /// Per face: outward normal, then the directions of increasing column and
    /// increasing row, matching the flat net (U top row is the back edge).
    private static func axes(_ f: CubeFace) -> (n: SIMD3<Float>, right: SIMD3<Float>, down: SIMD3<Float>) {
        switch f {
        case .front: return (SIMD3(0, 0, 1), SIMD3(1, 0, 0), SIMD3(0, -1, 0))
        case .back: return (SIMD3(0, 0, -1), SIMD3(-1, 0, 0), SIMD3(0, -1, 0))
        // Up: row 0 is the back edge, so rows run toward the front (+z).
        // Down: row 0 is the front edge, so rows run toward the back (-z).
        case .up: return (SIMD3(0, 1, 0), SIMD3(1, 0, 0), SIMD3(0, 0, 1))
        case .down: return (SIMD3(0, -1, 0), SIMD3(1, 0, 0), SIMD3(0, 0, -1))
        case .right: return (SIMD3(1, 0, 0), SIMD3(0, 0, -1), SIMD3(0, -1, 0))
        case .left: return (SIMD3(-1, 0, 0), SIMD3(0, 0, 1), SIMD3(0, -1, 0))
        }
    }

    var body: some View {
        let cube = CubeState.scrambled(by: moves)
        Map3DView(title: "Cube", active: active) { ctx, size, m in
            draw(&ctx, size: size, cube: cube, rotation: m)
        }
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, cube: CubeState, rotation m: simd_float3x3) {
        // Cube side is 3 units; the camera sits 9 units from the centre, so the
        // projected size grows a little for near corners. The scale keeps the
        // 4.3-unit diagonal inside the smaller screen dimension (40 mm fits).
        let scale = Float(min(size.width, size.height)) / 5.4
        let camera: Float = 9
        let project = Map3DView.projector(m, size: size, scale: scale, camera: camera)
        func quad(_ o: SIMD3<Float>, _ u: SIMD3<Float>, _ v: SIMD3<Float>) -> Path {
            var path = Path()
            path.move(to: project(o))
            path.addLine(to: project(o + u))
            path.addLine(to: project(o + u + v))
            path.addLine(to: project(o + v))
            path.closeSubpath()
            return path
        }
        let inset: Float = 0.05
        // Cull faces turned away from the eye, then paint far to near by the
        // rotated centre depth (+z is toward the camera).
        var visible: [(depth: Float, face: CubeFace)] = []
        for face in CubeFace.allCases {
            let n = Self.axes(face).n
            let center = n * 1.5
            guard Map3DView.isFrontFacing(m, normal: n, center: center, camera: camera) else { continue }
            visible.append(((m * center).z, face))
        }
        visible.sort { $0.depth < $1.depth }
        for (_, face) in visible {
            let ax = Self.axes(face)
            let origin = ax.n * 1.5 - ax.right * 1.5 - ax.down * 1.5
            ctx.fill(quad(origin, ax.right * 3, ax.down * 3), with: .color(Color(white: 0.08)))
            for r in 0..<3 {
                for c in 0..<3 {
                    let o = origin + ax.right * (Float(c) + inset) + ax.down * (Float(r) + inset)
                    let s = 1 - 2 * inset
                    ctx.fill(quad(o, ax.right * s, ax.down * s),
                             with: .color(cube.color(face: face, row: r, col: c)))
                }
            }
        }
    }
}
