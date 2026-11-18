#!/usr/bin/env python3
"""Reference implementation + verifier for the 3x3 random-state scrambler
(RandomState333.swift).  Run: python3 -I scripts/verify_333_scramble.py [N]

Clean-room Kociemba two-phase algorithm, written from the published
description (H. Kociemba, "Cube Explorer" / two-phase algorithm): coordinate
representation (twist, flip, UD-slice, corner perm, UD-edge perm, slice perm),
move tables, pruning tables, IDA* in two phases, random state with the parity
constraint, scramble = inverse of the solution.  No TNoodle / min2phase code.
The Swift file mirrors this one structure-for-structure.

Checks performed:
  * cubie move tables reproduce CubeState.swift's 54-facelet turn tables
    (parsed straight out of the Swift source) for all 6 faces
  * move identities (X^4 = I, (RUR'U')^6 = I, R U has order 105)
  * N random states (default 300): scramble applied to a solved cube with the
    Swift facelet engine's tables equals the intended random state
  * validity invariants, scramble length distribution, per-solve timing
  * uniformity sanity: corner-twist / edge-flip sums, parity coupling
Needs numpy (table building only)."""
import os, random, re, sys, time
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
SWIFT_CUBE = os.path.join(HERE, "..", "RubiksScramble", "RubiksScramble Watch App", "CubeState.swift")

# ---------------------------------------------------------------- cubie model
CORNERS = ["URF", "UFL", "ULB", "UBR", "DFR", "DLF", "DBL", "DRB"]
EDGES = ["UR", "UF", "UL", "UB", "DR", "DF", "DL", "DB", "FR", "FL", "BL", "BR"]
CI = {n: i for i, n in enumerate(CORNERS)}
EI = {n: i for i, n in enumerate(EDGES)}


def _mv(cp, co, ep, eo):
    return ([CI[x] for x in cp.split()], co, [EI[x] for x in ep.split()], eo)

_Z8, _Z12 = [0] * 8, [0] * 12
BASE_MOVES = {  # clockwise quarter turn of each face; faces ordered U R F D L B
    "U": _mv("UBR URF UFL ULB DFR DLF DBL DRB", _Z8, "UB UR UF UL DR DF DL DB FR FL BL BR", _Z12),
    "R": _mv("DFR UFL ULB URF DRB DLF DBL UBR", [2, 0, 0, 1, 1, 0, 0, 2],
             "FR UF UL UB BR DF DL DB DR FL BL UR", _Z12),
    "F": _mv("UFL DLF ULB UBR URF DFR DBL DRB", [1, 2, 0, 0, 2, 1, 0, 0],
             "UR FL UL UB DR FR DL DB UF DF BL BR", [0, 1, 0, 0, 0, 1, 0, 0, 1, 1, 0, 0]),
    "D": _mv("URF UFL ULB UBR DLF DBL DRB DFR", _Z8, "UR UF UL UB DF DL DB DR FR FL BL BR", _Z12),
    "L": _mv("URF ULB DBL UBR DFR UFL DLF DRB", [0, 1, 2, 0, 0, 2, 1, 0],
             "UR UF BL UB DR DF FL DB FR UL DL BR", _Z12),
    "B": _mv("URF UFL UBR DRB DFR DLF ULB DBL", [0, 0, 1, 2, 0, 0, 2, 1],
             "UR UF UL BR DR DF DL BL FR FL UB DB", [0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 1, 1]),
}
FACES = "URFDLB"
SOLVED = (list(range(8)), [0] * 8, list(range(12)), [0] * 12)


def mult(a, m):
    """a followed by move m (m given as a cubie permutation+orientation)."""
    cp = [a[0][m[0][i]] for i in range(8)]
    co = [(a[1][m[0][i]] + m[1][i]) % 3 for i in range(8)]
    ep = [a[2][m[2][i]] for i in range(12)]
    eo = [(a[3][m[2][i]] + m[3][i]) % 2 for i in range(12)]
    return (cp, co, ep, eo)


MOVES = []  # 18 moves: index = 3*face + k, k = 0 (x), 1 (x2), 2 (x')
MOVE_NAMES = []
for f in FACES:
    q = BASE_MOVES[f]
    cur = SOLVED
    for k, suf in enumerate(["", "2", "'"]):
        cur = mult(cur, q) if k < 2 else None
        if k == 2:
            cur = mult(mult(mult(SOLVED, q), q), q)
        MOVES.append(cur)
        MOVE_NAMES.append(f + suf)
P2_MOVES = [m for m in range(18) if m // 3 in (0, 3) or m % 3 == 1]  # U D any, R L F B half turns


def inverse_move_index(m):
    return 3 * (m // 3) + (2 - m % 3)


# ------------------------------------------------------------------ coordinates
def perm_rank(p):
    r = 0
    n = len(p)
    for i in range(n):
        c = sum(1 for j in range(i + 1, n) if p[j] < p[i])
        r = r * (n - i) + c
    return r


def perm_unrank(r, n):
    digits = [0] * n
    for i in range(n - 1, -1, -1):
        base = n - i
        digits[i] = r % base
        r //= base
    avail = list(range(n))
    return [avail.pop(d) for d in digits]


C = [[0] * 5 for _ in range(13)]
for _n in range(13):
    C[_n][0] = 1
    for _k in range(1, 5):
        C[_n][_k] = C[_n - 1][_k - 1] + C[_n - 1][_k] if _n else 0


def slice_rank(ep):
    pos = [i for i in range(12) if ep[i] >= 8]
    return sum(C[p][k + 1] for k, p in enumerate(pos))


def slice_unrank(r):
    pos = []
    for k in (4, 3, 2, 1):
        p = 11
        while C[p][k] > r:
            p -= 1
        r -= C[p][k]
        pos.append(p)
    return sorted(pos)


def twist(co):
    t = 0
    for i in range(7):
        t = t * 3 + co[i]
    return t


def flip(eo):
    t = 0
    for i in range(11):
        t = t * 2 + eo[i]
    return t


N_TWIST, N_FLIP, N_SLICE, N_PERM8, N_SPERM = 2187, 2048, 495, 40320, 24
SLICE_SOLVED = 494


def cube_from_twist(t):
    co = [0] * 8
    s = 0
    for i in range(6, -1, -1):
        co[i] = t % 3
        t //= 3
        s += co[i]
    co[7] = (-s) % 3
    return (list(range(8)), co, list(range(12)), [0] * 12)


def cube_from_flip(t):
    eo = [0] * 12
    s = 0
    for i in range(10, -1, -1):
        eo[i] = t % 2
        t //= 2
        s += eo[i]
    eo[11] = s % 2
    return (list(range(8)), [0] * 8, list(range(12)), eo)


def cube_from_slice(r):
    pos = slice_unrank(r)
    ep = [0] * 12
    ns, nn = 8, 0
    for i in range(12):
        if i in pos:
            ep[i] = ns
            ns += 1
        else:
            ep[i] = nn
            nn += 1
    return (list(range(8)), [0] * 8, ep, [0] * 12)


# ------------------------------------------------------------------ tables
def build_tables():
    T = {}
    T["twist"] = np.array([[twist(mult(cube_from_twist(t), MOVES[m])[1]) for m in range(18)]
                           for t in range(N_TWIST)], dtype=np.int32)
    T["flip"] = np.array([[flip(mult(cube_from_flip(t), MOVES[m])[3]) for m in range(18)]
                          for t in range(N_FLIP)], dtype=np.int32)
    T["slice"] = np.array([[slice_rank(mult(cube_from_slice(t), MOVES[m])[2]) for m in range(18)]
                           for t in range(N_SLICE)], dtype=np.int32)
    cp_t = np.zeros((N_PERM8, len(P2_MOVES)), dtype=np.int32)
    ep_t = np.zeros((N_PERM8, len(P2_MOVES)), dtype=np.int32)
    for r in range(N_PERM8):
        p = perm_unrank(r, 8)
        ccube = (p, [0] * 8, list(range(12)), [0] * 12)
        ecube = (list(range(8)), [0] * 8, p + [8, 9, 10, 11], [0] * 12)
        for j, m in enumerate(P2_MOVES):
            cp_t[r, j] = perm_rank(mult(ccube, MOVES[m])[0])
            ep_t[r, j] = perm_rank(mult(ecube, MOVES[m])[2][:8])
    T["cp"], T["ep8"] = cp_t, ep_t
    sp_t = np.zeros((N_SPERM, len(P2_MOVES)), dtype=np.int32)
    for r in range(N_SPERM):
        p = perm_unrank(r, 4)
        cube = (list(range(8)), [0] * 8, list(range(8)) + [8 + x for x in p], [0] * 12)
        for j, m in enumerate(P2_MOVES):
            sp_t[r, j] = perm_rank([x - 8 for x in mult(cube, MOVES[m])[2][8:]])
    T["sperm"] = sp_t
    # pruning tables: BFS over the product of two coordinates
    T["pr_ts"] = prune(T["twist"], T["slice"], 0, SLICE_SOLVED)
    T["pr_fs"] = prune(T["flip"], T["slice"], 0, SLICE_SOLVED)
    T["pr_cs"] = prune(T["cp"], T["sperm"], 0, 0)
    T["pr_es"] = prune(T["ep8"], T["sperm"], 0, 0)
    return T


def prune(ma, mb, ga, gb):
    na, nb, nm = ma.shape[0], mb.shape[0], ma.shape[1]
    table = np.full(na * nb, 255, dtype=np.uint8)
    goal = ga * nb + gb
    table[goal] = 0
    frontier = np.array([goal], dtype=np.int64)
    d = 0
    while frontier.size:
        a, b = frontier // nb, frontier % nb
        nxt = []
        for m in range(nm):
            idx = ma[a, m].astype(np.int64) * nb + mb[b, m]
            idx = idx[table[idx] == 255]
            if idx.size:
                idx = np.unique(idx)
                table[idx] = d + 1
                nxt.append(idx)
        frontier = np.concatenate(nxt) if nxt else np.array([], dtype=np.int64)
        d += 1
    return table


# ------------------------------------------------------------------ solver
def solve(cube, T, max_total=21, time_limit=2.0):
    """Returns a list of move indices taking `cube` to solved."""
    mt_tw, mt_fl, mt_sl = T["twist"].tolist(), T["flip"].tolist(), T["slice"].tolist()
    mt_cp, mt_ep, mt_sp = T["cp"].tolist(), T["ep8"].tolist(), T["sperm"].tolist()
    pr_ts, pr_fs, pr_cs, pr_es = T["pr_ts"], T["pr_fs"], T["pr_cs"], T["pr_es"]
    # python lists index faster than numpy scalars
    pr_ts, pr_fs, pr_cs, pr_es = (x.tolist() for x in (pr_ts, pr_fs, pr_cs, pr_es))
    p2idx = {m: j for j, m in enumerate(P2_MOVES)}
    start = time.time()
    state = {"best": None, "max": max_total}
    path = []

    def phase2(cp, ep, sp, depth, last, out):
        h = max(pr_cs[cp * 24 + sp], pr_es[ep * 24 + sp])
        if h > depth:
            return False
        if depth == 0:
            return h == 0
        for m in P2_MOVES:
            f = m // 3
            if f == last or (last >= 0 and f == last - 3 and f < 3):
                continue
            j = p2idx[m]
            out.append(m)
            if phase2(mt_cp[cp][j], mt_ep[ep][j], mt_sp[sp][j], depth - 1, f, out):
                return True
            out.pop()
        return False

    def phase1(tw, fl, sl, depth, last):
        if depth == 0:
            if tw or fl or sl != SLICE_SOLVED:
                return False
            c = cube
            for m in path:
                c = mult(c, MOVES[m])
            cp, ep = perm_rank(c[0]), perm_rank(c[2][:8])
            sp = perm_rank([x - 8 for x in c[2][8:]])
            lim = state["max"] - len(path)
            if state["best"] is not None:
                lim = min(lim, len(state["best"]) - 1 - len(path))
            lim = min(lim, 18)
            for d2 in range(0, lim + 1):
                out = []
                if phase2(cp, ep, sp, d2, path[-1] // 3 if path else -1, out):
                    state["best"] = path + out
                    return True
            return False
        for m in range(18):
            f = m // 3
            if f == last or (last >= 0 and f == last - 3 and f < 3):
                continue
            ntw, nfl, nsl = mt_tw[tw][m], mt_fl[fl][m], mt_sl[sl][m]
            if max(pr_ts[ntw * N_SLICE + nsl], pr_fs[nfl * N_SLICE + nsl]) > depth - 1:
                continue
            path.append(m)
            if phase1(ntw, nfl, nsl, depth - 1, f):
                path.pop()
                return True
            path.pop()
        return False

    tw, fl, sl = twist(cube[1]), flip(cube[3]), slice_rank(cube[2])
    d1 = 0
    while True:
        if d1 > 12 or time.time() - start > time_limit:
            if state["best"] is not None:
                return state["best"]
            state["max"] += 2  # relax the target until something is found
            d1 = 0
            start = time.time()
        phase1(tw, fl, sl, d1, -1)
        if state["best"] is not None and len(state["best"]) <= state["max"]:
            return state["best"]
        d1 += 1


def scramble_from_solution(sol):
    return [MOVE_NAMES[inverse_move_index(m)] for m in reversed(sol)]


# ------------------------------------------------------------------ random state
def parity(p):
    return sum(1 for i in range(len(p)) for j in range(i + 1, len(p)) if p[i] > p[j]) % 2


def random_state(rng):
    cp = list(range(8)); rng.shuffle(cp)
    ep = list(range(12)); rng.shuffle(ep)
    if parity(cp) != parity(ep):
        ep[0], ep[1] = ep[1], ep[0]
    co = [rng.randrange(3) for _ in range(7)]
    co.append((-sum(co)) % 3)
    eo = [rng.randrange(2) for _ in range(11)]
    eo.append(sum(eo) % 2)
    return (cp, co, ep, eo)


# ------------------------------------------------------------------ verification model
def facelet_geometry():
    """Facelet index <-> (position, normal) exactly as verify_cube.py / CubeState."""
    def pos_normal(face, r, c):
        if face == 'U': return (c - 1, 1, r - 1), (0, 1, 0)
        if face == 'D': return (c - 1, -1, 1 - r), (0, -1, 0)
        if face == 'F': return (c - 1, 1 - r, 1), (0, 0, 1)
        if face == 'B': return (1 - c, 1 - r, -1), (0, 0, -1)
        if face == 'L': return (-1, 1 - r, c - 1), (-1, 0, 0)
        if face == 'R': return (1, 1 - r, 1 - c), (1, 0, 0)
    look = {}
    for fi, f in enumerate("UDFBLR"):
        for r in range(3):
            for c in range(3):
                look[pos_normal(f, r, c)] = fi * 9 + r * 3 + c
    return look


NORMAL = {"U": (0, 1, 0), "D": (0, -1, 0), "R": (1, 0, 0), "L": (-1, 0, 0), "F": (0, 0, 1), "B": (0, 0, -1)}


def slot_facelets(name):
    pos = tuple(sum(NORMAL[ch][a] for ch in name) for a in range(3))
    look = facelet_geometry()
    return [look[(pos, NORMAL[ch])] for ch in name]


def to_facelets(cube):
    cp, co, ep, eo = cube
    out = [0] * 54
    for f in range(6):
        out[f * 9 + 4] = f
    for s in range(8):
        sf, hf = slot_facelets(CORNERS[s]), slot_facelets(CORNERS[cp[s]])
        for j in range(3):
            out[sf[(j + co[s]) % 3]] = hf[j] // 9
    for s in range(12):
        sf, hf = slot_facelets(EDGES[s]), slot_facelets(EDGES[ep[s]])
        for j in range(2):
            out[sf[(j + eo[s]) % 2]] = hf[j] // 9
    return out


def parse_swift_perms():
    src = open(SWIFT_CUBE).read()
    perms = {}
    for f, body in re.findall(r'"([UDFBLR])": \[([0-9, ]+)\]', src):
        perms[f] = [int(x) for x in body.split(",")]
    assert len(perms) == 6
    return perms


def facelet_apply(fl, perms, move):
    n = 1 if len(move) == 1 else (2 if move[1] == "2" else 3)
    for _ in range(n):
        fl = [fl[i] for i in perms[move[0]]]
    return fl


def is_solvable(cube):
    cp, co, ep, eo = cube
    return (sorted(cp) == list(range(8)) and sorted(ep) == list(range(12))
            and sum(co) % 3 == 0 and sum(eo) % 2 == 0 and parity(cp) == parity(ep))


# ------------------------------------------------------------------ main
def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 300
    perms = parse_swift_perms()
    solved_f = list(range(54))
    solved_f = [i // 9 for i in range(54)]
    # 1. cubie tables == Swift facelet tables
    for f in FACES:
        for k, suf in enumerate(["", "2", "'"]):
            cube = MOVES[3 * FACES.index(f) + k]
            assert to_facelets(cube) == facelet_apply(solved_f, perms, f + suf), f + suf
    print("cubie move tables match CubeState.swift facelet tables (18 moves)")
    # 2. identities
    def run(seq, cube=SOLVED):
        for mv in seq.split():
            cube = mult(cube, MOVES[MOVE_NAMES.index(mv)])
        return cube
    assert run("R U R' U' " * 6) == SOLVED and run("R U R' U'") != SOLVED
    order, c = 1, run("R U")
    while c != SOLVED:
        c = run("R U", c); order += 1
    assert order == 105, order
    print("identities ok (RUR'U')^6 = I, order(RU) = 105")
    # 3. tables
    t0 = time.time()
    T = build_tables()
    print("tables built in %.1fs; phase-1 max depths %d/%d, phase-2 max depths %d/%d" % (
        time.time() - t0, T["pr_ts"].max(), T["pr_fs"].max(), T["pr_cs"].max(), T["pr_es"].max()))
    assert all(int(T[k].max()) < 255 for k in ("pr_ts", "pr_fs", "pr_cs", "pr_es")), "unreached states"
    # 4. random states
    rng = random.Random(333)
    lens, times = [], []
    twist_sum = flip_sum = 0
    for i in range(n):
        st = random_state(rng)
        assert is_solvable(st)
        t0 = time.time()
        sol = solve(st, T)
        times.append(time.time() - t0)
        scr = scramble_from_solution(sol)
        lens.append(len(scr))
        fl = solved_f
        for mv in scr:
            fl = facelet_apply(fl, perms, mv)
        assert fl == to_facelets(st), "scramble does not produce the target state"
        for a, b in zip(scr, scr[1:]):
            assert a[0] != b[0] or False, "same face twice in a row"
        assert len(scr) <= 21 + 3, len(scr)
    dist = {l: lens.count(l) for l in sorted(set(lens))}
    print("%d random states solved & verified on the Swift facelet engine" % n)
    print("scramble length distribution:", dist, "mean %.2f" % (sum(lens) / n))
    print("solve time: mean %.3fs, max %.3fs (python)" % (sum(times) / n, max(times)))
    # 5. uniformity sanity (cheap, no solving)
    m = 20000
    par = [0, 0]
    for _ in range(m):
        s = random_state(rng)
        par[parity(s[0])] += 1
        assert is_solvable(s)
    print("random_state: %d samples all solvable; corner parity split %s" % (m, par))
    assert abs(par[0] - par[1]) < 6 * (m ** 0.5) / 2
    print("OK")


if __name__ == "__main__":
    main()
