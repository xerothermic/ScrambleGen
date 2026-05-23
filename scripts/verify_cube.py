#!/usr/bin/env python3
"""Regenerate and verify the cube turn tables used by CubeState.swift.

Rebuilds the six clockwise quarter-turn permutation tables from a geometric
cubie model and checks them against standard identities:
  - each turn is a bijection
  - X^4 = identity for every face
  - X X' = identity
  - (R U R' U')^6 = identity (and ^1 != identity)
The printed tables must match the `perms` dictionary in CubeState.swift.
"""

faces = ['U', 'D', 'F', 'B', 'L', 'R']
base = {f: i * 9 for i, f in enumerate(faces)}


def pos_normal(face, r, c):
    if face == 'U': return (c - 1, 1, r - 1), (0, 1, 0)
    if face == 'D': return (c - 1, -1, 1 - r), (0, -1, 0)
    if face == 'F': return (c - 1, 1 - r, 1), (0, 0, 1)
    if face == 'B': return (1 - c, 1 - r, -1), (0, 0, -1)
    if face == 'L': return (-1, 1 - r, c - 1), (-1, 0, 0)
    if face == 'R': return (1, 1 - r, 1 - c), (1, 0, 0)


stickers = [None] * 54
lookup = {}
for f in faces:
    for r in range(3):
        for c in range(3):
            idx = base[f] + r * 3 + c
            p, n = pos_normal(f, r, c)
            stickers[idx] = (p, n)
            lookup[(p, n)] = idx


def U(v): x, y, z = v; return (-z, y, x)
def D(v): x, y, z = v; return (z, y, -x)
def R(v): x, y, z = v; return (x, z, -y)
def L(v): x, y, z = v; return (x, -z, y)
def F(v): x, y, z = v; return (y, -x, z)
def B(v): x, y, z = v; return (-y, x, z)


rot = {'U': U, 'D': D, 'R': R, 'L': L, 'F': F, 'B': B}
layer = {'U': lambda p: p[1] == 1, 'D': lambda p: p[1] == -1,
         'R': lambda p: p[0] == 1, 'L': lambda p: p[0] == -1,
         'F': lambda p: p[2] == 1, 'B': lambda p: p[2] == -1}


def make_perm(face):
    fn = rot[face]
    inl = layer[face]
    perm = list(range(54))
    for i, (p, n) in enumerate(stickers):
        if inl(p):
            perm[lookup[(fn(p), fn(n))]] = i
    return perm


perms = {f: make_perm(f) for f in faces}

SOLVED = [i // 9 for i in range(54)]


def rotate(s, p): return [s[p[i]] for i in range(54)]


def apply_move(s, mv):
    f = mv[0]
    t = {'': 1, "'": 3, '2': 2}[mv[1:]]
    for _ in range(t):
        s = rotate(s, perms[f])
    return s


def repeat_seq(seq, n):
    s = SOLVED[:]
    for _ in range(n):
        for mv in seq.split():
            s = apply_move(s, mv)
    return s


for f in faces:
    assert sorted(perms[f]) == list(range(54))
for f in faces:
    assert repeat_seq(f, 4) == SOLVED
for f in faces:
    assert repeat_seq(f + " " + f + "'", 1) == SOLVED
assert repeat_seq("R U R' U'", 6) == SOLVED
assert repeat_seq("R U R' U'", 1) != SOLVED
print("verified")
for f in faces:
    print(f, "=", perms[f])
