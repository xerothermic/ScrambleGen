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

/// One flat convex polygon of a solid. `color` nil = not drawn (interior wall
/// kept only for the ordering test). `sticker` is painted inset on top.
struct Face3D {
    var points: [SIMD3<Float>]
    var color: Color?
    var sticker: Color? = nil
    var stroke = false
    /// Outward unit normal and plane offset (n . p), set by `Solid3D`.
    var normal = SIMD3<Float>.zero
    var offset: Float = 0
}

/// A convex solid made of `Face3D`s. Normals are derived from the vertices
/// (Newell) and oriented away from the solid's centroid, so winding does not
/// matter.
struct Solid3D {
    var faces: [Face3D]
    var vertices: [SIMD3<Float>]

    init(_ input: [Face3D]) {
        vertices = input.flatMap { $0.points }
        let c = vertices.reduce(SIMD3<Float>.zero, +) / Float(max(vertices.count, 1))
        faces = input.map { f in
            var f = f
            var n = SIMD3<Float>.zero
            for i in f.points.indices {
                let a = f.points[i], b = f.points[(i + 1) % f.points.count]
                n += SIMD3((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y))
            }
            n = simd_normalize(n)
            let fc = f.points.reduce(SIMD3<Float>.zero, +) / Float(f.points.count)
            if simd_dot(n, fc - c) < 0 { n = -n }
            f.normal = n
            f.offset = simd_dot(n, f.points[0])
            return f
        }
    }
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

    /// Draws convex solids with a robust visibility order (no per-polygon
    /// painter sort). Solids are ordered by `paintOrder`; within one convex
    /// solid the faces that point toward the eye never overlap on screen, so
    /// culling back faces is all that is needed there.
    static func drawSolids(_ ctx: inout GraphicsContext, _ solids: [Solid3D],
                           rotation m: simd_float3x3, size: CGSize, scale: Float, camera: Float) {
        let project = projector(m, size: size, scale: scale, camera: camera)
        let eye = SIMD3<Float>(0, 0, camera)
        func path(_ pts: [SIMD3<Float>]) -> Path {
            var p = Path()
            p.move(to: project(pts[0]))
            for q in pts.dropFirst() { p.addLine(to: project(q)) }
            p.closeSubpath()
            return p
        }
        for i in paintOrder(solids, rotation: m, camera: camera) {
            for f in solids[i].faces {
                guard let color = f.color,
                      simd_dot(m * f.normal, eye - m * f.points[0]) > 0.001 else { continue }
                ctx.fill(path(f.points), with: .color(color))
                if let st = f.sticker {
                    let c = f.points.reduce(SIMD3<Float>.zero, +) / Float(f.points.count)
                    ctx.fill(path(f.points.map { c + ($0 - c) * 0.9 }), with: .color(st))
                }
                if f.stroke {
                    ctx.stroke(path(f.points), with: .color(.black),
                               style: StrokeStyle(lineWidth: 0.8, lineJoin: .round))
                }
            }
        }
    }

    /// Back-to-front order of convex, non-overlapping solids for an eye at
    /// (0, 0, camera) in view space. A is in front of B when a face plane of A or
    /// B separates them with the eye on A's side: B can then never hide A. That gives a partial order, drawn by topological
    /// sort (farthest centre first among the free ones); a cycle (cannot occur
    /// for these puzzles) falls back to the farthest remaining solid.
    static func paintOrder(_ solids: [Solid3D], rotation m: simd_float3x3, camera: Float) -> [Int] {
        let eye = SIMD3<Float>(0, 0, camera)
        let eps: Float = 1e-4
        let n = solids.count
        let verts = solids.map { $0.vertices.map { m * $0 } }
        let planes = solids.map { s in s.faces.map { f in (n: m * f.normal, d: simd_dot(m * f.normal, m * f.points[0])) } }
        let depth = verts.map { v in v.reduce(0) { $0 + $1.z } / Float(max(v.count, 1)) }
        // a in front of b: a plane that separates them with the eye on a's side.
        func inFront(_ a: Int, _ b: Int) -> Bool {
            // Plane of b (outward normal): a entirely outside it, eye outside too.
            for pl in planes[b] where simd_dot(pl.n, eye) - pl.d > eps {
                if verts[a].allSatisfy({ simd_dot(pl.n, $0) - pl.d >= -eps }) { return true }
            }
            // Plane of a: b entirely outside it, eye inside (on a's side).
            for pl in planes[a] where simd_dot(pl.n, eye) - pl.d < -eps {
                if verts[b].allSatisfy({ simd_dot(pl.n, $0) - pl.d >= -eps }) { return true }
            }
            return false
        }
        var after = [[Int]](repeating: [], count: n)   // after[j]: must be drawn after j
        var indegree = [Int](repeating: 0, count: n)
        for a in 0..<n {
            for b in (a + 1)..<max(n, a + 1) {
                // Both true: neither can hide the other, so no constraint.
                let ab = inFront(a, b), ba = inFront(b, a)
                if ab && !ba { after[b].append(a); indegree[a] += 1 }
                else if ba && !ab { after[a].append(b); indegree[b] += 1 }
            }
        }
        var done = [Bool](repeating: false, count: n)
        var order: [Int] = []
        for _ in 0..<n {
            var free = (0..<n).filter { !done[$0] && indegree[$0] == 0 }
            if free.isEmpty { free = (0..<n).filter { !done[$0] } }
            let pick = free.min { depth[$0] < depth[$1] }!
            done[pick] = true
            order.append(pick)
            for x in after[pick] { indegree[x] -= 1 }
        }
        return order
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
        Map3DView.drawSolids(&ctx, Self.cubies(cube), rotation: m, size: size, scale: scale, camera: 9)
    }

    /// 26 unit cubies at -1...1. Only outer faces are drawn (dark body with the
    /// inset sticker); inner faces are kept (colour nil) for the ordering.
    private static func cubies(_ cube: CubeState) -> [Solid3D] {
        let dirs: [SIMD3<Float>] = [SIMD3(1, 0, 0), SIMD3(-1, 0, 0), SIMD3(0, 1, 0),
                                    SIMD3(0, -1, 0), SIMD3(0, 0, 1), SIMD3(0, 0, -1)]
        var out: [Solid3D] = []
        for x in -1...1 { for y in -1...1 { for z in -1...1 where !(x == 0 && y == 0 && z == 0) {
            let cc = SIMD3<Float>(Float(x), Float(y), Float(z))
            var faces: [Face3D] = []
            for d in dirs {
                // Two tangent axes of this face.
                let u: SIMD3<Float> = d.x != 0 ? SIMD3(0, 1, 0) : SIMD3(1, 0, 0)
                let v: SIMD3<Float> = d.z != 0 ? SIMD3(0, 1, 0) : SIMD3(0, 0, 1)
                let c = cc + d * 0.5
                let pts = [c - u * 0.5 - v * 0.5, c + u * 0.5 - v * 0.5, c + u * 0.5 + v * 0.5, c - u * 0.5 + v * 0.5]
                var face = Face3D(points: pts, color: nil)
                if simd_dot(cc, d) > 0.5 {
                    let f = CubeFace.allCases.first { axes($0).n == d }!
                    let ax = axes(f)
                    let r = Int(simd_dot(cc, ax.down).rounded()) + 1
                    let col = Int(simd_dot(cc, ax.right).rounded()) + 1
                    face.color = Color(white: 0.08)
                    face.sticker = cube.color(face: f, row: r, col: col)
                }
                faces.append(face)
            }
            out.append(Solid3D(faces))
        } } }
        return out
    }
}
