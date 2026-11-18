import Foundation

/// Random-state Square-1 scrambles (WCA style): pick a uniformly random
/// position, solve it, and hand out the inverse of the solution.
///
/// Model: 24 cells of 30 degrees, cells 0-11 the top layer and 12-23 the
/// bottom; a corner (pieces 0...7) fills two cells, an edge (8...15) one.
/// The slice swaps cells 6-11 with 12-17, so no corner may span 5|6 or 11|0.
///
/// Two phases:
///  1. Shape. The 3678 sliceable shapes x the parity of the piece order form
///     a graph of 7356 states with an exact distance table; walking it
///     downhill (a random distance-reducing turn each step, no search) ends
///     in cube shape with matching corner/edge parity.
///  2. Permutation. Inside cube shape the state is (corner permutation, edge
///     permutation) and there are 32 shape-preserving moves (top += 3i,
///     bottom += 3j, slice at offset 0 or 1). IDA* with three exact pruning
///     tables: corner perm, edge perm, and corner perm x edge 4-set
///     (2.82M entries, one nibble each).
///
/// About 8 MB of tables, built once by `prepare()` (call off the main
/// thread). `scripts/verify_square1_randomstate.py` mirrors this file line
/// for line and replays the scrambles on the app's Square1State.
enum Square1RandomState {
    static let permCount = 40320
    static let setCount = 70
    static let turnCount = 144
    /// Phase 2 gives up (the caller falls back to random-move) beyond this.
    static let nodeLimit = 20_000_000
    private static let fact: [Int] = [5040, 720, 120, 24, 6, 2, 1, 1]
    private static let cornerCells: [Int] = [0, 3, 6, 9, 12, 15, 18, 21]
    private static let edgeCells: [Int] = [2, 5, 8, 11, 14, 17, 20, 23]

    // MARK: Cell model

    static func mod12(_ x: Int) -> Int {
        return ((x % 12) + 12) % 12
    }

    /// Internal solved state: both layers read corner, corner, edge, ...
    /// (The app's solved state is this one with the bottom turned by +1.)
    static func solvedCells() -> [Int] {
        var s = [Int](repeating: 0, count: 24)
        for k in 0..<4 {
            s[3 * k] = k
            s[3 * k + 1] = k
            s[3 * k + 2] = 8 + k
            s[12 + 3 * k] = 4 + k
            s[12 + 3 * k + 1] = 4 + k
            s[12 + 3 * k + 2] = 12 + k
        }
        return s
    }

    static func turned(_ s: [Int], _ t: Int, _ b: Int) -> [Int] {
        var out = [Int](repeating: 0, count: 24)
        for i in 0..<12 {
            out[i] = s[mod12(i - t)]
            out[12 + i] = s[12 + mod12(i - b)]
        }
        return out
    }

    static func sliced(_ s: [Int]) -> [Int] {
        var out = s
        for i in 0..<6 {
            out[6 + i] = s[12 + i]
            out[12 + i] = s[6 + i]
        }
        return out
    }

    static func joined(_ a: Int, _ b: Int) -> Bool {
        return a == b && a < 8
    }

    static func isLegal(_ s: [Int]) -> Bool {
        return !(joined(s[11], s[0]) || joined(s[5], s[6])
                 || joined(s[23], s[12]) || joined(s[17], s[18]))
    }

    // MARK: Shape masks
    // Bit i (top) / 12 + i (bottom) is set when cell i holds the first half
    // of a corner (cell i + 1 the second half).

    static func shapeMask(_ s: [Int]) -> Int {
        var mask = 0
        for base in [0, 12] {
            for i in 0..<12 {
                let a = s[base + i]
                if a < 8 && a == s[base + (i + 1) % 12] {
                    mask |= 1 << (base + i)
                }
            }
        }
        return mask
    }

    static func rot12(_ x: Int, _ t: Int) -> Int {
        let k = mod12(t)
        return ((x << k) | (x >> (12 - k))) & 0xFFF
    }

    static func turnMask(_ mask: Int, _ t: Int, _ b: Int) -> Int {
        return rot12(mask & 0xFFF, t) | (rot12((mask >> 12) & 0xFFF, b) << 12)
    }

    static func maskLegal(_ mask: Int) -> Bool {
        return (mask & 0x820820) == 0
    }

    static func sliceMask(_ mask: Int) -> Int {
        let lo = (mask >> 6) & 0x3F
        let hi = (mask >> 12) & 0x3F
        return (mask & 0xFC003F) | (hi << 6) | (lo << 12)
    }

    /// Fills a (legal) shape with the given corners and edges in cell order.
    static func cells(for mask: Int, corners: [Int], edges: [Int]) -> [Int] {
        var s = [Int](repeating: 0, count: 24)
        var ci = 0
        var ei = 0
        var i = 0
        while i < 24 {
            if (mask >> i) & 1 == 1 {
                s[i] = corners[ci]
                s[i + 1] = corners[ci]
                ci += 1
                i += 2
            } else {
                s[i] = edges[ei]
                ei += 1
                i += 1
            }
        }
        return s
    }

    // MARK: Permutations

    static func inversionParity(_ p: [Int]) -> Int {
        var n = 0
        for i in 0..<p.count {
            for j in (i + 1)..<p.count where p[j] < p[i] {
                n += 1
            }
        }
        return n & 1
    }

    /// 0 when the corner order and the edge order (read cell by cell) have
    /// the same sign, 1 otherwise.
    static func parityBit(_ s: [Int]) -> Int {
        var c: [Int] = []
        var e: [Int] = []
        var i = 0
        while i < 24 {
            let x = s[i]
            if x < 8 {
                c.append(x)
                i += 2
            } else {
                e.append(x - 8)
                i += 1
            }
        }
        return inversionParity(c) ^ inversionParity(e)
    }

    /// Lehmer rank (lexicographic index) of a permutation of 0...7.
    static func permRank(_ p: [Int]) -> Int {
        var n = 0
        for k in 0..<8 {
            var less = 0
            for j in (k + 1)..<8 where p[j] < p[k] {
                less += 1
            }
            n += less * fact[k]
        }
        return n
    }

    static func permUnrank(_ n: Int) -> [Int] {
        var rest: [Int] = [0, 1, 2, 3, 4, 5, 6, 7]
        var p = [Int](repeating: 0, count: 8)
        var r = n
        for k in 0..<8 {
            let d = r / fact[k]
            r = r % fact[k]
            p[k] = rest.remove(at: d)
        }
        return p
    }

    static func cornerSlots(_ s: [Int]) -> [Int] {
        var out = [Int](repeating: 0, count: 8)
        for k in 0..<8 { out[k] = s[cornerCells[k]] }
        return out
    }

    static func edgeSlots(_ s: [Int]) -> [Int] {
        var out = [Int](repeating: 0, count: 8)
        for k in 0..<8 { out[k] = s[edgeCells[k]] - 8 }
        return out
    }

    /// Slots holding pieces 0...3, as an 8-bit mask.
    static func setMask(of p: [Int]) -> Int {
        var mask = 0
        for k in 0..<8 where p[k] < 4 {
            mask |= 1 << k
        }
        return mask
    }

    static func movedSetMask(_ mask: Int, _ p: [Int]) -> Int {
        var out = 0
        for k in 0..<8 where (mask >> p[k]) & 1 == 1 {
            out |= 1 << k
        }
        return out
    }

    static func turnIndex(_ t: Int, _ b: Int) -> Int {
        return (t + 5) * 12 + (b + 5)
    }

    @inline(__always)
    static func nibble(_ tab: [UInt8], _ i: Int) -> Int {
        return (Int(tab[i >> 1]) >> ((i & 1) * 4)) & 15
    }

    // MARK: Tables

    final class Tables {
        // Phase 1.
        /// Every sliceable shape; index 0 is the solved (aligned cube) shape.
        let shapeMasks: [Int]
        let shapeCount: Int
        /// [shape * 144 + turn] = next shape * 2 + parity flip, or -1.
        let shapeMove: [Int16]
        /// [shape * 2 + parity] = slices to (solved shape, parity 0).
        let shapeDist: [UInt8]
        // Phase 2. Move m = (i * 4 + j) * 2 + o.
        let setIndex: [Int]
        /// [m * 40320 + corner perm] / [m * 40320 + edge perm].
        let cornerMove: [UInt16]
        let edgeMove: [UInt16]
        /// [m * 70 + edge set].
        let edgeSetMove: [UInt8]
        let goalCorner: [Int]
        let goalEdge: [Int]
        let cornerDist: [UInt8]
        let edgeDist: [UInt8]
        /// Nibbles, entry = corner perm * 70 + edge set.
        let cornerSetDist: [UInt8]

        init() {
            let shapes = Square1RandomState.buildShapes()
            shapeMasks = shapes.masks
            shapeCount = shapes.masks.count
            shapeMove = shapes.move
            shapeDist = shapes.dist
            let p2 = Square1RandomState.buildPhase2()
            setIndex = p2.setIndex
            cornerMove = p2.cm
            edgeMove = p2.em
            edgeSetMove = p2.esm
            goalCorner = p2.goalC
            goalEdge = p2.goalE
            cornerDist = p2.dc
            edgeDist = p2.de
            cornerSetDist = p2.dcs
        }
    }

    /// Phase 1 tables: shapes, shape moves with parity flip, and the
    /// (shape, parity) distance.
    static func buildShapes() -> (masks: [Int], move: [Int16], dist: [UInt8]) {
        let solved = solvedCells()
        let start = shapeMask(solved)
        var masks: [Int] = [start]
        var index: [Int: Int] = [start: 0]
        var head = 0
        while head < masks.count {
            let y = sliceMask(masks[head])
            head += 1
            for t in -5...6 {
                for b in -5...6 {
                    let p = turnMask(y, t, b)
                    if maskLegal(p) && index[p] == nil {
                        index[p] = masks.count
                        masks.append(p)
                    }
                }
            }
        }
        let n = masks.count

        let identC: [Int] = [0, 1, 2, 3, 4, 5, 6, 7]
        let identE: [Int] = [8, 9, 10, 11, 12, 13, 14, 15]
        var mv = [Int16](repeating: -1, count: n * turnCount)
        for idx in 0..<n {
            let mask = masks[idx]
            let base = cells(for: mask, corners: identC, edges: identE)
            for t in -5...6 {
                for b in -5...6 {
                    let x = turnMask(mask, t, b)
                    if !maskLegal(x) { continue }
                    guard let nxt = index[sliceMask(x)] else { continue }
                    let flip = parityBit(sliced(turned(base, t, b)))
                    mv[idx * turnCount + turnIndex(t, b)] = Int16(nxt * 2 + flip)
                }
            }
        }

        var dist = [UInt8](repeating: 255, count: n * 2)
        dist[0] = 0
        var depth = 0
        var changed = true
        while changed {
            changed = false
            for st in 0..<(n * 2) {
                if dist[st] != 255 { continue }
                let idx = st >> 1
                let par = st & 1
                for m in 0..<turnCount {
                    let e = Int(mv[idx * turnCount + m])
                    if e < 0 { continue }
                    if Int(dist[e ^ par]) == depth {
                        dist[st] = UInt8(depth + 1)
                        changed = true
                        break
                    }
                }
            }
            depth += 1
        }
        return (masks: masks, move: mv, dist: dist)
    }

    /// Distance of every permutation index to the goal set (moves are applied
    /// forward, so a state is one further than its nearest successor).
    static func permDistance(move: [UInt16], goals: [Int]) -> [UInt8] {
        let np = permCount
        var dist = [UInt8](repeating: 255, count: np)
        for g in goals { dist[g] = 0 }
        var depth = 0
        var changed = true
        while changed {
            changed = false
            for n in 0..<np {
                if dist[n] != 255 { continue }
                for m in 0..<32 {
                    if Int(dist[Int(move[m * np + n])]) == depth {
                        dist[n] = UInt8(depth + 1)
                        changed = true
                        break
                    }
                }
            }
            depth += 1
        }
        return dist
    }

    /// Phase 2 tables.
    static func buildPhase2() -> (setIndex: [Int], cm: [UInt16], em: [UInt16], esm: [UInt8],
                                  goalC: [Int], goalE: [Int], dc: [UInt8], de: [UInt8], dcs: [UInt8]) {
        let np = permCount
        let ns = setCount
        let solved = solvedCells()

        // Slot permutations of the 10 generators (new[k] = old[p[k]]):
        // top turns, bottom turns, slice at offset 0 and at offset 1.
        var genC: [[Int]] = []
        var genE: [[Int]] = []
        for i in 0..<4 {
            let x = turned(solved, 3 * i, 0)
            genC.append(cornerSlots(x))
            genE.append(edgeSlots(x))
        }
        for j in 0..<4 {
            let x = turned(solved, 0, 3 * j)
            genC.append(cornerSlots(x))
            genE.append(edgeSlots(x))
        }
        let s0 = sliced(solved)
        genC.append(cornerSlots(s0))
        genE.append(edgeSlots(s0))
        let s1 = turned(sliced(turned(solved, 1, 1)), -1, -1)
        genC.append(cornerSlots(s1))
        genE.append(edgeSlots(s1))

        // Generator tables over the permutation index.
        var gc = [UInt16](repeating: 0, count: 10 * np)
        var ge = [UInt16](repeating: 0, count: 10 * np)
        var q = [Int](repeating: 0, count: 8)
        for n in 0..<np {
            let a = permUnrank(n)
            for g in 0..<10 {
                let pc = genC[g]
                for k in 0..<8 { q[k] = a[pc[k]] }
                gc[g * np + n] = UInt16(permRank(q))
                let pe = genE[g]
                for k in 0..<8 { q[k] = a[pe[k]] }
                ge[g * np + n] = UInt16(permRank(q))
            }
        }

        // 4-sets of slots.
        var setIndex = [Int](repeating: -1, count: 256)
        var setMasks: [Int] = []
        for mask in 0..<256 where mask.nonzeroBitCount == 4 {
            setIndex[mask] = setMasks.count
            setMasks.append(mask)
        }
        var gs = [Int](repeating: 0, count: 10 * ns)
        for g in 0..<10 {
            for s in 0..<ns {
                gs[g * ns + s] = setIndex[movedSetMask(setMasks[s], genE[g])]
            }
        }

        // Compose the 32 moves.
        var cm = [UInt16](repeating: 0, count: 32 * np)
        var em = [UInt16](repeating: 0, count: 32 * np)
        var esm = [UInt8](repeating: 0, count: 32 * ns)
        for m in 0..<32 {
            let i = m >> 3
            let j = (m >> 1) & 3
            let o = m & 1
            for n in 0..<np {
                let c1 = Int(gc[i * np + n])
                let c2 = Int(gc[(4 + j) * np + c1])
                cm[m * np + n] = gc[(8 + o) * np + c2]
                let e1 = Int(ge[i * np + n])
                let e2 = Int(ge[(4 + j) * np + e1])
                em[m * np + n] = ge[(8 + o) * np + e2]
            }
            for s in 0..<ns {
                let s1 = gs[i * ns + s]
                let s2 = gs[(4 + j) * ns + s1]
                esm[m * ns + s] = UInt8(gs[(8 + o) * ns + s2])
            }
        }
        gc = []
        ge = []

        // Goal: the 16 turns of solved that keep both layers aligned.
        var goalC: [Int] = []
        var goalE: [Int] = []
        var goalCS: [Int] = []
        for i in 0..<4 {
            for j in 0..<4 {
                let x = turned(solved, 3 * i, 3 * j)
                let c = cornerSlots(x)
                let e = edgeSlots(x)
                goalC.append(permRank(c))
                goalE.append(permRank(e))
                goalCS.append(permRank(c) * ns + setIndex[setMask(of: e)])
            }
        }

        let dc = permDistance(move: cm, goals: goalC)
        let de = permDistance(move: em, goals: goalE)

        // (corner perm x edge 4-set) distance, one nibble per entry, built
        // breadth-first from the goal through the inverse move tables.
        var invC = [UInt16](repeating: 0, count: 32 * np)
        var invS = [UInt8](repeating: 0, count: 32 * ns)
        for m in 0..<32 {
            for n in 0..<np {
                invC[m * np + Int(cm[m * np + n])] = UInt16(n)
            }
            for s in 0..<ns {
                invS[m * ns + Int(esm[m * ns + s])] = UInt8(s)
            }
        }
        let total = np * ns
        var dcs = [UInt8](repeating: 255, count: total / 2)
        dcs.withUnsafeMutableBufferPointer { d in
            invC.withUnsafeBufferPointer { ic in
                invS.withUnsafeBufferPointer { isv in
                    for g in goalCS {
                        let sh = (g & 1) * 4
                        let keep = Int(d[g >> 1]) & (0xF0 >> sh)
                        d[g >> 1] = UInt8(keep)
                    }
                    var depth = 0
                    var added = 1
                    while added > 0 && depth < 14 {
                        added = 0
                        for idx in 0..<total {
                            if (Int(d[idx >> 1]) >> ((idx & 1) * 4)) & 15 != depth { continue }
                            let c = idx / ns
                            let s = idx % ns
                            for m in 0..<32 {
                                let p = Int(ic[m * np + c]) * ns + Int(isv[m * ns + s])
                                let sh = (p & 1) * 4
                                let cur = Int(d[p >> 1])
                                if (cur >> sh) & 15 == 15 {
                                    let keep = cur & (0xF0 >> sh)
                                    let value = (depth + 1) << sh
                                    d[p >> 1] = UInt8(keep | value)
                                    added += 1
                                }
                            }
                        }
                        depth += 1
                    }
                }
            }
        }
        return (setIndex: setIndex, cm: cm, em: em, esm: esm,
                goalC: goalC, goalE: goalE, dc: dc, de: de, dcs: dcs)
    }

    private final class Store: @unchecked Sendable {
        let lock = NSLock()
        let buildLock = NSLock()
        var tables: Tables?
    }

    private static let store = Store()

    /// True once the tables are built (generation then takes milliseconds).
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

    /// IDA* over (corner perm, edge perm, edge 4-set) inside cube shape.
    final class Search {
        let t: Tables
        var path: [Int] = []
        var nodes: Int = 0

        init(tables: Tables) {
            t = tables
        }

        func isGoal(_ c: Int, _ e: Int) -> Bool {
            for k in 0..<16 where t.goalCorner[k] == c && t.goalEdge[k] == e {
                return true
            }
            return false
        }

        func dfs(_ c: Int, _ e: Int, _ es: Int, _ rem: Int) -> Bool {
            nodes += 1
            if rem == 0 { return isGoal(c, e) }
            if nodes > Square1RandomState.nodeLimit { return false }
            let np = Square1RandomState.permCount
            let ns = Square1RandomState.setCount
            for m in 0..<32 {
                let c2 = Int(t.cornerMove[m * np + c])
                if Int(t.cornerDist[c2]) >= rem { continue }
                let e2 = Int(t.edgeMove[m * np + e])
                if Int(t.edgeDist[e2]) >= rem { continue }
                let es2 = Int(t.edgeSetMove[m * ns + es])
                if Square1RandomState.nibble(t.cornerSetDist, c2 * ns + es2) >= rem { continue }
                path.append(m)
                if dfs(c2, e2, es2, rem - 1) { return true }
                path.removeLast()
            }
            return false
        }

        /// Shortest move sequence to a goal, left in `path`.
        func solve(c: Int, e: Int, es: Int, maxDepth: Int) -> Bool {
            var rem = max(Int(t.cornerDist[c]), Int(t.edgeDist[e]),
                          Square1RandomState.nibble(t.cornerSetDist, c * Square1RandomState.setCount + es))
            while rem <= maxDepth && nodes <= Square1RandomState.nodeLimit {
                path = []
                if dfs(c, e, es, rem) { return true }
                rem += 1
            }
            return false
        }
    }

    // MARK: Random state

    /// Uniformly random sliceable position: random shape, random pieces.
    static func randomState<G: RandomNumberGenerator>(_ t: Tables, using g: inout G) -> (cells: [Int], shape: Int) {
        let idx = Int.random(in: 0..<t.shapeCount, using: &g)
        var corners: [Int] = [0, 1, 2, 3, 4, 5, 6, 7]
        var edges: [Int] = [8, 9, 10, 11, 12, 13, 14, 15]
        corners.shuffle(using: &g)
        edges.shuffle(using: &g)
        return (cells: cells(for: t.shapeMasks[idx], corners: corners, edges: edges), shape: idx)
    }

    static func norm(_ a: Int) -> Int {
        let m = mod12(a)
        return m > 6 ? m - 12 : m
    }

    /// Tokens that take the app's solved Square-1 to `state` (whose shape is
    /// `shape`): `(x,y)/` per slice, a bare `/` only as the first token, and
    /// a last `(x,y)` without slice when a final turn is needed. Nil if the
    /// solver gives up, which should not happen.
    static func scramble<G: RandomNumberGenerator>(_ t: Tables, state: [Int], shape: Int,
                                                   using g: inout G) -> [String]? {
        // Phase 1: to aligned cube shape with matching parity.
        var sol: [(Int, Int)] = []
        var x = state
        var idx = shape
        var par = parityBit(x)
        while true {
            let d = Int(t.shapeDist[idx * 2 + par])
            if d == 0 { break }
            if d == 255 { return nil }
            var options: [Int] = []
            for m in 0..<turnCount {
                let e = Int(t.shapeMove[idx * turnCount + m])
                if e >= 0 && Int(t.shapeDist[e ^ par]) == d - 1 {
                    options.append(m)
                }
            }
            if options.isEmpty { return nil }
            let m = options[Int.random(in: 0..<options.count, using: &g)]
            let tt = m / 12 - 5
            let bb = m % 12 - 5
            let e = Int(t.shapeMove[idx * turnCount + m]) ^ par
            idx = e >> 1
            par = e & 1
            x = sliced(turned(x, tt, bb))
            sol.append((tt, bb))
        }

        // Phase 2: permutations inside cube shape.
        let cs = cornerSlots(x)
        let es = edgeSlots(x)
        let search = Search(tables: t)
        if !search.solve(c: permRank(cs), e: permRank(es), es: t.setIndex[setMask(of: es)], maxDepth: 40) {
            return nil
        }
        var offset = 0
        for m in search.path {
            let o = m & 1
            let tt = 3 * (m >> 3) + o - offset
            let bb = 3 * ((m >> 1) & 3) + o - offset
            x = turned(x, tt, bb)
            if !isLegal(x) { return nil }
            x = sliced(x)
            sol.append((tt, bb))
            offset = o
        }

        // Final turn back to the internal solved state.
        let solved = solvedCells()
        var finA = -1
        var finB = -1
        for a in 0..<12 {
            for b in 0..<12 where finA < 0 && turned(x, a, b) == solved {
                finA = a
                finB = b
            }
        }
        if finA < 0 { return nil }

        // The scramble is the inverse, read backwards. The app's solved state
        // is the internal one with the bottom layer turned by +1, hence the -1.
        var seq: [(Int, Int)] = [(-finA, -finB - 1)]
        var k = sol.count - 1
        while k >= 0 {
            seq.append((-sol[k].0, -sol[k].1))
            k -= 1
        }
        // A (0,0) turn between two slices cancels both slices.
        var i = 1
        while i < seq.count - 1 {
            if mod12(seq[i].0) == 0 && mod12(seq[i].1) == 0 {
                seq[i - 1] = (seq[i - 1].0 + seq[i + 1].0, seq[i - 1].1 + seq[i + 1].1)
                seq.removeSubrange(i..<(i + 2))
                i = max(1, i - 1)
            } else {
                i += 1
            }
        }
        var tokens: [String] = []
        for n in 0..<seq.count {
            let a = norm(seq[n].0)
            let b = norm(seq[n].1)
            let last = n == seq.count - 1
            if a == 0 && b == 0 {
                if !last { tokens.append("/") }
            } else {
                tokens.append("(\(a),\(b))" + (last ? "" : "/"))
            }
        }
        return tokens
    }

    /// A random-state scramble (blocking the first time while tables build).
    static func randomScramble<G: RandomNumberGenerator>(using g: inout G) -> [String]? {
        let t = prepare()
        let state = randomState(t, using: &g)
        return scramble(t, state: state.cells, shape: state.shape, using: &g)
    }

    static func randomScramble() -> [String]? {
        var g = SystemRandomNumberGenerator()
        return randomScramble(using: &g)
    }
}
