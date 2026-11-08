#!/usr/bin/env python3
"""Check the Square-1 scrambler in Square1Scrambler.swift.

`generate` mirrors the Swift generator line for line (the same `joined`
cell model). Every scramble it produces is then replayed on a separately
written model that tracks each layer as a set of piece-boundary positions,
and must stay legal there too: a turn must leave boundaries on both slice
lines (0 and 6) of both layers, and the pieces must always tile 12 cells
with 8 two-cell corners and 8 one-cell edges between them.

Also checks that the shape is cube shape after each of the first six slices.

Also checks the token format the watch UI relies on: one token per slice,
no token wider than 8 characters, and a (0,0) turn only as the opening
bare "/".
"""
import random
import re

TOKEN = re.compile(r"^(?:\((-?\d+),(-?\d+)\))?/$")


# --- line-for-line port of Square1Shape / Square1Scrambler ------------------

SOLVED = [True, False, False, True, False, False, True, False, False, True, False, False,
          False, True, False, False, True, False, False, True, False, False, True, False]


def turn(joined, top, bottom):
    up, down = joined[:12], joined[12:]
    cell = lambda layer, i, steps: layer[((i - steps) % 12 + 12) % 12]
    if cell(up, 5, top) or cell(up, 11, top) or cell(down, 5, bottom) or cell(down, 11, bottom):
        return False
    for i in range(12):
        joined[i] = cell(up, i, top)
        joined[12 + i] = cell(down, i, bottom)
    return True


def slice_(joined):
    for i in range(6):
        joined[6 + i], joined[12 + i] = joined[12 + i], joined[6 + i]


def is_cube(joined):
    for layer in (joined[:12], joined[12:]):
        starts = [i for i in range(12) if not layer[(i - 1) % 12]]
        widths = [((starts[(k + 1) % len(starts)] - s) % 12) or 12 for k, s in enumerate(starts)]
        if widths.count(2) != 4 or any(widths[k] == widths[(k + 1) % len(widths)]
                                       for k in range(len(widths))):
            return False
    return True


CUBE_SHAPE_SLICES = 6


def generate(slices, rng, shapes=None):
    joined = SOLVED[:]
    tokens = []
    while len(tokens) < max(0, slices):
        if len(tokens) < CUBE_SHAPE_SLICES:
            options = []
            for t in range(-5, 7):
                for b in range(-5, 7):
                    if (t or b or not tokens):
                        trial = joined[:]
                        if turn(trial, t, b):
                            slice_(trial)
                            if is_cube(trial):
                                options.append((t, b))
            top, bottom = rng.choice(options)
        else:
            top, bottom = rng.randint(-5, 6), rng.randint(-5, 6)
            if not (top or bottom):
                continue
            if not turn(joined[:], top, bottom):
                continue
        is_turn = top != 0 or bottom != 0
        assert turn(joined, top, bottom)
        slice_(joined)
        tokens.append(f"({top},{bottom})/" if is_turn else "/")
        if len(tokens) <= CUBE_SHAPE_SLICES:
            assert is_cube(joined), f"slice {len(tokens)} left cube shape: {tokens}"
    return tokens


# --- independent boundary model ----------------------------------------------

def boundaries(joined_layer):
    """Positions 0..11 where a piece starts (boundary before cell i)."""
    return {i for i in range(12) if not joined_layer[(i - 1) % 12]}


class BoundaryCube:
    def __init__(self):
        self.top = boundaries(SOLVED[:12])
        self.bottom = boundaries(SOLVED[12:])

    def turn(self, x, y):
        # Content moves from cell i - k to cell i, so boundaries shift by +k.
        top = {(b + x) % 12 for b in self.top}
        bottom = {(b + y) % 12 for b in self.bottom}
        assert {0, 6} <= top, f"top layer can't slice after ({x},{y}): {sorted(top)}"
        assert {0, 6} <= bottom, f"bottom layer can't slice after ({x},{y}): {sorted(bottom)}"
        self.top, self.bottom = top, bottom

    def slice(self):
        # Top cells 6..11 trade places with bottom cells 0..5, keeping order.
        top_keep = {b for b in self.top if b <= 6}
        bottom_keep = {b for b in self.bottom if b == 0 or b >= 6}
        moved_to_bottom = {b - 6 for b in self.top if b >= 6}
        moved_to_top = {(b + 6) % 12 for b in self.bottom if b <= 6}
        self.top = top_keep | moved_to_top
        self.bottom = bottom_keep | moved_to_bottom
        self.check_pieces()

    def check_pieces(self):
        corners = 0
        for layer in (self.top, self.bottom):
            starts = sorted(layer)
            widths = [(starts[(i + 1) % len(starts)] - s) % 12 or 12
                      for i, s in enumerate(starts)]
            assert sum(widths) == 12, widths
            assert set(widths) <= {1, 2}, f"piece wider than a corner: {widths}"
            corners += widths.count(2)
        assert corners == 8, f"{corners} corners"


def replay(tokens):
    cube = BoundaryCube()
    for i, tok in enumerate(tokens):
        m = TOKEN.match(tok)
        assert m, f"bad token {tok!r}"
        assert len(tok) <= 8, f"token wider than the UI column: {tok!r}"
        if m.group(1) is None:
            assert i == 0, "bare '/' only allowed as the opening move"
            x = y = 0
        else:
            x, y = int(m.group(1)), int(m.group(2))
            assert -5 <= x <= 6 and -5 <= y <= 6, tok
            assert (x, y) != (0, 0), "(0,0) must be written as a bare '/'"
        cube.turn(x, y)
        cube.slice()


rng = random.Random(1)
runs = 0
for slices in list(range(0, 31)) * 700:
    tokens = generate(slices, rng)
    assert len(tokens) == slices, (slices, len(tokens))
    replay(tokens)
    runs += 1

# first six slices stay in cube shape; later ones eventually leave it
left = 0
for _ in range(500):
    j = SOLVED[:]
    toks = generate(15, rng)
    for k, tok in enumerate(toks):
        m = TOKEN.match(tok)
        x, y = (int(m.group(1)), int(m.group(2))) if m.group(1) else (0, 0)
        assert turn(j, x, y); slice_(j)
        if k < 6:
            assert is_cube(j)
        elif not is_cube(j):
            left += 1
            break
assert left > 100, f"scrambles never leave cube shape after slice 6 ({left})"

sample = generate(15, random.Random(7))
print(f"verified {runs} scrambles (0-30 slices); sample: {' '.join(sample)}")
