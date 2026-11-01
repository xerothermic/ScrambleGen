#!/usr/bin/env python3
"""Re-verify the Algorithms card data (RubiksScramble Watch App/AlgoCases.json)
with the sticker simulator in cubesim.py.

Usage: python3 scripts/verify_algos.py [--write] [path/to/AlgoCases.json]

For all cases and every AUF variant it checks that
  - `setup` on a solved cube leaves F2L and centres solved,
  - `solve` on that setup gives exactly the solved cube,
  - the base setup reproduces the stored picture (`pic` for OLL and edge steps,
    `cp`/`ep` for PLL) and every variant keeps the OLL picture or its own
    stored PLL cp/ep,
  - OLL picture-driven: an orientation-only LL rebuilt from `pic`, run through
    `alg`, ends with all nine top stickers yellow,
  - `alg` equals `solve`, and all OLL (up to U turns) / PLL (up to AUF) are
    pairwise distinct; OLL 1-4 have no oriented edges, 21-27 have all four.
Inverse relations: `inverseOf` is the case whose picture the inverse of this
case's alg produces (PLL: up to AUF, exactly; OLL / edge steps: up to U turns,
same kind preferred), `inverseKind` is "self" when that is the case itself,
otherwise "pair". `--write` (re)computes both fields into the JSON.
It cannot catch a valid alg filed under the wrong case number or name; that
needs a human cross-check against a published table.
"""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cubesim import Cube, invert

DEFAULT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..',
                       'RubiksScramble', 'RubiksScramble Watch App', 'AlgoCases.json')

UP = (0, 1, 0)
LL = [(x, 1, z) for z in (-1, 0, 1) for x in (-1, 0, 1)]   # top view row-major (back row first)
SIDES = ([((x, 1, -1), (0, 0, -1)) for x in (-1, 0, 1)] +  # back, left->right
         [((1, 1, z), (1, 0, 0)) for z in (-1, 0, 1)] +    # right, back->front
         [((x, 1, 1), (0, 0, 1)) for x in (-1, 0, 1)] +    # front, left->right
         [((-1, 1, z), (-1, 0, 0)) for z in (-1, 0, 1)])   # left, back->front

def case_state(alg):
    return Cube().apply(invert(alg))

def f2l_intact(c):
    s = Cube().s
    return all(c.s[k] == v for k, v in s.items() if k[0][1] <= 0 and k[0] != (0, 0, 0)) or \
           all(c.s[k] == v for k, v in s.items() if k[0][1] <= 0)

def oll_bits(c):
    bits = ''.join('1' if c.s[(p, UP)] == 'U' else '0' for p in LL)
    bits += ''.join('1' if c.s[k] == 'U' else '0' for k in SIDES)
    return bits

def rebuild_from_bits(bits):
    """Orientation-only LL state with identity permutation from a 21-char string."""
    c = Cube()
    for i, p in enumerate(LL):
        yel_top = bits[i] == '1'
        if p[0] == 0 and p[2] == 0:
            continue
        if (p[0] == 0) or (p[2] == 0):       # edge: two stickers on the LL
            side = [k for k in SIDES if k[0] == p][0]
            sidebit = bits[9 + SIDES.index(side)] == '1'
            if not yel_top:                   # flipped: swap colours
                c.s[(p, UP)], c.s[side] = c.s[side], c.s[(p, UP)]
        else:                                  # corner: 3 stickers
            sx = [k for k in SIDES if k[0] == p and k[1][0] != 0][0]
            sz = [k for k in SIDES if k[0] == p and k[1][2] != 0][0]
            order = [(p, UP), sx, sz]
            n = [k[1] for k in order]
            det = (n[0][0]*(n[1][1]*n[2][2]-n[1][2]*n[2][1]) - n[0][1]*(n[1][0]*n[2][2]-n[1][2]*n[2][0])
                   + n[0][2]*(n[1][0]*n[2][1]-n[1][1]*n[2][0]))
            if det < 0: order = [order[0], order[2], order[1]]
            cols = [c.s[k] for k in order]
            # which sticker is yellow in the picture?
            yi = 0 if yel_top else (1 if bits[9 + SIDES.index(order[1])] == '1' else 2)
            new = [None]*3
            for j in range(3): new[(j + yi) % 3] = cols[j]
            for k, col in zip(order, new): c.s[k] = col
    return c

SLOT_C = [(-1, 1, -1), (1, 1, -1), (1, 1, 1), (-1, 1, 1)]   # BL BR FR FL
SLOT_E = [(0, 1, -1), (1, 1, 0), (0, 1, 1), (-1, 1, 0)]     # B R F L

def pll_perm(c):
    """For each slot: slot index its current piece belongs to (-1 impossible)."""
    solved = Cube()
    def pieces(slots):
        out = []
        for p in slots:
            out.append(frozenset(v for k, v in solved.s.items() if k[0] == p))
        return out
    res = []
    for slots in (SLOT_C, SLOT_E):
        home = pieces(slots)
        cur = [frozenset(v for k, v in c.s.items() if k[0] == p) for p in slots]
        res.append(''.join(str(home.index(x)) for x in cur))
    return res

def ll_only(c):
    s = Cube().s
    return all(c.s[k] == v for k, v in s.items() if k[0][1] <= 0)

TURNS = ('', 'U', 'U2', "U'")


def _state_key(c):
    return tuple(sorted(c.s.items()))


def inverse_map(cases):
    """id -> id of the case that the inverse of its alg looks like."""
    pll_states = {}
    oll_keys = {}
    for o in cases:
        inv = invert(o['alg'])
        if o['kind'] == 'pll':
            for a in TURNS:
                for b in TURNS:
                    pll_states.setdefault(_state_key(Cube().apply(f'{a} {inv} {b}')), []).append(o['id'])
        else:
            key = min(oll_bits(Cube().apply(' '.join(['U'] * a) + f' {inv} ' + ' '.join(['U'] * ((4 - a) % 4))))
                      for a in range(4))
            oll_keys.setdefault(key, []).append(o)
    out = {}
    for e in cases:
        if e['kind'] == 'pll':
            ids = pll_states.get(_state_key(Cube().apply(e['alg'])), [])
            out[e['id']] = ids[0] if ids else None
        else:
            key = min(oll_bits(Cube().apply(' '.join(['U'] * a) + ' ' + e['alg'] + ' ' + ' '.join(['U'] * ((4 - a) % 4))))
                      for a in range(4))
            found = oll_keys.get(key, [])
            found = [o for o in found if o['kind'] == e['kind']] or found
            out[e['id']] = found[0]['id'] if found else None
    return out


def main(path, write=False):
    cases = json.load(open(path))
    inv_map = inverse_map(cases)
    if write:
        for e in cases:
            e['inverseOf'] = inv_map[e['id']]
            e['inverseKind'] = 'self' if inv_map[e['id']] == e['id'] else 'pair'
        with open(path, 'w') as f:
            json.dump(cases, f, separators=(',', ':'))
    bad, solved, seen_ids, classes = [], Cube().s, set(), {}
    top = [(p, UP) for p in LL]
    counts = {'oll': 0, 'pll': 0, 'edge': 0}
    for e in cases:
        cid = e['id']
        if cid in seen_ids: bad.append(f'{cid}: duplicate id')
        seen_ids.add(cid)
        counts[e['kind']] += 1
        if e['alg'] != e['solve']: bad.append(f'{cid}: alg != solve')
        base = Cube().apply(e['setup'])
        if not ll_only(base): bad.append(f'{cid}: setup disturbs F2L')
        if base.copy().apply(e['solve']).s != solved: bad.append(f'{cid}: solve fails')
        if e['kind'] in ('oll', 'edge'):
            if oll_bits(base) != e['pic']: bad.append(f'{cid}: setup != pic')
            r = rebuild_from_bits(e['pic']).apply(e['alg'])
            if e['kind'] == 'oll' and not all(r.s[k] == 'U' for k in top):
                bad.append(f'{cid}: picture-driven OLL check failed')
        else:
            if pll_perm(base) != [e['cp'], e['ep']]: bad.append(f'{cid}: setup != cp/ep')
            if not all(base.s[k] == 'U' for k in top): bad.append(f'{cid}: top not oriented')
        if e['kind'] == 'oll':
            n = int(cid[3:]); b = e['pic']
            eo = sum(b[i] == '1' for i in (1, 3, 5, 7))
            if n <= 4 and eo != 0: bad.append(f'{cid}: expected 0 oriented edges')
            if 21 <= n <= 27 and eo != 4: bad.append(f'{cid}: expected 4 oriented edges')
            key = min(oll_bits(Cube().apply(' '.join(['U'] * a)).apply(invert(e['alg']))
                               .apply(' '.join(['U'] * ((4 - a) % 4)))) for a in range(4))
            if key in classes: bad.append(f'{cid}: same pattern as {classes[key]}')
            classes[key] = cid
        for v in e['aufs']:
            c = Cube().apply(v['setup'])
            tag = f"{cid} {v['pre']}|{v['post']}"
            if not ll_only(c): bad.append(f'{tag}: F2L disturbed')
            if c.copy().apply(v['solve']).s != solved: bad.append(f'{tag}: solve fails')
            if e['kind'] == 'pll':
                if pll_perm(c) != [v['cp'], v['ep']]: bad.append(f'{tag}: cp/ep mismatch')
            elif oll_bits(c) != e['pic']: bad.append(f'{tag}: picture changed')
    ids = {e['id']: e for e in cases}
    for e in cases:
        want = inv_map[e['id']]
        if want is None: bad.append(f"{e['id']}: inverse is not in the set")
        if e.get('inverseOf') != want: bad.append(f"{e['id']}: inverseOf {e.get('inverseOf')} != {want}")
        kind = 'self' if want == e['id'] else 'pair'
        if e.get('inverseKind') != kind: bad.append(f"{e['id']}: inverseKind {e.get('inverseKind')} != {kind}")
        if e['kind'] == 'pll' and want in ids and inv_map.get(want) != e['id']:
            bad.append(f"{e['id']}: PLL inverse is not mutual")
    if counts != {'oll': 57, 'pll': 21, 'edge': 3}: bad.append(f'unexpected counts {counts}')
    nv = sum(len(e['aufs']) for e in cases)
    print(f'{len(cases)} cases {counts}, {nv} AUF variants, {len(bad)} problems')
    for b in bad: print('  ', b)
    return 1 if bad else 0

if __name__ == '__main__':
    args = [a for a in sys.argv[1:] if a != '--write']
    sys.exit(main(args[0] if args else DEFAULT, '--write' in sys.argv))
