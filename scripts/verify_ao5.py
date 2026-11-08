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
        avg = (sum(mid) + 15) // 30 * 10   # nearest centisecond
    vals = [eff(s) for s in solves if eff(s) is not None]
    return dropped, avg, (min(vals) if vals else None)

def reference(solves):
    vals = [eff(s) for s in solves]
    if sum(v is None for v in vals) >= 2:
        avg = None
    else:
        fin = sorted(v for v in vals if v is not None)
        trimmed = fin[1:-1] if len(fin) == 5 else fin[1:]  # one DNF: drop it + fastest
        m = Fraction(sum(trimmed), 30)          # centiseconds
        avg = 10 * (int(m) + (1 if m - int(m) >= Fraction(1, 2) else 0))
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
assert compute([(1, "none"), (333, "none"), (333, "none"), (335, "none"), (9999, "none")])[1] == 330
assert compute([(0, "none"), (15, "none"), (15, "none"), (15, "none"), (50, "none")])[1] == 20

# --- crown mapper mirror (Ao5CrownMapper) ---
DEFAULT_UPR = UPR = 524.0                  # crown binding units per revolution (Ao5CrownMapper.unitsPerRev)
DPU = 150.0
TH = {'off': None, 'gentle': (50, 120, 260), 'normal': (25, 60, 130), 'custom': None}
def tier(v, base, accel, custom=(25, 60, 130)):
    th = custom if accel == 'custom' else TH[accel]
    if th is None: return base
    t = 1 if v < th[0] else 10 if v < th[1] else 100 if v < th[2] else 1000
    return max(base, t)

class Mapper:
    def __init__(s, base=1, accel='normal', spr=150, upr=DEFAULT_UPR, custom=(25, 60, 130)):
        s.base, s.up, s.spr, s.carry, s.speed, s.t, s.upr, s.custom = base, accel, spr, 0.0, 0.0, None, upr, custom
    def feed(s, delta, now):
        if delta == 0: return 0
        d = delta / max(1, s.upr) * s.spr
        if (d > 0 and s.carry < 0) or (d < 0 and s.carry > 0): s.carry = 0.0
        if s.t is not None and now - s.t <= 0.3:
            inst = abs(d) / max(now - s.t, 0.01)
            s.speed = inst if s.speed == 0 else s.speed * 0.5 + inst * 0.5
        else:
            s.speed = 0.0
        s.t = now
        d += s.carry
        whole = int(d + (-1e-9 if d < 0 else 1e-9))  # toward zero, absorbing float dust
        s.carry = d - whole
        return whole * tier(s.speed, max(1, s.base), s.up, s.custom)

m = Mapper(); tot = 0; t = 0.0
for _ in range(524):
    t += 0.5; tot += m.feed(1.0, t)
assert tot == 150, tot                       # slow full revolution (524 units) = 150 ms
m = Mapper(); tot = 0; t = 0.0
for _ in range(7080):                        # smallest measured delta 0.074, carried: 524 units
    t += 0.5; tot += m.feed(0.074, t)
assert tot == int(7080 * 0.074 / UPR * 150), tot
m = Mapper(); assert m.feed(UPR / DPU, 1) == 1 and m.feed(-UPR / DPU, 5) == -1
m = Mapper(); assert (m.feed(2.0, 1), m.feed(-2.0, 2), m.feed(-2.0, 3)) == (0, 0, -1)
m = Mapper(); m.feed(10.48, 1.00); assert m.feed(10.48, 1.02) == 3000
random.seed(9)
for _ in range(2000):   # slow one-direction turn: sum of ms == detents moved (+-1), no lost movement
    m = Mapper(); t = 0.0; units = 0.0; tot = 0
    for _ in range(200):
        t += 1.0; dlt = random.random() * 5.0
        units += dlt; tot += m.feed(dlt, t)
    assert abs(tot - units / UPR * DPU) < 1.0 + 1e-6
for n in (30, 100, 150, 1000):
    assert Mapper(spr=n).feed(UPR, 1) == n
    m = Mapper(spr=n); assert sum(m.feed(UPR / (8 * n), 10 + i) for i in range(8)) == 1
assert tier(40, 1, 'gentle') == 1 and tier(40, 1, 'normal') == 10 and tier(300, 1, 'gentle') == 1000
for u in (100, 524, 1500):                  # units per revolution setting
    assert Mapper(upr=u).feed(u, 1) == 150
c = (10, 20, 30)
assert [tier(v, 1, 'custom', c) for v in (5, 15, 25, 35)] == [1, 10, 100, 1000]
m = Mapper(accel='custom', custom=c); m.feed(10.48, 1.00); assert m.feed(10.48, 1.02) == 3000
# display + digit entry (mirrors AverageOfFive.format / millis(fromDigits:))
def fmt(ms):
    t = max(0, ms) // 10
    m, s, cs = t // 6000, t // 100 % 60, t % 100
    return f"{m}:{s:02d}.{cs:02d}" if m else f"{s}.{cs:02d}"
def digits(ds):
    v = int(ds[-6:] or 0); r = v // 100
    return min((r % 100 + r // 100 * 60) * 1000 + v % 100 * 10, 600_000)
assert [fmt(x) for x in (8420, 12345, 5, 62345, 600_000)] == ["8.42", "12.34", "0.00", "1:02.34", "10:00.00"]
assert all("." in fmt(x) and len(fmt(x).split(".")[1]) == 2 for x in range(0, 600_001, 137))
assert [digits(x) for x in ("5", "1234", "10234", "7599", "17599", "95999", "123456")] == [50, 12340, 62340, 75990, 135990, 599_990, 600_000]
# clamping (mirrors Ao5Dial.apply)
MAXMS = 10 * 60000   # 10:00.000
clamp = lambda v: min(max(v, 0), MAXMS)
assert clamp(-5) == 0 and clamp(MAXMS + 1000) == MAXMS and clamp(599_999) == 599_999
assert MAXMS == 600_000
# haptic detent decision (mirrors Ao5Haptic.clickIndex)
def click_index(ms, iv, h):
    iv = max(1, iv); i = ms // iv
    if i > h: return i
    if i < h and ms + iv // 4 < h * iv: return i
    return None
assert click_index(5, 10, 0) is None and click_index(10, 10, 0) == 1 and click_index(1000, 10, 0) == 100
assert click_index(9, 10, 1) is None and click_index(7, 10, 1) == 0 and click_index(110, 100, 0) == 1
print("ok")
