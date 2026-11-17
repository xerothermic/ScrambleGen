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

    /// True when both layers alternate corner, edge, corner, edge, ... (four
    /// corners and four edges each): the starting "cube shape".
    var isCube: Bool {
        for base in [0, 12] {
            var starts: [Int] = []
            for i in 0..<12 where !joined[base + (i + 11) % 12] { starts.append(i) }
            var widths: [Int] = []
            for (k, start) in starts.enumerated() {
                let gap = (starts[(k + 1) % starts.count] - start + 12) % 12
                widths.append(gap == 0 ? 12 : gap)
            }
            if widths.filter({ $0 == 2 }).count != 4 { return false }
            for k in 0..<widths.count where widths[k] == widths[(k + 1) % widths.count] { return false }
        }
        return true
    }
}

/// Random-move Square-1 scrambles in WCA notation: `(x,y)/` turns the top
/// layer x and the bottom layer y steps of 30°, then slices.
///
/// The first `cubeShapeSlices` slices are chosen so the puzzle is back in cube
/// shape after each of them (uniform over the legal turns that do that);
/// from the next slice on, any legal turn is allowed.
enum Square1Scrambler {
    static let defaultSlices = 15
    static let cubeShapeSlices = 6

    /// One token per slice. A scramble may open with a bare `/`; anywhere
    /// else a (0,0) turn would just undo the previous slice.
    static func generate(slices: Int = defaultSlices) -> [String] {
        var shape = Square1Shape()
        var tokens: [String] = []
        tokens.reserveCapacity(max(0, slices))
        while tokens.count < max(0, slices) {
            var top: Int
            var bottom: Int
            if tokens.count < cubeShapeSlices {
                var options: [(Int, Int)] = []
                for t in -5...6 {
                    for b in -5...6 where t != 0 || b != 0 || tokens.isEmpty {
                        var trial = shape
                        if trial.turn(top: t, bottom: b) {
                            trial.slice()
                            if trial.isCube { options.append((t, b)) }
                        }
                    }
                }
                (top, bottom) = options.randomElement()!
            } else {
                top = Int.random(in: -5...6)
                bottom = Int.random(in: -5...6)
                guard top != 0 || bottom != 0, shape.turn(top: top, bottom: bottom) else { continue }
                shape.slice()
                tokens.append("(\(top),\(bottom))/")
                continue
            }
            let isTurn = top != 0 || bottom != 0
            _ = shape.turn(top: top, bottom: bottom)
            shape.slice()
            tokens.append(isTurn ? "(\(top),\(bottom))/" : "/")
        }
        return tokens
    }
}
