import Foundation

/// The shape of a Square-1, tracked only as far as scrambling needs: where the
/// corners sit, so we know whether the slice can cut.
///
/// Each layer has 12 cells of 30°: an edge fills one cell, a corner two.
/// `joined[i]` is true when cell `i` and the next cell belong to the same
/// corner. Cells 0–11 are the top layer and 12–23 the bottom; the slice cuts
/// each layer between cells 5|6 and 11|0, so a corner may never span either.
struct Square1Shape {
    private var joined: [Bool] = [
        true, false, false, true, false, false, true, false, false, true, false, false,
        false, true, false, false, true, false, false, true, false, false, true, false,
    ]

    /// Turns the top layer `top` steps and the bottom layer `bottom` steps of
    /// 30°. Returns false, leaving the shape untouched, if a corner would end
    /// up straddling the slice line.
    mutating func turn(top: Int, bottom: Int) -> Bool {
        let up = Array(joined[0..<12])
        let down = Array(joined[12..<24])
        func cell(_ layer: [Bool], _ i: Int, after steps: Int) -> Bool {
            layer[((i - steps) % 12 + 12) % 12]
        }
        if cell(up, 5, after: top) || cell(up, 11, after: top)
            || cell(down, 5, after: bottom) || cell(down, 11, after: bottom) {
            return false
        }
        for i in 0..<12 {
            joined[i] = cell(up, i, after: top)
            joined[12 + i] = cell(down, i, after: bottom)
        }
        return true
    }

    /// The `/` move: the right halves of the two layers trade places.
    mutating func slice() {
        for i in 0..<6 { joined.swapAt(6 + i, 12 + i) }
    }
}

/// Random-move Square-1 scrambles in WCA notation: `(x,y)/` turns the top
/// layer x and the bottom layer y steps of 30°, then slices.
enum Square1Scrambler {
    static let defaultSlices = 15

    /// One token per slice. A scramble may open with a bare `/`; anywhere
    /// else a (0,0) turn would just undo the previous slice.
    static func generate(slices: Int = defaultSlices) -> [String] {
        var shape = Square1Shape()
        var tokens: [String] = []
        tokens.reserveCapacity(max(0, slices))
        while tokens.count < max(0, slices) {
            let top = Int.random(in: -5...6)
            let bottom = Int.random(in: -5...6)
            let isTurn = top != 0 || bottom != 0
            guard isTurn || tokens.isEmpty, shape.turn(top: top, bottom: bottom) else { continue }
            shape.slice()
            tokens.append(isTurn ? "(\(top),\(bottom))/" : "/")
        }
        return tokens
    }
}
