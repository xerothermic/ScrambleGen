import Foundation

// Random-state 3x3 scrambles (WCA / TNoodle style): pick a uniformly random
// valid cube state, solve it with Kociemba's two-phase algorithm, and use the
// inverse of the solution as the scramble.
//
// Clean-room implementation written from the published description of the
// two-phase algorithm. It contains no TNoodle or min2phase code (both GPL).
// scripts/verify_333_scramble.py is the reference this file mirrors; keep the
// two in step and re-run it after any change here.
//
// Foundation only, so it can be unit-tested off-device (Tests/Scramble333).

/// Cubie-level cube: corner/edge permutation and orientation.
/// Corners URF UFL ULB UBR DFR DLF DBL DRB, edges UR UF UL UB DR DF DL DB FR FL BL BR.
/// `cp[i]` is the piece sitting in slot i; orientation 0 = U/D (or, for the
/// middle-layer edges, F/B) sticker on the slot's U/D (F/B) side.
struct Cubie: Equatable {
    var cp: [Int]
    var co: [Int]
    var ep: [Int]
    var eo: [Int]

    static let solved = Cubie(cp: Array(0..<8), co: [Int](repeating: 0, count: 8),
                              ep: Array(0..<12), eo: [Int](repeating: 0, count: 12))

    /// `self` followed by the move `m`.
    func applying(_ m: Cubie) -> Cubie {
        var r = self
        for i in 0..<8 {
            r.cp[i] = cp[m.cp[i]]
            r.co[i] = (co[m.cp[i]] + m.co[i]) % 3
        }
        for i in 0..<12 {
            r.ep[i] = ep[m.ep[i]]
            r.eo[i] = (eo[m.ep[i]] + m.eo[i]) % 2
        }
        return r
    }

    /// A reachable cube: valid permutations, orientation sums, matching parity.
    var isSolvable: Bool {
        cp.sorted() == Array(0..<8) && ep.sorted() == Array(0..<12)
            && co.reduce(0, +) % 3 == 0 && eo.reduce(0, +) % 2 == 0
            && RandomState333.parity(cp) == RandomState333.parity(ep)
    }
}

enum RandomState333 {
    // MARK: Moves

    private static let cornerNames = ["URF", "UFL", "ULB", "UBR", "DFR", "DLF", "DBL", "DRB"]
    private static let edgeNames = ["UR", "UF", "UL", "UB", "DR", "DF", "DL", "DB", "FR", "FL", "BL", "BR"]

    private static func makeMove(_ cp: String, _ co: [Int], _ ep: String, _ eo: [Int]) -> Cubie {
        Cubie(cp: cp.split(separator: " ").map { cornerNames.firstIndex(of: String($0))! },
              co: co,
              ep: ep.split(separator: " ").map { edgeNames.firstIndex(of: String($0))! },
              eo: eo)
    }

    /// Faces in move-index order; move index = 3 * face + k, k = 0 (x), 1 (x2), 2 (x').
    static let faces: [Character] = ["U", "R", "F", "D", "L", "B"]
    private static let suffixes = ["", "2", "'"]

    private static let z8 = [Int](repeating: 0, count: 8)
    private static let z12 = [Int](repeating: 0, count: 12)

    /// Clockwise quarter turn of each face.
    private static let quarterTurns: [Cubie] = [
        makeMove("UBR URF UFL ULB DFR DLF DBL DRB", z8, "UB UR UF UL DR DF DL DB FR FL BL BR", z12),
        makeMove("DFR UFL ULB URF DRB DLF DBL UBR", [2, 0, 0, 1, 1, 0, 0, 2],
                 "FR UF UL UB BR DF DL DB DR FL BL UR", z12),
        makeMove("UFL DLF ULB UBR URF DFR DBL DRB", [1, 2, 0, 0, 2, 1, 0, 0],
                 "UR FL UL UB DR FR DL DB UF DF BL BR", [0, 1, 0, 0, 0, 1, 0, 0, 1, 1, 0, 0]),
        makeMove("URF UFL ULB UBR DLF DBL DRB DFR", z8, "UR UF UL UB DF DL DB DR FR FL BL BR", z12),
        makeMove("URF ULB DBL UBR DFR UFL DLF DRB", [0, 1, 2, 0, 0, 2, 1, 0],
                 "UR UF BL UB DR DF FL DB FR UL DL BR", z12),
        makeMove("URF UFL UBR DRB DFR DLF ULB DBL", [0, 0, 1, 2, 0, 0, 2, 1],
                 "UR UF UL BR DR DF DL BL FR FL UB DB", [0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 1, 1]),
    ]

    /// All 18 moves as cubie transformations.
    static let moves: [Cubie] = {
        var out: [Cubie] = []
        for q in quarterTurns {
            let q2 = q.applying(q)
            out.append(q)
            out.append(q2)
            out.append(q2.applying(q))
        }
        return out
    }()

    static let moveNames: [String] = faces.flatMap { f in suffixes.map { String(f) + $0 } }

    /// Moves allowed in phase 2: U and D any turn, R L F B half turns only.
    static let phase2Moves: [Int] = (0..<18).filter { $0 / 3 == 0 || $0 / 3 == 3 || $0 % 3 == 1 }

    static func inverseMove(_ m: Int) -> Int { 3 * (m / 3) + (2 - m % 3) }

    // MARK: Coordinates

    static let nTwist = 2187, nFlip = 2048, nSlice = 495, nPerm8 = 40320, nSlicePerm = 24
    static let sliceSolved = 494

    static func permRank(_ p: ArraySlice<Int>) -> Int {
        let a = Array(p)
        let n = a.count
        var r = 0
        for i in 0..<n {
            var c = 0
            for j in (i + 1)..<max(n, i + 1) where a[j] < a[i] { c += 1 }
            r = r * (n - i) + c
        }
        return r
    }

    static func permRank(_ p: [Int]) -> Int { permRank(p[...]) }

    static func permUnrank(_ rank: Int, _ n: Int) -> [Int] {
        var digits = [Int](repeating: 0, count: n)
        var r = rank
        for i in stride(from: n - 1, through: 0, by: -1) {
            let base = n - i
            digits[i] = r % base
            r /= base
        }
        var avail = Array(0..<n)
        return digits.map { avail.remove(at: $0) }
    }

    static func parity(_ p: [Int]) -> Int {
        var inv = 0
        for i in 0..<p.count {
            for j in (i + 1)..<max(p.count, i + 1) where p[i] > p[j] { inv += 1 }
        }
        return inv % 2
    }

    /// binom[n][k], n 0...12, k 0...4
    private static let binom: [[Int]] = {
        var c = [[Int]](repeating: [Int](repeating: 0, count: 5), count: 13)
        for n in 0..<13 {
            c[n][0] = 1
            if n > 0 { for k in 1..<5 { c[n][k] = c[n - 1][k - 1] + c[n - 1][k] } }
        }
        return c
    }()

    /// Which 4 of the 12 edge slots hold the UD-slice edges (FR FL BL BR): 0..<495, solved = 494.
    static func sliceRank(_ ep: [Int]) -> Int {
        var r = 0, k = 0
        for i in 0..<12 where ep[i] >= 8 {
            r += binom[i][k + 1]
            k += 1
        }
        return r
    }

    private static func sliceUnrank(_ rank: Int) -> [Int] {
        var r = rank
        var pos: [Int] = []
        for k in [4, 3, 2, 1] {
            var p = 11
            while binom[p][k] > r { p -= 1 }
            r -= binom[p][k]
            pos.append(p)
        }
        return pos.sorted()
    }

    static func twist(_ co: [Int]) -> Int {
        var t = 0
        for i in 0..<7 { t = t * 3 + co[i] }
        return t
    }

    static func flip(_ eo: [Int]) -> Int {
        var t = 0
        for i in 0..<11 { t = t * 2 + eo[i] }
        return t
    }

    private static func cubeFromTwist(_ twist: Int) -> Cubie {
        var c = Cubie.solved
        var t = twist, s = 0
        for i in stride(from: 6, through: 0, by: -1) {
            c.co[i] = t % 3
            t /= 3
            s += c.co[i]
        }
        c.co[7] = (3 - s % 3) % 3
        return c
    }

    private static func cubeFromFlip(_ flip: Int) -> Cubie {
        var c = Cubie.solved
        var t = flip, s = 0
        for i in stride(from: 10, through: 0, by: -1) {
            c.eo[i] = t % 2
            t /= 2
            s += c.eo[i]
        }
        c.eo[11] = s % 2
        return c
    }

    private static func cubeFromSlice(_ rank: Int) -> Cubie {
        let pos = sliceUnrank(rank)
        var c = Cubie.solved
        var nextSlice = 8, nextOther = 0
        for i in 0..<12 {
            if pos.contains(i) {
                c.ep[i] = nextSlice
                nextSlice += 1
            } else {
                c.ep[i] = nextOther
                nextOther += 1
            }
        }
        return c
    }

    // MARK: Tables

    /// Move tables (coordinate x move -> coordinate) and pruning tables
    /// (exact distance to the phase goal of a coordinate pair). About 6 MB.
    final class Tables {
        // Phase 1 move tables, 18 columns.
        let twistMove: [UInt16]
        let flipMove: [UInt16]
        let sliceMove: [UInt16]
        // Phase 2 move tables, columns follow `phase2Moves`.
        let cpMove: [UInt16]
        let epMove: [UInt16]
        let spMove: [UInt16]
        // Pruning tables, index = first * secondCount + second.
        let pruneTwistSlice: [UInt8]
        let pruneFlipSlice: [UInt8]
        let pruneCpSp: [UInt8]
        let pruneEpSp: [UInt8]

        init() {
            let mv = RandomState333.moves
            let p2 = RandomState333.phase2Moves
            let n2 = p2.count

            var tw = [UInt16](repeating: 0, count: RandomState333.nTwist * 18)
            for t in 0..<RandomState333.nTwist {
                let c = RandomState333.cubeFromTwist(t)
                for m in 0..<18 { tw[t * 18 + m] = UInt16(RandomState333.twist(c.applying(mv[m]).co)) }
            }
            var fl = [UInt16](repeating: 0, count: RandomState333.nFlip * 18)
            for t in 0..<RandomState333.nFlip {
                let c = RandomState333.cubeFromFlip(t)
                for m in 0..<18 { fl[t * 18 + m] = UInt16(RandomState333.flip(c.applying(mv[m]).eo)) }
            }
            var sl = [UInt16](repeating: 0, count: RandomState333.nSlice * 18)
            for t in 0..<RandomState333.nSlice {
                let c = RandomState333.cubeFromSlice(t)
                for m in 0..<18 { sl[t * 18 + m] = UInt16(RandomState333.sliceRank(c.applying(mv[m]).ep)) }
            }
            var cpT = [UInt16](repeating: 0, count: RandomState333.nPerm8 * n2)
            var epT = [UInt16](repeating: 0, count: RandomState333.nPerm8 * n2)
            for r in 0..<RandomState333.nPerm8 {
                let p = RandomState333.permUnrank(r, 8)
                let pe = p + [8, 9, 10, 11]
                for (j, m) in p2.enumerated() {
                    let mc = mv[m].cp, me = mv[m].ep
                    cpT[r * n2 + j] = UInt16(RandomState333.permRank((0..<8).map { p[mc[$0]] }))
                    epT[r * n2 + j] = UInt16(RandomState333.permRank((0..<8).map { pe[me[$0]] }))
                }
            }
            var spT = [UInt16](repeating: 0, count: RandomState333.nSlicePerm * n2)
            for r in 0..<RandomState333.nSlicePerm {
                let p = RandomState333.permUnrank(r, 4)
                let pe = p.map { 8 + $0 }
                for (j, m) in p2.enumerated() {
                    let me = mv[m].ep
                    spT[r * n2 + j] = UInt16(RandomState333.permRank((0..<4).map { pe[me[8 + $0] - 8] - 8 }))
                }
            }
            twistMove = tw; flipMove = fl; sliceMove = sl
            cpMove = cpT; epMove = epT; spMove = spT

            pruneTwistSlice = Tables.prune(na: RandomState333.nTwist, nb: RandomState333.nSlice, nm: 18,
                                           ma: tw, mb: sl, goal: RandomState333.sliceSolved)
            pruneFlipSlice = Tables.prune(na: RandomState333.nFlip, nb: RandomState333.nSlice, nm: 18,
                                          ma: fl, mb: sl, goal: RandomState333.sliceSolved)
            pruneCpSp = Tables.prune(na: RandomState333.nPerm8, nb: RandomState333.nSlicePerm, nm: n2,
                                     ma: cpT, mb: spT, goal: 0)
            pruneEpSp = Tables.prune(na: RandomState333.nPerm8, nb: RandomState333.nSlicePerm, nm: n2,
                                     ma: epT, mb: spT, goal: 0)
        }

        /// Breadth-first distances from the goal over the product of two
        /// coordinates (every move is invertible within the move set, so
        /// forward expansion from the goal gives the exact distance).
        static func prune(na: Int, nb: Int, nm: Int, ma: [UInt16], mb: [UInt16], goal: Int) -> [UInt8] {
            var table = [UInt8](repeating: 255, count: na * nb)
            table[goal] = 0
            var depth: UInt8 = 0
            var added = 1
            table.withUnsafeMutableBufferPointer { t in
                ma.withUnsafeBufferPointer { a in
                    mb.withUnsafeBufferPointer { b in
                        while added > 0 {
                            added = 0
                            for idx in 0..<t.count where t[idx] == depth {
                                let ia = idx / nb, ib = idx % nb
                                for m in 0..<nm {
                                    let n = Int(a[ia * nm + m]) * nb + Int(b[ib * nm + m])
                                    if t[n] == 255 {
                                        t[n] = depth + 1
                                        added += 1
                                    }
                                }
                            }
                            depth += 1
                        }
                    }
                }
            }
            return table
        }
    }

    private final class Store: @unchecked Sendable {
        let lock = NSLock()
        let buildLock = NSLock()
        var tables: Tables?
    }

    private static let store = Store()

    /// True once the tables are built (generation then takes tens of ms).
    static var isReady: Bool {
        store.lock.lock()
        defer { store.lock.unlock() }
        return store.tables != nil
    }

    /// Builds the tables if needed (blocking; call off the main thread).
    /// Safe to call concurrently and repeatedly.
    @discardableResult
    static func prepare() -> Tables {
        store.buildLock.lock()
        defer { store.buildLock.unlock() }
        store.lock.lock()
        let existing = store.tables
        store.lock.unlock()
        if let existing { return existing }
        let t = Tables()
        store.lock.lock()
        store.tables = t
        store.lock.unlock()
        return t
    }

    // MARK: Solver

    /// Two-phase IDA* search. Phase 1 brings the cube into the subgroup
    /// <U, D, R2, L2, F2, B2> (twist = flip = 0, slice edges in the slice),
    /// phase 2 solves it inside that subgroup.
    private final class Search {
        let t: Tables
        let cube: Cubie
        var maxTotal: Int
        var best: [Int]?
        var path: [Int] = []

        init(tables: Tables, cube: Cubie, maxTotal: Int) {
            t = tables
            self.cube = cube
            self.maxTotal = maxTotal
        }

        @inline(__always)
        func skip(_ face: Int, after last: Int) -> Bool {
            face == last || (last >= 0 && face == last - 3 && face < 3)
        }

        func phase2(cp: Int, ep: Int, sp: Int, depth: Int, last: Int, out: inout [Int]) -> Bool {
            let n2 = RandomState333.phase2Moves.count
            let h = max(Int(t.pruneCpSp[cp * 24 + sp]), Int(t.pruneEpSp[ep * 24 + sp]))
            if h > depth { return false }
            if depth == 0 { return h == 0 }
            for (j, m) in RandomState333.phase2Moves.enumerated() {
                let f = m / 3
                if skip(f, after: last) { continue }
                out.append(m)
                if phase2(cp: Int(t.cpMove[cp * n2 + j]), ep: Int(t.epMove[ep * n2 + j]),
                          sp: Int(t.spMove[sp * n2 + j]), depth: depth - 1, last: f, out: &out) {
                    return true
                }
                out.removeLast()
            }
            return false
        }

        func phase1(tw: Int, fl: Int, sl: Int, depth: Int, last: Int) -> Bool {
            if depth == 0 {
                if tw != 0 || fl != 0 || sl != RandomState333.sliceSolved { return false }
                var c = cube
                for m in path { c = c.applying(RandomState333.moves[m]) }
                let cp = RandomState333.permRank(c.cp)
                let ep = RandomState333.permRank(c.ep[0..<8])
                let sp = RandomState333.permRank((8..<12).map { c.ep[$0] - 8 })
                var lim = maxTotal - path.count
                if let b = best { lim = min(lim, b.count - 1 - path.count) }
                lim = min(lim, 18)
                if lim < 0 { return false }
                for d2 in 0...lim {
                    var out: [Int] = []
                    if phase2(cp: cp, ep: ep, sp: sp, depth: d2, last: path.last.map { $0 / 3 } ?? -1, out: &out) {
                        best = path + out
                        return true
                    }
                }
                return false
            }
            for m in 0..<18 {
                let f = m / 3
                if skip(f, after: last) { continue }
                let ntw = Int(t.twistMove[tw * 18 + m])
                let nfl = Int(t.flipMove[fl * 18 + m])
                let nsl = Int(t.sliceMove[sl * 18 + m])
                let h = max(Int(t.pruneTwistSlice[ntw * RandomState333.nSlice + nsl]),
                            Int(t.pruneFlipSlice[nfl * RandomState333.nSlice + nsl]))
                if h > depth - 1 { continue }
                path.append(m)
                if phase1(tw: ntw, fl: nfl, sl: nsl, depth: depth - 1, last: f) {
                    path.removeLast()
                    return true
                }
                path.removeLast()
            }
            return false
        }

        func run(timeLimit: TimeInterval) -> [Int] {
            let tw = RandomState333.twist(cube.co)
            let fl = RandomState333.flip(cube.eo)
            let sl = RandomState333.sliceRank(cube.ep)
            var d1 = 0
            var start = ProcessInfo.processInfo.systemUptime
            while true {
                if d1 > 12 || ProcessInfo.processInfo.systemUptime - start > timeLimit {
                    if let b = best { return b }
                    maxTotal += 2   // relax the target until something is found
                    d1 = 0
                    start = ProcessInfo.processInfo.systemUptime
                }
                _ = phase1(tw: tw, fl: fl, sl: sl, depth: d1, last: -1)
                if let b = best, b.count <= maxTotal { return b }
                d1 += 1
            }
        }
    }

    /// Solution (move indices) taking `cube` to solved. Aims for <= 21 moves.
    static func solution(for cube: Cubie, maxTotal: Int = 21, timeLimit: TimeInterval = 1.0) -> [Int] {
        Search(tables: prepare(), cube: cube, maxTotal: maxTotal).run(timeLimit: timeLimit)
    }

    /// Scramble (WCA notation) that produces `cube` from solved: the inverse of the solution.
    static func scramble(for cube: Cubie) -> [String] {
        solution(for: cube).reversed().map { moveNames[inverseMove($0)] }
    }

    // MARK: Random state

    /// Uniformly random reachable cube: random permutations with the parity
    /// of the two matched, random orientations with the sums fixed.
    static func randomCube<G: RandomNumberGenerator>(using g: inout G) -> Cubie {
        var cp = Array(0..<8)
        cp.shuffle(using: &g)
        var ep = Array(0..<12)
        ep.shuffle(using: &g)
        if parity(cp) != parity(ep) { ep.swapAt(0, 1) }
        var co = (0..<7).map { _ in Int.random(in: 0..<3, using: &g) }
        co.append((3 - co.reduce(0, +) % 3) % 3)
        var eo = (0..<11).map { _ in Int.random(in: 0..<2, using: &g) }
        eo.append(eo.reduce(0, +) % 2)
        return Cubie(cp: cp, co: co, ep: ep, eo: eo)
    }

    /// A random-state scramble (blocking the first time while tables build).
    static func randomScramble<G: RandomNumberGenerator>(using g: inout G) -> [String] {
        scramble(for: randomCube(using: &g))
    }

    static func randomScramble() -> [String] {
        var g = SystemRandomNumberGenerator()
        return randomScramble(using: &g)
    }
}
