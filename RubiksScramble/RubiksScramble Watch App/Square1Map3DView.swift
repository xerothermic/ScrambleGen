import SwiftUI
import simd

/// Square-1 map as a perspective 3D model: top and bottom layers built from
/// the same piece cells as the flat map (30 degree edge wedges, 60 degree
/// corner kites, stickers from `Square1Drawing`), and the middle layer as two
/// half-prisms whose right half is turned over when the slice is flipped.
/// Rotation, wrist tilt, finger drag and recenter come from `Map3DView`.
struct Square1Map3DView: View {
    let moves: [String]
    let active: Bool

    var body: some View {
        let solids = Square1Model.solids(for: Square1State.scrambled(by: moves))
        Map3DView(title: "Square-1", active: active) { ctx, size, m in
            // Model radius is 1 (corner tips 1.37, half height 0.7); the scale
            // keeps the ~1.55 bounding radius inside the screen with perspective.
            let scale = Float(min(size.width, size.height)) / 3.9
            Map3DView.drawSolids(&ctx, solids, rotation: m, size: size, scale: scale, camera: 6)
        }
    }
}

private enum Square1Model {
    /// Layer thickness and middle-layer thickness (model units, edge radius 1).
    static let layer: Float = 0.5
    static let middle: Float = 0.4
    /// Half side of the cube-shaped middle layer: edge chord distance cos 15.
    static let half: Float = cos(15 * .pi / 180)
    static let inside = Color(white: 0.12)

    /// Every piece (12 top cells grouped into wedges/kites, same at the bottom)
    /// and the two middle half-prisms is its own convex solid.
    static func solids(for state: Square1State) -> [Solid3D] {
        var out: [Solid3D] = []
        addLayer(Array(state.pieces[0..<12]), top: true, into: &out)
        addLayer(Array(state.pieces[12..<24]), top: false, into: &out)
        addMiddle(flipped: !state.sliceSolved, into: &out)
        return out
    }

    // MARK: Layers

    /// Same cell walk as the flat `drawFace`: the top starts at 105 degrees,
    /// the bottom at -105 (seen from below, front at the top of the screen),
    /// clockwise in screen coordinates, 30 degrees per cell.
    private static func addLayer(_ cells: [Int], top: Bool, into out: inout [Solid3D]) {
        let inner = (top ? 1 : -1) * middle / 2
        let outer = (top ? 1 : -1) * (middle / 2 + layer)
        let startDegrees: Float = top ? 105 : -105
        let first = (0..<12).first { cells[$0] != cells[($0 + 11) % 12] } ?? 0
        var degrees = startDegrees + Float(first) * 30
        var cell = first
        while cell < first + 12 {
            let piece = cells[cell % 12]
            let corner = Square1Drawing.isCorner(piece)
            let fills = Square1Drawing.colors(of: piece)
            let a = degrees * .pi / 180
            // Piece outline in its local planar frame: face polygon, then the
            // rim segments that carry the side stickers (fills[1...]).
            let poly = corner ? cornerPolygon() : edgePolygon()
            func world(_ p: SIMD2<Float>, _ y: Float) -> SIMD3<Float> {
                let sx = p.x * cos(a) - p.y * sin(a)
                let sy = p.x * sin(a) + p.y * cos(a)
                return SIMD3(sx, y, top ? sy : -sy)
            }
            var faces = [Face3D(points: poly.map { world($0, outer) }, color: fills[0], stroke: true),
                         // Dark inner side so a layer looks solid from the other side.
                         Face3D(points: poly.map { world($0, inner) }, color: inside, stroke: true)]
            // Walls: polygon edge i -> i+1 carries sticker fills[i] on the rim;
            // the two walls touching the centre are interior (colour nil).
            for i in poly.indices {
                let j = (i + 1) % poly.count
                let rim = i >= 1 && j >= 1
                faces.append(Face3D(points: [world(poly[i], outer), world(poly[j], outer),
                                             world(poly[j], inner), world(poly[i], inner)],
                                    color: rim ? fills[i] : nil, stroke: true))
            }
            out.append(Solid3D(faces))
            let span = corner ? 2 : 1
            degrees += Float(span) * 30
            cell += span
        }
    }

    private static func edgePolygon() -> [SIMD2<Float>] {
        [SIMD2(0, 0), SIMD2(1, 0), SIMD2(sqrt(3) / 2, 0.5)]
    }

    /// Kite: centre, (1,0), outer tip at 30 degrees, then 60 degrees.
    private static func cornerPolygon() -> [SIMD2<Float>] {
        let angle: Float = 75 * .pi / 180
        let outer = SIMD2<Float>(1 + cos(angle) / sqrt(2), sin(angle) / sqrt(2))
        return [SIMD2(0, 0), SIMD2(1, 0), outer, SIMD2(0.5, sqrt(3) / 2)]
    }

    // MARK: Middle layer

    /// The cut between the halves runs along 105/285 degrees (screen), so its
    /// normal in the (x, z) plane is 15 degrees from the +x axis. The right half
    /// (x > 0 side: top cells 6-11, bottom cells 0-5) turns over about that
    /// normal on a slice: along the cut it mirrors, top and bottom swap (the
    /// prism is symmetric in y), and its stickers travel with it.
    private static func addMiddle(flipped: Bool, into out: inout [Solid3D]) {
        let d = SIMD2<Float>(cos(15 * .pi / 180), sin(15 * .pi / 180))
        let along = SIMD2<Float>(-d.y, d.x)
        let square: [SIMD2<Float>] = [SIMD2(half, half), SIMD2(-half, half),
                                      SIMD2(-half, -half), SIMD2(half, -half)]
        for right in [false, true] {
            let poly = clip(square, keeping: right ? d : -d)
            let turn = right && flipped
            func map(_ p: SIMD2<Float>) -> SIMD2<Float> {
                turn ? p - 2 * simd_dot(p, along) * along : p
            }
            let moved = poly.map(map)
            let h = middle / 2
            func p3(_ p: SIMD2<Float>, _ y: Float) -> SIMD3<Float> { SIMD3(p.x, y, p.y) }
            var faces = [Face3D(points: moved.map { p3($0, h) }, color: inside, stroke: true),
                         Face3D(points: moved.map { p3($0, -h) }, color: inside, stroke: true)]
            for i in 0..<poly.count {
                let a = poly[i], b = poly[(i + 1) % poly.count]
                var color: Color?   // nil: the cut face, interior
                if !(abs(simd_dot(a, d)) < 1e-4 && abs(simd_dot(b, d)) < 1e-4) {
                    // Sticker colour from the ORIGINAL outward direction of the side.
                    let mid = (a + b) / 2
                    let idx = abs(mid.x) > abs(mid.y) ? (mid.x < 0 ? 0 : 2) : (mid.y < 0 ? 1 : 3)
                    color = Square1Drawing.scheme[idx]
                }
                let p = map(a), q = map(b)
                faces.append(Face3D(points: [p3(p, h), p3(q, h), p3(q, -h), p3(p, -h)],
                                    color: color, stroke: true))
            }
            out.append(Solid3D(faces))
        }
    }

    /// Sutherland-Hodgman clip of a convex polygon to the half-plane dot(p, d) >= 0.
    private static func clip(_ poly: [SIMD2<Float>], keeping d: SIMD2<Float>) -> [SIMD2<Float>] {
        var out: [SIMD2<Float>] = []
        for i in poly.indices {
            let a = poly[i], b = poly[(i + 1) % poly.count]
            let da = simd_dot(a, d), db = simd_dot(b, d)
            if da >= 0 { out.append(a) }
            if (da >= 0) != (db >= 0) {
                out.append(a + (b - a) * (da / (da - db)))
            }
        }
        return out
    }
}
