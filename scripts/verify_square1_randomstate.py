#!/usr/bin/env python3
"""Python mirror + verifier for the random-state Square-1 scrambler
(Square1RandomState.swift).  Run: python3 -I scripts/verify_square1_randomstate.py [N] [SEED]

The functions below mirror the Swift file name for name and line for line
(same cell model, same flat table layouts, same Lehmer ranking, same search),
in pure Python (no numpy), so a logic error in one shows up in the other.
Building the tables takes a minute or two here (a few seconds natively).

Algorithm (two phases, both on a 24-cell model: 12 cells of 30 degrees per
layer, a corner fills two cells, an edge one):
  * random state: a uniformly random sliceable shape (3678 of them) with a
    uniformly random assignment of the 8 corners and 8 edges
  * phase 1: walk the (shape, parity) graph (3678 x 2 states, exact distance
    table) down to "aligned cube shape with matching corner/edge parity";
    no search, every step is a random distance-reducing move
  * phase 2: IDA* inside cube shape on (corner permutation, edge permutation)
    with the 32 shape-preserving moves, pruned by the corner-perm table, the
    edge-perm table and a (corner perm x edge 4-set) table (2.82M nibbles)
  * scramble = inverse of the solution, written as "(top,bottom)/" tokens

Checks performed for N random states (default 200):
  * the tokens, replayed from solved on a port of the app's Square1State
    (Square1MapView.swift), give exactly the intended random state
  * replayed on the cell model, every slice is legal (no corner on the cut)
  * token format: "(a,b)/" per slice, a bare "/" only as the first token, an
    optional last "(a,b)" without slice, a/b in -5...6, never (0,0), <= 8 chars
  * the (shape, parity) table covers all 7356 states; the parity tracked in
    phase 1 equals the parity of the real state; table depth histograms
Prints slice-count and node-count statistics."""
import random
import re
import sys
import time
from array import array

N_PERM = 40320
N_SET = 70
N_TURN = 144
FACT = [5040, 720, 120, 24, 6, 2, 1, 1]
CORNER_CELLS = [0, 3, 6, 9, 12, 15, 18, 21]
EDGE_CELLS = [2, 5, 8, 11, 14, 17, 20, 23]


# ------------------------------------------------------------- cell model

def mod12(x):
    return ((x % 12) + 12) % 12


def solved_cells():
    """Internal solved state: both layers read corner, corner, edge, ...
    Corners are 0...7, edges 8...15."""
    s = [0] * 24
    for k in range(4):
        s[3 * k] = k
        s[3 * k + 1] = k
        s[3 * k + 2] = 8 + k
        s[12 + 3 * k] = 4 + k
        s[12 + 3 * k + 1] = 4 + k
        s[12 + 3 * k + 2] = 12 + k
    return s


def turned(s, t, b):
    out = [0] * 24
    for i in range(12):
        out[i] = s[mod12(i - t)]
        out[12 + i] = s[12 + mod12(i - b)]
    return out


def sliced(s):
    out = s[:]
    for i in range(6):
        out[6 + i] = s[12 + i]
        out[12 + i] = s[6 + i]
    return out


def joined(a, b):
    return a == b and a < 8


def is_legal(s):
    return not (joined(s[11], s[0]) or joined(s[5], s[6])
                or joined(s[23], s[12]) or joined(s[17], s[18]))


# ------------------------------------------------------------- shape masks
# Bit i (top) / 12 + i (bottom) is set when cell i holds the first half of a
# corner (cell i + 1 the second half).

def shape_mask(s):
    mask = 0
    for base in (0, 12):
        for i in range(12):
            a = s[base + i]
            if a < 8 and a == s[base + (i + 1) % 12]:
                mask |= 1 << (base + i)
    return mask


def rot12(x, t):
    k = mod12(t)
    return ((x << k) | (x >> (12 - k))) & 0xFFF


def turn_mask(mask, t, b):
    return rot12(mask & 0xFFF, t) | (rot12((mask >> 12) & 0xFFF, b) << 12)


def mask_legal(mask):
    return (mask & 0x820820) == 0


def slice_mask(mask):
    lo = (mask >> 6) & 0x3F
    hi = (mask >> 12) & 0x3F
    return (mask & 0xFC003F) | (hi << 6) | (lo << 12)


def cells_for(mask, corners, edges):
    """Fill a (legal) shape with the given corners and edges in cell order."""
    s = [0] * 24
    ci = 0
    ei = 0
    i = 0
    while i < 24:
        if (mask >> i) & 1 == 1:
            s[i] = corners[ci]
            s[i + 1] = corners[ci]
            ci += 1
            i += 2
        else:
            s[i] = edges[ei]
            ei += 1
            i += 1
    return s


# ------------------------------------------------------------- permutations

def inversion_parity(p):
    n = 0
    for i in range(len(p)):
        for j in range(i + 1, len(p)):
            if p[j] < p[i]:
                n += 1
    return n & 1


def parity_bit(s):
    """0 when the corner order and the edge order (read cell by cell) have
    the same sign, 1 otherwise."""
    c = []
    e = []
    i = 0
    while i < 24:
        x = s[i]
        if x < 8:
            c.append(x)
            i += 2
        else:
            e.append(x - 8)
            i += 1
    return inversion_parity(c) ^ inversion_parity(e)


def perm_rank(p):
    n = 0
    for k in range(8):
        less = 0
        for j in range(k + 1, 8):
            if p[j] < p[k]:
                less += 1
        n += less * FACT[k]
    return n


def perm_unrank(n):
    rest = [0, 1, 2, 3, 4, 5, 6, 7]
    p = [0] * 8
    r = n
    for k in range(8):
        d = r // FACT[k]
        r = r % FACT[k]
        p[k] = rest.pop(d)
    return p


def corner_slots(s):
    return [s[c] for c in CORNER_CELLS]


def edge_slots(s):
    return [s[c] - 8 for c in EDGE_CELLS]


def set_mask_of(p):
    """Slots holding pieces 0...3, as an 8-bit mask."""
    mask = 0
    for k in range(8):
        if p[k] < 4:
            mask |= 1 << k
    return mask


def moved_set_mask(mask, p):
    out = 0
    for k in range(8):
        if (mask >> p[k]) & 1 == 1:
            out |= 1 << k
    return out


def turn_index(t, b):
    return (t + 5) * 12 + (b + 5)


def get_nibble(tab, i):
    return (tab[i >> 1] >> ((i & 1) * 4)) & 15


def set_nibble(tab, i, v):
    sh = (i & 1) * 4
    tab[i >> 1] = (tab[i >> 1] & ~(15 << sh) & 0xFF) | (v << sh)


# ------------------------------------------------------------- tables

class Tables:
    def __init__(self):
        self.build_shapes()
        self.build_phase2()

    # --- phase 1: shapes, shape moves with parity flip, (shape, parity) distance
    def build_shapes(self):
        solved = solved_cells()
        start = shape_mask(solved)
        masks = [start]
        index = {start: 0}
        head = 0
        while head < len(masks):
            y = slice_mask(masks[head])
            head += 1
            for t in range(-5, 7):
                for b in range(-5, 7):
                    p = turn_mask(y, t, b)
                    if mask_legal(p) and p not in index:
                        index[p] = len(masks)
                        masks.append(p)
        n = len(masks)
        self.shape_masks = masks
        self.shape_count = n

        # shape_move[idx * 144 + turn] = next idx * 2 + parity flip, or -1.
        ident_c = [0, 1, 2, 3, 4, 5, 6, 7]
        ident_e = [8, 9, 10, 11, 12, 13, 14, 15]
        mv = array('h', [-1]) * (n * N_TURN)
        for idx in range(n):
            mask = masks[idx]
            cells = cells_for(mask, ident_c, ident_e)
            for t in range(-5, 7):
                for b in range(-5, 7):
                    x = turn_mask(mask, t, b)
                    if not mask_legal(x):
                        continue
                    nxt = index.get(slice_mask(x))
                    if nxt is None:
                        continue
                    flip = parity_bit(sliced(turned(cells, t, b)))
                    mv[idx * N_TURN + turn_index(t, b)] = nxt * 2 + flip
        self.shape_move = mv

        # Distance of (shape, parity) to (solved shape, parity 0).
        dist = bytearray([255]) * (n * 2)
        dist[0] = 0
        depth = 0
        changed = True
        while changed:
            changed = False
            for st in range(n * 2):
                if dist[st] != 255:
                    continue
                idx = st >> 1
                par = st & 1
                for m in range(N_TURN):
                    e = mv[idx * N_TURN + m]
                    if e < 0:
                        continue
                    if dist[e ^ par] == depth:
                        dist[st] = depth + 1
                        changed = True
                        break
            depth += 1
        self.shape_dist = dist

    # --- phase 2: 32 moves (i, j, o): top += 3i, bottom += 3j, slice at offset o
    def build_phase2(self):
        solved = solved_cells()
        gen_c = []
        gen_e = []
        for i in range(4):
            x = turned(solved, 3 * i, 0)
            gen_c.append(corner_slots(x))
            gen_e.append(edge_slots(x))
        for j in range(4):
            x = turned(solved, 0, 3 * j)
            gen_c.append(corner_slots(x))
            gen_e.append(edge_slots(x))
        x = sliced(solved)
        gen_c.append(corner_slots(x))
        gen_e.append(edge_slots(x))
        x = turned(sliced(turned(solved, 1, 1)), -1, -1)
        gen_c.append(corner_slots(x))
        gen_e.append(edge_slots(x))

        # Generator tables over the permutation index (new[k] = old[p[k]]).
        gc = array('H', [0]) * (10 * N_PERM)
        ge = array('H', [0]) * (10 * N_PERM)
        q = [0] * 8
        for n in range(N_PERM):
            a = perm_unrank(n)
            for g in range(10):
                p = gen_c[g]
                for k in range(8):
                    q[k] = a[p[k]]
                gc[g * N_PERM + n] = perm_rank(q)
                p = gen_e[g]
                for k in range(8):
                    q[k] = a[p[k]]
                ge[g * N_PERM + n] = perm_rank(q)

        # 4-sets of slots.
        set_index = [-1] * 256
        set_masks = []
        for mask in range(256):
            if bin(mask).count("1") == 4:
                set_index[mask] = len(set_masks)
                set_masks.append(mask)
        self.set_index = set_index
        gs = [0] * (10 * N_SET)
        for g in range(10):
            for s in range(N_SET):
                gs[g * N_SET + s] = set_index[moved_set_mask(set_masks[s], gen_e[g])]

        # Compose the 32 moves: m = (i * 4 + j) * 2 + o.
        cm = array('H', [0]) * (32 * N_PERM)
        em = array('H', [0]) * (32 * N_PERM)
        esm = bytearray(32 * N_SET)
        for m in range(32):
            i = m >> 3
            j = (m >> 1) & 3
            o = m & 1
            for n in range(N_PERM):
                cm[m * N_PERM + n] = gc[(8 + o) * N_PERM + gc[(4 + j) * N_PERM + gc[i * N_PERM + n]]]
                em[m * N_PERM + n] = ge[(8 + o) * N_PERM + ge[(4 + j) * N_PERM + ge[i * N_PERM + n]]]
            for s in range(N_SET):
                esm[m * N_SET + s] = gs[(8 + o) * N_SET + gs[(4 + j) * N_SET + gs[i * N_SET + s]]]
        self.cm = cm
        self.em = em
        self.esm = esm

        # Goal: the 16 turns of solved that keep both layers aligned.
        goal_c = []
        goal_e = []
        goal_cs = []
        for i in range(4):
            for j in range(4):
                x = turned(solved, 3 * i, 3 * j)
                c = corner_slots(x)
                e = edge_slots(x)
                goal_c.append(perm_rank(c))
                goal_e.append(perm_rank(e))
                goal_cs.append(perm_rank(c) * N_SET + set_index[set_mask_of(e)])
        self.goal_c = goal_c
        self.goal_e = goal_e

        self.dc = self.perm_distance(cm, goal_c)
        self.de = self.perm_distance(em, goal_e)

        # (corner perm x edge 4-set) distance, one nibble per entry, built
        # breadth-first from the goal through the inverse move tables.
        inv_c = array('H', [0]) * (32 * N_PERM)
        inv_s = bytearray(32 * N_SET)
        for m in range(32):
            for n in range(N_PERM):
                inv_c[m * N_PERM + cm[m * N_PERM + n]] = n
            for s in range(N_SET):
                inv_s[m * N_SET + esm[m * N_SET + s]] = s
        total = N_PERM * N_SET
        dcs = bytearray([255]) * (total // 2)
        for g in goal_cs:
            set_nibble(dcs, g, 0)
        depth = 0
        added = 1
        while added > 0 and depth < 14:
            added = 0
            for idx in range(total):
                if (dcs[idx >> 1] >> ((idx & 1) * 4)) & 15 != depth:
                    continue
                c = idx // N_SET
                s = idx % N_SET
                for m in range(32):
                    p = inv_c[m * N_PERM + c] * N_SET + inv_s[m * N_SET + s]
                    if (dcs[p >> 1] >> ((p & 1) * 4)) & 15 == 15:
                        set_nibble(dcs, p, depth + 1)
                        added += 1
            depth += 1
        self.dcs = dcs

    @staticmethod
    def perm_distance(move, goals):
        """Distance of every permutation index to the goal set (moves are
        applied forward, so a state is one further than its nearest successor)."""
        dist = bytearray([255]) * N_PERM
        for g in goals:
            dist[g] = 0
        depth = 0
        changed = True
        while changed:
            changed = False
            for n in range(N_PERM):
                if dist[n] != 255:
                    continue
                for m in range(32):
                    if dist[move[m * N_PERM + n]] == depth:
                        dist[n] = depth + 1
                        changed = True
                        break
            depth += 1
        return dist


# ------------------------------------------------------------- solver

class Search:
    def __init__(self, tables):
        self.t = tables
        self.path = []
        self.nodes = 0

    def is_goal(self, c, e):
        t = self.t
        for k in range(16):
            if t.goal_c[k] == c and t.goal_e[k] == e:
                return True
        return False

    def dfs(self, c, e, es, rem):
        self.nodes += 1
        if rem == 0:
            return self.is_goal(c, e)
        t = self.t
        for m in range(32):
            c2 = t.cm[m * N_PERM + c]
            if t.dc[c2] >= rem:
                continue
            e2 = t.em[m * N_PERM + e]
            if t.de[e2] >= rem:
                continue
            es2 = t.esm[m * N_SET + es]
            if get_nibble(t.dcs, c2 * N_SET + es2) >= rem:
                continue
            self.path.append(m)
            if self.dfs(c2, e2, es2, rem - 1):
                return True
            self.path.pop()
        return False

    def solve(self, c, e, es, max_depth):
        t = self.t
        rem = max(t.dc[c], t.de[e], get_nibble(t.dcs, c * N_SET + es))
        while rem <= max_depth:
            self.path = []
            if self.dfs(c, e, es, rem):
                return True
            rem += 1
        return False


def random_state(t, rng):
    """Uniformly random sliceable position: random shape, random pieces."""
    idx = rng.randrange(t.shape_count)
    corners = [0, 1, 2, 3, 4, 5, 6, 7]
    edges = [8, 9, 10, 11, 12, 13, 14, 15]
    rng.shuffle(corners)
    rng.shuffle(edges)
    return cells_for(t.shape_masks[idx], corners, edges), idx


def norm(a):
    m = mod12(a)
    return m - 12 if m > 6 else m


STATS = {}


def scramble(t, state, shape_idx, rng):
    """Tokens that take the app's solved Square-1 to `state` (None on failure)."""
    # Phase 1: to aligned cube shape with matching parity.
    sol = []
    x = state
    idx = shape_idx
    par = parity_bit(x)
    while t.shape_dist[idx * 2 + par] > 0:
        d = t.shape_dist[idx * 2 + par]
        if d == 255:
            return None
        options = []
        for m in range(N_TURN):
            e = t.shape_move[idx * N_TURN + m]
            if e >= 0 and t.shape_dist[e ^ par] == d - 1:
                options.append(m)
        if not options:
            return None
        m = options[rng.randrange(len(options))]
        tt = m // 12 - 5
        bb = m % 12 - 5
        e = t.shape_move[idx * N_TURN + m] ^ par
        idx = e >> 1
        par = e & 1
        x = sliced(turned(x, tt, bb))
        sol.append((tt, bb))
    assert shape_mask(x) == t.shape_masks[0] and parity_bit(x) == 0 and par == 0   # verifier only
    phase1 = len(sol)

    # Phase 2: permutations inside cube shape.
    cs = corner_slots(x)
    es = edge_slots(x)
    search = Search(t)
    if not search.solve(perm_rank(cs), perm_rank(es), t.set_index[set_mask_of(es)], 40):
        return None
    offset = 0
    for m in search.path:
        o = m & 1
        tt = 3 * (m >> 3) + o - offset
        bb = 3 * ((m >> 1) & 3) + o - offset
        x = turned(x, tt, bb)
        if not is_legal(x):
            return None
        x = sliced(x)
        sol.append((tt, bb))
        offset = o
    STATS.setdefault("p1", []).append(phase1)
    STATS.setdefault("p2", []).append(len(search.path))
    STATS.setdefault("nodes", []).append(search.nodes)

    # Final turn back to the internal solved state.
    solved = solved_cells()
    fin = None
    for a in range(12):
        for b in range(12):
            if fin is None and turned(x, a, b) == solved:
                fin = (a, b)
    if fin is None:
        return None

    # The scramble is the inverse, read backwards. The app's solved state is
    # the internal one with the bottom layer turned by +1, hence the -1.
    seq = [(-fin[0], -fin[1] - 1)]
    for k in range(len(sol) - 1, -1, -1):
        seq.append((-sol[k][0], -sol[k][1]))
    # A (0,0) turn between two slices cancels both slices.
    i = 1
    while i < len(seq) - 1:
        if mod12(seq[i][0]) == 0 and mod12(seq[i][1]) == 0:
            seq[i - 1] = (seq[i - 1][0] + seq[i + 1][0], seq[i - 1][1] + seq[i + 1][1])
            del seq[i:i + 2]
            i = max(1, i - 1)
        else:
            i += 1
    tokens = []
    for i in range(len(seq)):
        a = norm(seq[i][0])
        b = norm(seq[i][1])
        last = i == len(seq) - 1
        if a == 0 and b == 0:
            if not last:
                tokens.append("/")
        else:
            tokens.append("(%d,%d)" % (a, b) + ("" if last else "/"))
    return tokens


# ------------------------------------------------------------- verification

# Port of Square1State (Square1MapView.swift): the model the app replays on.
APP_SOLVED = [0, 0, 1, 2, 2, 3, 4, 4, 5, 6, 6, 7,
              8, 9, 9, 10, 11, 11, 12, 13, 13, 14, 15, 15]


def app_replay(tokens):
    pieces = APP_SOLVED[:]
    for token in tokens:
        nums = [int(v) for v in token.strip("()/ ").split(",") if v.strip()]
        if len(nums) == 2:
            up, down = pieces[:12], pieces[12:]
            ts = ((-nums[0] % 12) + 12) % 12
            bs = ((-nums[1] % 12) + 12) % 12
            for i in range(12):
                pieces[i] = up[(ts + i) % 12]
                pieces[12 + i] = down[(bs + i) % 12]
        if token.endswith("/"):
            for i in range(6):
                pieces[6 + i], pieces[12 + i] = pieces[12 + i], pieces[6 + i]
    return pieces


SLICE_TOKEN = re.compile(r"^(?:\((-?\d+),(-?\d+)\))?/$")
LAST_TOKEN = re.compile(r"^\((-?\d+),(-?\d+)\)$")


def check_tokens(tokens):
    assert tokens, "empty scramble"
    for n, tk in enumerate(tokens):
        m = SLICE_TOKEN.match(tk)
        if m is None:
            assert n == len(tokens) - 1 and LAST_TOKEN.match(tk), "bad token %r" % tk
            m = LAST_TOKEN.match(tk)
        assert len(tk) <= 8, tk
        if m.group(1) is None:
            assert n == 0, "bare / after the first token"
        else:
            a, b = int(m.group(1)), int(m.group(2))
            assert -5 <= a <= 6 and -5 <= b <= 6 and (a, b) != (0, 0), tk


def cell_replay(tokens, start):
    """Replay on the cell model, asserting every slice is legal."""
    s = start
    for tk in tokens:
        m = SLICE_TOKEN.match(tk) or LAST_TOKEN.match(tk)
        if m.group(1) is not None:
            s = turned(s, int(m.group(1)), int(m.group(2)))
        if tk.endswith("/"):
            assert is_legal(s), "slice through a corner"
            s = sliced(s)
    return s


def main():
    count = int(sys.argv[1]) if len(sys.argv) > 1 else 200
    seed = int(sys.argv[2]) if len(sys.argv) > 2 else 2026
    t0 = time.time()
    t = Tables()
    print("tables built in %.1fs (pure Python)" % (time.time() - t0), flush=True)

    assert t.shape_count == 3678, t.shape_count
    assert 255 not in t.shape_dist, "unreachable (shape, parity) state"
    hist = lambda tab: [tab.count(d) for d in range(max(tab) + 1)]
    print("shape x parity: %d states, depth histogram %s" % (len(t.shape_dist), hist(t.shape_dist)))
    assert 255 not in t.dc and 255 not in t.de
    assert hist(t.dc) == [16, 256, 1424, 5152, 12416, 14592, 6464], hist(t.dc)
    assert hist(t.de) == [16, 256, 1424, 5152, 12416, 14592, 6464], hist(t.de)
    nib = [0] * 16
    for byte in t.dcs:
        nib[byte & 15] += 1
        nib[byte >> 4] += 1
    assert nib[:8] == [16, 512, 4240, 38560, 288320, 1134336, 1270144, 86272] and sum(nib[8:]) == 0, nib
    print("corner/edge perm depth %s; corner x edge-set depth %s" % (hist(t.dc), nib[:8]), flush=True)

    # The app's solved state in internal piece numbering, and the relabelling.
    solved = solved_cells()
    app_start = turned(solved, 0, 1)
    relabel = {}
    for i in range(24):
        relabel[app_start[i]] = APP_SOLVED[i]
    assert len(relabel) == 16 and [relabel[v] for v in app_start] == APP_SOLVED
    assert is_legal(app_start)

    rng = random.Random(seed)
    lengths = []
    times = []
    seen_shapes = set()
    for n in range(count):
        state, idx = random_state(t, rng)
        assert is_legal(state) and shape_mask(state) == t.shape_masks[idx]
        seen_shapes.add(idx)
        t1 = time.time()
        tokens = scramble(t, state, idx, rng)
        times.append(time.time() - t1)
        assert tokens is not None, "no scramble found"
        check_tokens(tokens)
        assert cell_replay(tokens, app_start) == state, "cell replay differs"
        assert app_replay(tokens) == [relabel[v] for v in state], "app replay differs"
        lengths.append(sum(1 for tk in tokens if tk.endswith("/")))
        if n < 5:
            print("%2d slices: %s" % (lengths[-1], " ".join(tokens)), flush=True)
    avg = lambda v: sum(v) / len(v)
    print("%d random states reproduced exactly (app model + cell model), %d distinct shapes" % (count, len(seen_shapes)))
    print("slices: avg %.2f min %d max %d  histogram %s" % (
        avg(lengths), min(lengths), max(lengths),
        {k: lengths.count(k) for k in sorted(set(lengths))}))
    print("phase 1 slices: avg %.2f max %d | phase 2 slices: avg %.2f max %d" % (
        avg(STATS["p1"]), max(STATS["p1"]), avg(STATS["p2"]), max(STATS["p2"])))
    nodes = sorted(STATS["nodes"])
    print("phase 2 nodes: avg %d median %d p95 %d max %d" % (
        avg(nodes), nodes[len(nodes) // 2], nodes[len(nodes) * 95 // 100], nodes[-1]))
    print("seconds per scramble (Python): avg %.3f max %.3f" % (avg(times), max(times)))
    print("OK")


if __name__ == "__main__":
    main()
