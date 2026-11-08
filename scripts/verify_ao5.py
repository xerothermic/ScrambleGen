#!/usr/bin/env python3
"""Mirror of (integer milliseconds) AverageOfFive.swift's compute() plus an independent brute-force
check (sort DNF as infinity, Fraction arithmetic). Run: python3 -I scripts/verify_ao5.py"""
import random
from fractions import Fraction

INF = float("inf")

def eff(s):
    c, p = s
    return None if p == "dnf" else c + (2000 if p == "plus2" else 0)

def compute(solves):  # mirrors the Swift
    ranked = sorted(range(5), key=lambda i: ((eff(solves[i]) if eff(solves[i]) is not None else INF), i))
    dropped = {ranked[0], ranked[4]}
    mid = [eff(solves[i]) for i in ranked[1:4]]
    dnfs = sum(1 for s in solves if s[1] == "dnf")
    if dnfs >= 2 or None in mid:
        avg = None
    else:
        avg = (2 * sum(mid) + 3) // 6
    vals = [eff(s) for s in solves if eff(s) is not None]
    return dropped, avg, (min(vals) if vals else None)

def reference(solves):
    vals = [eff(s) for s in solves]
    if sum(v is None for v in vals) >= 2:
        avg = None
    else:
        fin = sorted(v for v in vals if v is not None)
        trimmed = fin[1:-1] if len(fin) == 5 else fin[1:]  # one DNF: drop it + fastest
        m = Fraction(sum(trimmed), 3)
        avg = int(m) + (1 if m - int(m) >= Fraction(1, 2) else 0)
    fin = [v for v in vals if v is not None]
    return avg, (min(fin) if fin else None)

random.seed(5)
for _ in range(200000):
    solves = [(random.choice([random.randint(0, 400), random.randint(0, 200000)]),
               random.choice(["none"] * 6 + ["plus2", "dnf"])) for _ in range(5)]
    d, a, b = compute(solves)
    assert len(d) == 2
    assert (a, b) == reference(solves), solves
assert compute([(9000, "none")] * 5)[0] == {0, 4}
assert compute([(1, "none"), (333, "none"), (333, "none"), (335, "none"), (9999, "none")])[1] == 334

# --- crown mapper mirror (Ao5CrownMapper) ---
DPU = 150.0
TH = {'off': None, 'gentle': (50, 120, 260), 'normal': (25, 60, 130)}
def tier(v, base, accel):
    th = TH[accel]
    if th is None: return base
    t = 1 if v < th[0] else 10 if v < th[1] else 100 if v < th[2] else 1000
    return max(base, t)

class Mapper:
    def __init__(s, base=1, accel='normal', spr=150): s.base, s.up, s.spr, s.carry, s.speed, s.t = base, accel, spr, 0.0, 0.0, None
    def feed(s, delta, now):
        if delta == 0: return 0
        d = delta * s.spr
        if (d > 0 and s.carry < 0) or (d < 0 and s.carry > 0): s.carry = 0.0
        if s.t is not None and now - s.t <= 0.3:
            inst = abs(d) / max(now - s.t, 0.01)
            s.speed = inst if s.speed == 0 else s.speed * 0.5 + inst * 0.5
        else:
            s.speed = 0.0
        s.t = now
        d += s.carry
        whole = int(d)  # toward zero
        s.carry = d - whole
        return whole * tier(s.speed, max(1, s.base), s.up)

m = Mapper(); tot = 0; t = 0.0
for _ in range(1000):
    t += 0.5; tot += m.feed(0.001, t)
assert tot == 150, tot                       # slow full unit = 150 ms
m = Mapper(); assert m.feed(1 / DPU, 1) == 1 and m.feed(-1 / DPU, 5) == -1
m = Mapper(); assert (m.feed(0.004, 1), m.feed(-0.004, 2), m.feed(-0.004, 3)) == (0, 0, -1)
m = Mapper(); m.feed(0.02, 1.00); assert m.feed(0.02, 1.02) == 3000
random.seed(9)
for _ in range(2000):   # slow one-direction turn: sum of ms == detents moved (+-1), no lost movement
    m = Mapper(); t = 0.0; units = 0.0; tot = 0
    for _ in range(200):
        t += 1.0; dlt = random.random() * 0.01
        units += dlt; tot += m.feed(dlt, t)
    assert abs(tot - units * DPU) < 1.0 + 1e-6
for n in (30, 100, 150, 1000):
    assert Mapper(spr=n).feed(1.0, 1) == n
    m = Mapper(spr=n); assert sum(m.feed(1.0 / (8 * n), 10 + i) for i in range(8)) == 1
assert tier(40, 1, 'gentle') == 1 and tier(40, 1, 'normal') == 10 and tier(300, 1, 'gentle') == 1000
# clamping (mirrors Ao5Dial.apply)
MAXMS = 59 * 60000 + 59999
clamp = lambda v: min(max(v, 0), MAXMS)
assert clamp(-5) == 0 and clamp(MAXMS + 1000) == MAXMS
print("ok")
