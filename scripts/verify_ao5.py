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
print("ok")
