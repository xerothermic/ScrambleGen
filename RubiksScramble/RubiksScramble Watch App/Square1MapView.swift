import SwiftUI

/// Piece-level Square-1 state in the cell model of the WCA's TNoodle
/// scrambler: cells 0–11 are the top layer and 12–23 the bottom, each holding
/// a piece id (0–7 start on top, 8–15 on the bottom; a corner fills two
/// cells). Square1Shape in the scrambler tracks the same cells, so any
/// scramble it emits replays here.
struct Square1State {
    private(set) var pieces = [0, 0, 1, 2, 2, 3, 4, 4, 5, 6, 6, 7,
                               8, 9, 9, 10, 11, 11, 12, 13, 13, 14, 15, 15]
    /// Whether the middle layer is in its solved orientation; every slice flips it.
    private(set) var sliceSolved = true

    /// Applies `(x,y)/` and bare `/` tokens, starting from solved.
    static func scrambled(by tokens: [String]) -> Square1State {
        var state = Square1State()
        for token in tokens {
            let turn = token
                .trimmingCharacters(in: CharacterSet(charactersIn: "()/ "))
                .split(separator: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            if turn.count == 2 { state.turn(top: turn[0], bottom: turn[1]) }
            if token.hasSuffix("/") { state.slice() }
        }
        return state
    }

    mutating func turn(top: Int, bottom: Int) {
        let up = Array(pieces[0..<12])
        let down = Array(pieces[12..<24])
        let topShift = ((-top % 12) + 12) % 12
        let bottomShift = ((-bottom % 12) + 12) % 12
        for i in 0..<12 {
            pieces[i] = up[(topShift + i) % 12]
            pieces[12 + i] = down[(bottomShift + i) % 12]
        }
    }

    mutating func slice() {
        for i in 0..<6 { pieces.swapAt(6 + i, 12 + i) }
        sliceSolved.toggle()
    }
}

/// The Square-1 after the scramble, drawn the way WCA scramble sheets draw
/// it (TNoodle's layout and colours): top face above, bottom face below, and
/// the middle layer between them — one bar when solved, split front/back
/// when flipped.
struct Square1MapView: View {
    let moves: [String]

    var body: some View {
        let state = Square1State.scrambled(by: moves)
        NavigationStack {
            Canvas { context, size in
                Square1Drawing.draw(state, in: &context, size: size)
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 6)
            .navigationTitle("Square-1")
        }
    }
}

private enum Square1Drawing {
    static let multiplier: CGFloat = 1.4
    static let radiusMultiplier: CGFloat = sqrt(2) * cos(15 * .pi / 180)

    /// Indexed Left, Back, Right, Front, Up, Down. The WCA scrambles Square-1
    /// with yellow on top and red in front, so this differs from the 3×3 net.
    static let scheme: [Color] = [
        Color(hex: 0x0051BA), Color(hex: 0xFF5800), Color(hex: 0x30D158),
        Color(hex: 0xCE2029), Color(hex: 0xFFD500), Color(hex: 0xFFFFFF),
    ]

    static func draw(_ state: Square1State, in context: inout GraphicsContext, size: CGSize) {
        let m = multiplier
        let r = min(size.width / (2 * radiusMultiplier * m),
                    size.height / (4 * radiusMultiplier * m))
        let width = 2 * radiusMultiplier * m * r
        let height = 4 * radiusMultiplier * m * r
        let origin = CGPoint(x: (size.width - width) / 2, y: (size.height - height) / 2)
        let lineWidth = max(1, r / 16)

        let halfSquare = r * radiusMultiplier * m / sqrt(2)
        let edgeWidth = 2 * r * m * sin(15 * .pi / 180)
        let cornerWidth = halfSquare - edgeWidth / 2
        let barX = origin.x + width / 2 - halfSquare
        let barY = origin.y + height / 2 - r * (m - 1) / 2
        let barHeight = r * (m - 1)
        let frontBar = CGRect(x: barX, y: barY, width: cornerWidth, height: barHeight)
        let restBar = CGRect(x: barX, y: barY,
                             width: state.sliceSolved ? 2 * cornerWidth + edgeWidth
                                                      : cornerWidth + edgeWidth,
                             height: barHeight)
        context.fill(Path(restBar), with: .color(state.sliceSolved ? scheme[3] : scheme[1]))
        context.fill(Path(frontBar), with: .color(scheme[3]))
        context.stroke(Path(restBar), with: .color(.black), lineWidth: lineWidth)
        context.stroke(Path(frontBar), with: .color(.black), lineWidth: lineWidth)

        let centerX = origin.x + width / 2
        drawFace(Array(state.pieces[0..<12]),
                 center: CGPoint(x: centerX, y: origin.y + height / 4),
                 startDegrees: 90 + 15, radius: r, lineWidth: lineWidth, in: &context)
        drawFace(Array(state.pieces[12..<24]),
                 center: CGPoint(x: centerX, y: origin.y + 3 * height / 4),
                 startDegrees: -90 - 15, radius: r, lineWidth: lineWidth, in: &context)
    }

    private static func drawFace(_ face: [Int], center: CGPoint, startDegrees: CGFloat,
                                 radius r: CGFloat, lineWidth: CGFloat,
                                 in context: inout GraphicsContext) {
        // Start on a piece boundary so a corner is never split at the seam.
        let first = (0..<12).first { face[$0] != face[($0 + 11) % 12] } ?? 0
        var degrees = startDegrees + CGFloat(first) * 30
        var cell = first
        while cell < first + 12 {
            let piece = face[cell % 12]
            let corner = isCorner(piece)
            let transform = CGAffineTransform(translationX: center.x, y: center.y)
                .rotated(by: degrees * .pi / 180)
            let shapes = corner ? cornerShapes(r) : edgeShapes(r)
            let fills = colors(of: piece)
            for k in fills.indices.reversed() {
                let path = shapes[k].applying(transform)
                context.fill(path, with: .color(fills[k]))
                context.stroke(path, with: .color(.black),
                               style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round))
            }
            let span = corner ? 2 : 1
            degrees += CGFloat(span) * 30
            cell += span
        }
    }

    private static func isCorner(_ piece: Int) -> Bool {
        (piece + (piece <= 7 ? 0 : 1)) % 2 == 0
    }

    /// Fills in the order of `cornerShapes` / `edgeShapes`: the piece's
    /// top-or-bottom sticker, then its side stickers.
    private static func colors(of piece: Int) -> [Color] {
        let up = piece <= 7
        let face = up ? scheme[4] : scheme[5]
        if isCorner(piece) {
            let p = up ? piece : 15 - piece
            var a = scheme[(p / 2 + 3) % 4]
            var b = scheme[p / 2]
            if !up { swap(&a, &b) }
            return [face, a, b]
        }
        let p = up ? piece : 14 - piece
        return [face, scheme[p / 2]]
    }

    private static func polygon(_ points: [CGPoint]) -> Path {
        var path = Path()
        path.addLines(points)
        path.closeSubpath()
        return path
    }

    private static func edgeShapes(_ r: CGFloat) -> [Path] {
        let m = multiplier
        let tip = CGPoint(x: sqrt(3) * r / 2, y: r / 2)
        return [
            polygon([.zero, CGPoint(x: r, y: 0), tip]),
            polygon([CGPoint(x: r, y: 0), CGPoint(x: m * r, y: 0),
                     CGPoint(x: m * tip.x, y: m * tip.y), tip]),
        ]
    }

    private static func cornerShapes(_ r: CGFloat) -> [Path] {
        let m = multiplier
        let angle: CGFloat = 75 * .pi / 180
        let outer = CGPoint(x: r * (1 + cos(angle) / sqrt(2)), y: r * sin(angle) / sqrt(2))
        let far = CGPoint(x: r / 2, y: sqrt(3) * r / 2)
        let outerRim = CGPoint(x: m * outer.x, y: m * outer.y)
        let farRim = CGPoint(x: m * far.x, y: m * far.y)
        return [
            polygon([.zero, CGPoint(x: r, y: 0), outer, far]),
            polygon([CGPoint(x: r, y: 0), CGPoint(x: m * r, y: 0), outerRim, outer]),
            polygon([outerRim, outer, far, farRim]),
        ]
    }
}

#Preview {
    Square1MapView(moves: Square1Scrambler.generate())
}
