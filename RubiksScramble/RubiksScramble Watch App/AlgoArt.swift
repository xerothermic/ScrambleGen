import SwiftUI

/// Canvas drawings for the Algorithms card: a last-layer top view. OLL and
/// edge-step cases are 3x3 rounded squares plus 12 side bars (yellow = that
/// sticker is yellow); PLL cases are a yellow top with arrows from each
/// misplaced piece's slot to its home slot (a 2-cycle is one double-headed
/// arrow). Same geometry as the design mock-ups (algo-card `mockups.py`).
enum AlgoArt {
    static let yellow = Color(red: 1.0, green: 0.84, blue: 0.0)
    static let off = Color(red: 0.24, green: 0.24, blue: 0.27)
    static let arrowInk = Color(red: 0.08, green: 0.08, blue: 0.1)

    /// Corner slots BL BR FR FL and edge slots B R F L as (column, row) on the
    /// 3x3 top grid; matches the order of `cp` / `ep` in AlgoCases.json.
    static let cornerSlots: [(Int, Int)] = [(0, 0), (2, 0), (2, 2), (0, 2)]
    static let edgeSlots: [(Int, Int)] = [(1, 0), (2, 1), (1, 2), (0, 1)]

    /// Draws one case in a square `size` x `size` box centred in `canvas`.
    static func draw(_ context: inout GraphicsContext, algoCase: AlgoCase,
                     variant: AlgoAuf?, canvas: CGSize) {
        let side = min(canvas.width, canvas.height)
        let origin = CGPoint(x: (canvas.width - side) / 2, y: (canvas.height - side) / 2)
        if algoCase.kind == "pll" {
            drawPLL(&context, origin: origin, side: side,
                    cp: variant?.cp ?? algoCase.cp ?? "0123",
                    ep: variant?.ep ?? algoCase.ep ?? "0123")
        } else {
            drawOLL(&context, origin: origin, side: side, bits: algoCase.pic ?? "")
        }
    }

    private static func roundedRect(_ context: inout GraphicsContext, _ rect: CGRect,
                                    radius: CGFloat, color: Color) {
        context.fill(Path(roundedRect: rect, cornerRadius: radius), with: .color(color))
    }

    /// bits: 9 top stickers (row-major, back row first), then back, right,
    /// front, left side stickers (3 each).
    static func drawOLL(_ context: inout GraphicsContext, origin: CGPoint,
                        side: CGFloat, bits: String) {
        let b = Array(bits.utf8)
        guard b.count >= 21 else { return }
        let on: (Int) -> Color = { b[$0] == UInt8(ascii: "1") ? yellow : off }
        let cell = side / (3 + 2 * 0.42 + 4 * 0.06)
        let gap = cell * 0.06
        let bar = cell * 0.30
        let span = 3 * cell + 2 * gap
        let x0 = origin.x + (side - span) / 2
        let y0 = origin.y + (side - span) / 2
        for i in 0..<9 {
            let r = i / 3, q = i % 3
            roundedRect(&context,
                        CGRect(x: x0 + CGFloat(q) * (cell + gap),
                               y: y0 + CGFloat(r) * (cell + gap), width: cell, height: cell),
                        radius: cell * 0.14, color: on(i))
        }
        for j in 0..<3 {
            let o = CGFloat(j) * (cell + gap)
            roundedRect(&context,
                        CGRect(x: x0 + o, y: y0 - gap * 1.5 - bar, width: cell, height: bar),
                        radius: bar * 0.3, color: on(9 + j))
            roundedRect(&context,
                        CGRect(x: x0 + span + gap * 1.5, y: y0 + o, width: bar, height: cell),
                        radius: bar * 0.3, color: on(12 + j))
            roundedRect(&context,
                        CGRect(x: x0 + o, y: y0 + span + gap * 1.5, width: cell, height: bar),
                        radius: bar * 0.3, color: on(15 + j))
            roundedRect(&context,
                        CGRect(x: x0 - gap * 1.5 - bar, y: y0 + o, width: bar, height: cell),
                        radius: bar * 0.3, color: on(18 + j))
        }
    }

    static func drawPLL(_ context: inout GraphicsContext, origin: CGPoint,
                        side: CGFloat, cp: String, ep: String) {
        let cell = side / 3.1
        let gap = cell * 0.06
        let span = 3 * cell + 2 * gap
        let x0 = origin.x + (side - span) / 2
        let y0 = origin.y + (side - span) / 2
        for i in 0..<9 {
            let r = i / 3, q = i % 3
            roundedRect(&context,
                        CGRect(x: x0 + CGFloat(q) * (cell + gap),
                               y: y0 + CGFloat(r) * (cell + gap), width: cell, height: cell),
                        radius: cell * 0.14, color: yellow)
        }
        func centre(_ slot: (Int, Int)) -> CGPoint {
            CGPoint(x: x0 + CGFloat(slot.0) * (cell + gap) + cell / 2,
                    y: y0 + CGFloat(slot.1) * (cell + gap) + cell / 2)
        }
        for (slots, code) in [(cornerSlots, cp), (edgeSlots, ep)] {
            let homes = code.compactMap { Int(String($0)) }
            guard homes.count == 4 else { continue }
            var done = Set<Int>()
            for (i, h) in homes.enumerated() where h != i && !done.contains(i) {
                let both = homes[h] == i
                if both { done.insert(h) }
                drawArrow(&context, from: centre(slots[i]), to: centre(slots[h]),
                          width: max(1, side * 0.03), head: side * 0.11, both: both)
            }
        }
    }

    static func drawArrow(_ context: inout GraphicsContext, from a: CGPoint, to b: CGPoint,
                          width: CGFloat, head: CGFloat, both: Bool) {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = (dx * dx + dy * dy).squareRoot()
        guard len > 0 else { return }
        let ux = dx / len, uy = dy / len
        let start = both ? CGPoint(x: a.x + ux * head * 0.4, y: a.y + uy * head * 0.4) : a
        let end = CGPoint(x: b.x - ux * head * 0.8, y: b.y - uy * head * 0.8)
        var line = Path()
        line.move(to: start)
        line.addLine(to: end)
        context.stroke(line, with: .color(arrowInk),
                       style: StrokeStyle(lineWidth: width, lineCap: .butt))
        func tip(_ p: CGPoint, _ vx: CGFloat, _ vy: CGFloat) {
            let nx = -vy, ny = vx
            var tri = Path()
            tri.move(to: p)
            tri.addLine(to: CGPoint(x: p.x - vx * head + nx * head * 0.55,
                                    y: p.y - vy * head + ny * head * 0.55))
            tri.addLine(to: CGPoint(x: p.x - vx * head - nx * head * 0.55,
                                    y: p.y - vy * head - ny * head * 0.55))
            tri.closeSubpath()
            context.fill(tri, with: .color(arrowInk))
        }
        tip(b, ux, uy)
        if both { tip(a, -ux, -uy) }
    }
}

/// A case picture at a fixed square size. `variant` selects which AUF's PLL
/// arrows to draw (OLL pictures are the same for every variant).
struct AlgoCaseView: View {
    let algoCase: AlgoCase
    var variant: AlgoAuf?
    let size: CGFloat

    var body: some View {
        Canvas { context, canvas in
            AlgoArt.draw(&context, algoCase: algoCase, variant: variant, canvas: canvas)
        }
        .frame(width: size, height: size)
    }
}
