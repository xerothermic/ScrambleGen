import AppIntents
import SwiftUI
import WidgetKit

// Watch-face complication: shows the chosen puzzle and, when tapped, opens
// the app on that puzzle (scramblegen://puzzle/<slug>, handled by
// ContentView.onOpenURL). Puzzle, its colours and the URL format are shared
// with the app via ScrambleGenerator.swift and PuzzleStyle.swift.

// MARK: - Intent

extension Puzzle: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Puzzle" }
    static var caseDisplayRepresentations: [Puzzle: DisplayRepresentation] {
        [.cube3x3: DisplayRepresentation(title: "3×3"),
         .square1: DisplayRepresentation(title: "Square-1")]
    }
}

struct SelectPuzzleIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Scramble" }
    static var description: IntentDescription {
        IntentDescription("Choose which puzzle the complication opens.")
    }

    @Parameter(title: "Puzzle", default: .cube3x3)
    var puzzle: Puzzle

    init() {}
    init(puzzle: Puzzle) { self.puzzle = puzzle }
}

// MARK: - Timeline

struct PuzzleEntry: TimelineEntry {
    let date: Date
    let puzzle: Puzzle
}

struct PuzzleProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> PuzzleEntry {
        PuzzleEntry(date: .now, puzzle: .cube3x3)
    }

    func snapshot(for configuration: SelectPuzzleIntent, in context: Context) async -> PuzzleEntry {
        PuzzleEntry(date: .now, puzzle: configuration.puzzle)
    }

    func timeline(for configuration: SelectPuzzleIntent, in context: Context) async -> Timeline<PuzzleEntry> {
        // Static content: one entry, never needs a refresh.
        Timeline(entries: [PuzzleEntry(date: .now, puzzle: configuration.puzzle)], policy: .never)
    }

    // watchOS lists these in the face editor's complication gallery.
    func recommendations() -> [AppIntentRecommendation<SelectPuzzleIntent>] {
        Puzzle.allCases.map {
            AppIntentRecommendation(intent: SelectPuzzleIntent(puzzle: $0),
                                    description: Text($0.name))
        }
    }
}

// MARK: - Art

/// Complication artwork drawn with Canvas paths: an isometric three-face cube
/// for 3x3, a top view of kite (corner) and edge pieces with coloured rims for
/// Square-1. Colours are the app's sticker colours (CubeFace.stickerColor);
/// when the system renders the widget tinted or vibrant, the pieces are drawn
/// as separated white cells at three opacities (line art) instead.
struct PuzzleArt: View {
    let puzzle: Puzzle
    let fullColor: Bool

    var body: some View {
        if fullColor {
            Canvas { context, size in
                PuzzleArt.drawColour(&context, puzzle: puzzle, size: size)
            }
        } else {
            // Tinted / vibrant rendering flattens colour, so the art is drawn as
            // line art: separated cells, three opacity levels, no black strokes.
            // Only layer 0 is accentable; layers 1 and 2 stay plain white so the
            // luminance differences between them survive the tint.
            ZStack {
                Canvas { context, size in
                    PuzzleArt.drawLine(&context, puzzle: puzzle, size: size, layer: 0)
                }
                .widgetAccentable()
                Canvas { context, size in
                    PuzzleArt.drawLine(&context, puzzle: puzzle, size: size, layer: 1)
                }
                Canvas { context, size in
                    PuzzleArt.drawLine(&context, puzzle: puzzle, size: size, layer: 2)
                }
            }
        }
    }

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

    private static let cubeTop: [CubeFace] =
        [.up, .back, .up, .front, .up, .right, .down, .up, .front]
    private static let cubeLeft: [CubeFace] =
        [.front, .left, .down, .back, .front, .right, .right, .down, .left]
    private static let cubeRight: [CubeFace] =
        [.right, .left, .up, .front, .right, .back, .left, .down, .right]

    /// One 3x3 sticker grid on a parallelogram spanned by u (columns) and v (rows).
    private static func drawGrid(_ context: inout GraphicsContext, origin: CGPoint,
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

    private struct Piece {
        let isCorner: Bool
        let rim: [CubeFace]
    }

    /// Solved top layer, clockwise: corner, edge, corner, edge, ...
    private static let square1Pieces: [Piece] = [
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

// MARK: - View

struct ScrambleComplicationView: View {
    let entry: PuzzleEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    private var puzzle: Puzzle { entry.puzzle }
    private var fullColor: Bool { renderingMode == .fullColor }

    private var title: String {
        switch puzzle {
        case .cube3x3: return "3×3 Cube"
        case .square1: return "Square-1"
        }
    }

    var body: some View {
        content
            .widgetURL(puzzle.deepLink)
            .containerBackground(for: .widget) { Color.clear }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                PuzzleArt(puzzle: puzzle, fullColor: fullColor)
                    .padding(4)
            }
        case .accessoryRectangular:
            HStack(spacing: 8) {
                PuzzleArt(puzzle: puzzle, fullColor: fullColor)
                    .frame(width: 54, height: 54)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Watch Scramble")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.headline)
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)
                    Text("Tap to scramble")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        case .accessoryCorner:
            // No fixed size: the art fills whatever the corner slot offers.
            PuzzleArt(puzzle: puzzle, fullColor: fullColor)
                .aspectRatio(1, contentMode: .fit)
                .padding(1)
                .widgetLabel { Text(puzzle.name) }
        case .accessoryInline:
            // Inline complications can only show text and SF Symbols.
            Label(puzzle.name, systemImage: puzzle.symbolName)
        default:
            Text(puzzle.shortName)
        }
    }
}

// MARK: - Widget

@main
struct ScrambleComplication: Widget {
    static let kind = "ScrambleComplication"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind,
                               intent: SelectPuzzleIntent.self,
                               provider: PuzzleProvider()) { entry in
            ScrambleComplicationView(entry: entry)
        }
        .configurationDisplayName("Scramble")
        .description("Open Watch Scramble on a puzzle of your choice.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular,
                            .accessoryCorner, .accessoryInline])
    }
}
