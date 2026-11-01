import SwiftUI

// Puzzle artwork (approved "A" mock-ups), shared by the watch app (card previews)
// and the widget extension (complications). Drawn with Canvas paths: an
// isometric three-face cube for 3x3, a top view of kite (corner) and edge
// pieces with coloured rims for Square-1.
enum PuzzleArtDrawing {
    static func drawColour(_ context: inout GraphicsContext, puzzle: Puzzle, size: CGSize) {
        let side = min(size.width, size.height)
        let lineWidth = max(0.6, side * 0.012)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        switch puzzle {
        case .cube3x3:
            drawCube(&context, center: center, edge: side * 0.48,
                     lineWidth: lineWidth, fullColor: true)
        case .square1:
            drawSquare1(&context, center: center, radius: side * 0.29,
                        lineWidth: lineWidth, fullColor: true)
        }
    }

    // MARK: Colours

    static func tone(_ face: CubeFace, fullColor: Bool) -> Color {
        if fullColor { return face.stickerColor }
        switch face {
        case .up: return Color(hex: 0xFFFFFF)
        case .down: return Color(hex: 0xDADADA)
        case .left: return Color(hex: 0xA6A6A6)
        case .front: return Color(hex: 0x7E7E7E)
        case .right: return Color(hex: 0x585858)
        case .back: return Color(hex: 0x3A3A3A)
        }
    }

    // MARK: Helpers

    static func polygon(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }

    static func paint(_ context: inout GraphicsContext, _ points: [CGPoint],
                      color: Color, lineWidth: CGFloat) {
        let path = polygon(points)
        context.fill(path, with: .color(color))
        context.stroke(path, with: .color(.black),
                       style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round))
    }

    // MARK: Timer (speed cube timer)

    /// Generic Stackmat/Speed-Stacks-style timer: dark bow-tie body, raised
    /// centre panel with an LCD, a round yellow hand pad on each wing. Drawn in
    /// a 1 x 0.5 box (unit coordinates, y 0.2...0.7) fitted to the canvas width.
    private struct TimerGeo {
        let ox: CGFloat, oy: CGFloat, w: CGFloat
        init(_ size: CGSize) {
            w = min(size.width, size.height * 2.1) * 0.98
            ox = (size.width - w) / 2
            oy = size.height / 2 - 0.45 * w
        }
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * w, y: oy + y * w) }
        func rect(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> CGRect {
            CGRect(x: ox + x0 * w, y: oy + y0 * w, width: (x1 - x0) * w, height: (y1 - y0) * w)
        }
        func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: ox + (x - r) * w, y: oy + (y - r) * w,
                                   width: 2 * r * w, height: 2 * r * w))
        }
        var body: [CGPoint] {
            [p(0.02, 0.30), p(0.36, 0.22), p(0.64, 0.22), p(0.98, 0.30), p(0.98, 0.56),
             p(0.90, 0.68), p(0.50, 0.58), p(0.10, 0.68), p(0.02, 0.56)]
        }
        var panel: CGRect { rect(0.34, 0.20, 0.66, 0.54) }
        var lcd: CGRect { rect(0.38, 0.25, 0.62, 0.40) }
        var padR: CGFloat { 0.10 }
        var pads: [CGPoint] { [CGPoint(x: 0.17, y: 0.43), CGPoint(x: 0.83, y: 0.43)] }
    }

    /// Seven-segment "0.00" inside the LCD rect as bars (large enough to read
    /// as digits even at complication size).
    private static func lcdDigits(_ g: TimerGeo) -> [CGRect] {
        let r = g.lcd
        let digitW = r.width * 0.2, gap = r.width * 0.07
        let h = r.height * 0.7, t = max(0.8, r.height * 0.14)
        let total = digitW * 3 + gap * 2 + r.width * 0.08
        var x = r.minX + (r.width - total) / 2
        let y = r.minY + (r.height - h) / 2
        var out: [CGRect] = []
        for i in 0..<3 {
            // Digit "0": top, bottom, left, right.
            out.append(CGRect(x: x, y: y, width: digitW, height: t))
            out.append(CGRect(x: x, y: y + h - t, width: digitW, height: t))
            out.append(CGRect(x: x, y: y, width: t, height: h))
            out.append(CGRect(x: x + digitW - t, y: y, width: t, height: h))
            x += digitW + gap
            if i == 0 {
                out.append(CGRect(x: x - gap / 2 - t / 2 + r.width * 0.04, y: y + h - t, width: t, height: t))
                x += r.width * 0.08
            }
        }
        return out
    }

    /// Full colour: dark body, silver panel, green-grey LCD with dark digits,
    /// yellow hand pads.
    static func drawTimerColour(_ context: inout GraphicsContext, size: CGSize) {
        let g = TimerGeo(size)
        let lineWidth = max(0.6, g.w * 0.012)
        paint(&context, g.body, color: Color(hex: 0x2A2A2F), lineWidth: lineWidth)
        context.fill(Path(roundedRect: g.panel, cornerRadius: g.w * 0.04), with: .color(Color(hex: 0xB9BDC4)))
        context.fill(Path(roundedRect: g.lcd, cornerRadius: g.w * 0.015), with: .color(Color(hex: 0xA8B58C)))
        for d in lcdDigits(g) { context.fill(Path(d), with: .color(Color(hex: 0x1B1F14))) }
        for c in g.pads {
            let pad = g.circle(c.x, c.y, g.padR)
            context.fill(pad, with: .color(Color(hex: 0xF4C20D)))
            context.stroke(pad, with: .color(.black), style: StrokeStyle(lineWidth: lineWidth * 0.8))
        }
        let power = g.circle(0.56, 0.47, 0.025)
        context.fill(power, with: .color(Color(hex: 0xCE2029)))
    }

    /// Line art. Layer 0 = body outline and LCD digits (opacity 1.0),
    /// 1 = hand pads (0.6), 2 = centre panel and LCD window (0.32).
    static func drawTimerLine(_ context: inout GraphicsContext, size: CGSize, layer: Int) {
        let g = TimerGeo(size)
        switch layer {
        case 0:
            context.stroke(polygon(g.body), with: .color(.white),
                           style: StrokeStyle(lineWidth: max(1, g.w * 0.035), lineJoin: .round))
            for d in lcdDigits(g) { context.fill(Path(d), with: .color(.white)) }
        case 1:
            for c in g.pads {
                context.fill(g.circle(c.x, c.y, g.padR), with: .color(Color.white.opacity(0.6)))
            }
        default:
            context.fill(Path(roundedRect: g.panel, cornerRadius: g.w * 0.04),
                         with: .color(Color.white.opacity(0.32)))
        }
    }


    // MARK: 3x3

    static let cubeTop: [CubeFace] =
        [.up, .back, .up, .front, .up, .right, .down, .up, .front]
    static let cubeLeft: [CubeFace] =
        [.front, .left, .down, .back, .front, .right, .right, .down, .left]
    static let cubeRight: [CubeFace] =
        [.right, .left, .up, .front, .right, .back, .left, .down, .right]

    /// One 3x3 sticker grid on a parallelogram spanned by u (columns) and v (rows).
    static func drawGrid(_ context: inout GraphicsContext, origin: CGPoint,
                                 u: CGPoint, v: CGPoint, faces: [CubeFace],
                                 lineWidth: CGFloat, fullColor: Bool) {
        for row in 0..<3 {
            for col in 0..<3 {
                let c0 = CGFloat(col) / 3
                let c1 = CGFloat(col + 1) / 3
                let r0 = CGFloat(row) / 3
                let r1 = CGFloat(row + 1) / 3
                let corners = [
                    CGPoint(x: origin.x + u.x * c0 + v.x * r0, y: origin.y + u.y * c0 + v.y * r0),
                    CGPoint(x: origin.x + u.x * c1 + v.x * r0, y: origin.y + u.y * c1 + v.y * r0),
                    CGPoint(x: origin.x + u.x * c1 + v.x * r1, y: origin.y + u.y * c1 + v.y * r1),
                    CGPoint(x: origin.x + u.x * c0 + v.x * r1, y: origin.y + u.y * c0 + v.y * r1),
                ]
                paint(&context, corners,
                      color: tone(faces[row * 3 + col], fullColor: fullColor),
                      lineWidth: lineWidth)
            }
        }
    }

    /// Isometric cube: `edge` is the distance from the centre to each hexagon corner.
    static func drawCube(_ context: inout GraphicsContext, center: CGPoint,
                         edge: CGFloat, lineWidth: CGFloat, fullColor: Bool) {
        let k = edge * 0.8660254
        let h = edge * 0.5
        let down = CGPoint(x: 0, y: edge)
        drawGrid(&context, origin: CGPoint(x: center.x, y: center.y - edge),
                 u: CGPoint(x: k, y: h), v: CGPoint(x: -k, y: h),
                 faces: cubeTop, lineWidth: lineWidth, fullColor: fullColor)
        drawGrid(&context, origin: CGPoint(x: center.x - k, y: center.y - h),
                 u: CGPoint(x: k, y: h), v: down,
                 faces: cubeLeft, lineWidth: lineWidth, fullColor: fullColor)
        drawGrid(&context, origin: center,
                 u: CGPoint(x: k, y: -h), v: down,
                 faces: cubeRight, lineWidth: lineWidth, fullColor: fullColor)
    }

    // MARK: Square-1

    struct Piece {
        let isCorner: Bool
        let rim: [CubeFace]
    }

    /// Solved top layer, clockwise: corner, edge, corner, edge, ...
    static let square1Pieces: [Piece] = [
        Piece(isCorner: true, rim: [.right, .back]),
        Piece(isCorner: false, rim: [.back]),
        Piece(isCorner: true, rim: [.back, .left]),
        Piece(isCorner: false, rim: [.left]),
        Piece(isCorner: true, rim: [.left, .front]),
        Piece(isCorner: false, rim: [.front]),
        Piece(isCorner: true, rim: [.front, .right]),
        Piece(isCorner: false, rim: [.right]),
    ]

    /// Top view: yellow top face with a coloured rim of side stickers.
    /// `radius` is half of the square's side.
    static func drawSquare1(_ context: inout GraphicsContext, center: CGPoint,
                            radius: CGFloat, lineWidth: CGFloat, fullColor: Bool) {
        let edgeRadius = radius / CGFloat(cos(15.0 * Double.pi / 180))
        let tipRadius = radius * CGFloat(2.0.squareRoot())
        let rimDepth = radius * 0.26
        let top = tone(.down, fullColor: fullColor)

        func point(_ degrees: Double, _ r: CGFloat) -> CGPoint {
            let a = degrees * Double.pi / 180
            return CGPoint(x: center.x + r * CGFloat(cos(a)),
                           y: center.y + r * CGFloat(sin(a)))
        }

        var angle = 15.0
        for piece in square1Pieces {
            let span = piece.isCorner ? 60.0 : 30.0
            let p0 = point(angle, edgeRadius)
            let p1 = point(angle + span, edgeRadius)
            if piece.isCorner {
                let tip = point(angle + span / 2, tipRadius)
                paint(&context, [center, p0, tip, p1], color: top, lineWidth: lineWidth)
                let q0 = point(angle, edgeRadius + rimDepth * 0.8)
                let q1 = point(angle + span, edgeRadius + rimDepth * 0.8)
                let qTip = point(angle + span / 2, tipRadius + rimDepth)
                paint(&context, [p0, tip, qTip, q0],
                      color: tone(piece.rim[0], fullColor: fullColor), lineWidth: lineWidth * 0.8)
                paint(&context, [tip, p1, q1, qTip],
                      color: tone(piece.rim[1], fullColor: fullColor), lineWidth: lineWidth * 0.8)
            } else {
                let q0 = point(angle, edgeRadius + rimDepth)
                let q1 = point(angle + span, edgeRadius + rimDepth)
                paint(&context, [center, p0, p1], color: top, lineWidth: lineWidth)
                paint(&context, [p0, p1, q1, q0],
                      color: tone(piece.rim[0], fullColor: fullColor), lineWidth: lineWidth * 0.8)
            }
            angle += span
        }
    }

    // MARK: Line art (tinted / vibrant)

    /// Shrinks a polygon towards its centroid, leaving a gap between neighbours.
    static func inset(_ points: [CGPoint], _ factor: CGFloat) -> [CGPoint] {
        var sumX: CGFloat = 0
        var sumY: CGFloat = 0
        for point in points {
            sumX += point.x
            sumY += point.y
        }
        let cx = sumX / CGFloat(points.count)
        let cy = sumY / CGFloat(points.count)
        return points.map {
            CGPoint(x: cx + ($0.x - cx) * factor, y: cy + ($0.y - cy) * factor)
        }
    }

    static func fillLine(_ context: inout GraphicsContext, _ points: [CGPoint],
                         opacity: Double, factor: CGFloat) {
        context.fill(polygon(inset(points, factor)),
                     with: .color(Color.white.opacity(opacity)))
    }

    static func drawLine(_ context: inout GraphicsContext, puzzle: Puzzle,
                         size: CGSize, layer: Int) {
        let side = min(size.width, size.height)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        switch puzzle {
        case .cube3x3:
            drawCubeLine(&context, center: center, edge: side * 0.48, layer: layer)
        case .square1:
            drawSquare1Line(&context, center: center, radius: side * 0.26, layer: layer)
        }
    }

    /// Layer 0 = top face (opacity 1.0), 1 = left face (0.6), 2 = right face (0.32).
    static func drawCubeLine(_ context: inout GraphicsContext, center: CGPoint,
                             edge: CGFloat, layer: Int) {
        let k = edge * 0.8660254
        let h = edge * 0.5
        let down = CGPoint(x: 0, y: edge)
        let origin: CGPoint
        let u: CGPoint
        let v: CGPoint
        let opacity: Double
        switch layer {
        case 0:
            origin = CGPoint(x: center.x, y: center.y - edge)
            u = CGPoint(x: k, y: h)
            v = CGPoint(x: -k, y: h)
            opacity = 1.0
        case 1:
            origin = CGPoint(x: center.x - k, y: center.y - h)
            u = CGPoint(x: k, y: h)
            v = down
            opacity = 0.6
        default:
            origin = center
            u = CGPoint(x: k, y: -h)
            v = down
            opacity = 0.32
        }
        for row in 0..<3 {
            for col in 0..<3 {
                let c0 = CGFloat(col) / 3
                let c1 = CGFloat(col + 1) / 3
                let r0 = CGFloat(row) / 3
                let r1 = CGFloat(row + 1) / 3
                let corners = [
                    CGPoint(x: origin.x + u.x * c0 + v.x * r0, y: origin.y + u.y * c0 + v.y * r0),
                    CGPoint(x: origin.x + u.x * c1 + v.x * r0, y: origin.y + u.y * c1 + v.y * r0),
                    CGPoint(x: origin.x + u.x * c1 + v.x * r1, y: origin.y + u.y * c1 + v.y * r1),
                    CGPoint(x: origin.x + u.x * c0 + v.x * r1, y: origin.y + u.y * c0 + v.y * r1),
                ]
                fillLine(&context, corners, opacity: opacity, factor: 0.78)
            }
        }
    }

    /// Layer 0 = top-face wedges (opacity 1.0), 1 = rim stickers (0.55 and 0.36).
    /// Layer 2 is unused.
    static func drawSquare1Line(_ context: inout GraphicsContext, center: CGPoint,
                                radius: CGFloat, layer: Int) {
        if layer > 1 { return }
        let edgeRadius = radius / CGFloat(cos(15.0 * Double.pi / 180))
        let tipRadius = radius * CGFloat(2.0.squareRoot())
        let rimDepth = radius * 0.40
        let gap = radius * 0.07

        func point(_ degrees: Double, _ r: CGFloat) -> CGPoint {
            let a = degrees * Double.pi / 180
            return CGPoint(x: center.x + r * CGFloat(cos(a)),
                           y: center.y + r * CGFloat(sin(a)))
        }

        var angle = 15.0
        for piece in square1Pieces {
            let span = piece.isCorner ? 60.0 : 30.0
            let p0 = point(angle, edgeRadius)
            let p1 = point(angle + span, edgeRadius)
            let mid = angle + span / 2
            if piece.isCorner {
                if layer == 0 {
                    fillLine(&context, [center, p0, point(mid, tipRadius), p1],
                             opacity: 1.0, factor: 0.88)
                } else {
                    let g0 = point(angle, edgeRadius + gap)
                    let g1 = point(angle + span, edgeRadius + gap)
                    let gTip = point(mid, tipRadius + gap)
                    let q0 = point(angle, edgeRadius + gap + rimDepth * 0.8)
                    let q1 = point(angle + span, edgeRadius + gap + rimDepth * 0.8)
                    let qTip = point(mid, tipRadius + gap + rimDepth)
                    fillLine(&context, [g0, gTip, qTip, q0], opacity: 0.55, factor: 0.88)
                    fillLine(&context, [gTip, g1, q1, qTip], opacity: 0.36, factor: 0.88)
                }
            } else {
                if layer == 0 {
                    fillLine(&context, [center, p0, p1], opacity: 1.0, factor: 0.88)
                } else {
                    let g0 = point(angle, edgeRadius + gap)
                    let g1 = point(angle + span, edgeRadius + gap)
                    let q0 = point(angle, edgeRadius + gap + rimDepth)
                    let q1 = point(angle + span, edgeRadius + gap + rimDepth)
                    fillLine(&context, [g0, g1, q1, q0], opacity: 0.55, factor: 0.88)
                }
            }
            angle += span
        }
    }
}
