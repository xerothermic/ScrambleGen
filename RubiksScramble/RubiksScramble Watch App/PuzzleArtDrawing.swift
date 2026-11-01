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
