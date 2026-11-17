#!/usr/bin/env python3
"""Check the Clock scrambler in ClockScrambler.swift.

`generate` mirrors the Swift generator line for line. Every scramble must match
the WCA / TNoodle token layout: UR DR DL UL U R D L ALL, y2, U R D L ALL, then
nothing after the last ALL move (no pin list). Dial values are
-5...6 written as magnitude + sign (5- ... 6+, zero as 0+). Also checks that
all 12 values and both signs actually occur.
"""
import random
import re

FRONT = ["UR", "DR", "DL", "UL", "U", "R", "D", "L", "ALL"]
BACK = ["U", "R", "D", "L", "ALL"]


def fmt(turn):
    return str(abs(turn)) + ("-" if turn < 0 else "+")


def generate(rng):
    tokens = [m + fmt(rng.randint(-5, 6)) for m in FRONT] + ["y2"]
    tokens += [m + fmt(rng.randint(-5, 6)) for m in BACK]
    return tokens


LAYOUT = re.compile(
    r"^" + r" ".join(m + r"(?:[0-5][+-]|6\+)" for m in FRONT) + r" y2 "
    + r" ".join(m + r"(?:[0-5][+-]|6\+)" for m in BACK) + r"$"
)


PINS = {"UL": [(0, 0)], "UR": [(0, 1)], "DL": [(1, 0)], "DR": [(1, 1)],
        "U": [(0, 0), (0, 1)], "D": [(1, 0), (1, 1)],
        "L": [(0, 0), (1, 0)], "R": [(0, 1), (1, 1)],
        "ALL": [(0, 0), (0, 1), (1, 0), (1, 1)]}


def simulate(tokens):
    """Mirror of ClockState.scrambled: 9 front-view hours (row-major)."""
    dial = [0] * 9
    back = False
    for t in tokens:
        if t == "y2":
            back = True
            continue
        m = re.match(r"^([A-Z]+)(\d)([+-])$", t)
        name, n, sign = m.group(1), int(m.group(2)), m.group(3)
        n = -n if sign == "-" else n
        hit = set()
        for r0, c0 in PINS[name]:
            for r in (r0, r0 + 1):
                for c in (c0, c0 + 1):
                    hit.add(r * 3 + (2 - c if back else c))
        for i in hit:
            dial[i] = (dial[i] + (-n if back else n)) % 12
    return dial


def check_simulation():
    assert simulate(["UR1+"]) == [0, 1, 1, 0, 1, 1, 0, 0, 0]
    assert simulate(["U2-"]) == [10] * 6 + [0] * 3
    assert simulate(["ALL3+"]) == [3] * 9
    # Back view: UL pin = back column 0 = front column 2; clockwise from the back.
    assert simulate(["y2", "UL1+"]) == [0, 11, 11, 0, 11, 11, 0, 0, 0]
    print("simulation OK")


def main():
    check_simulation()
    rng = random.Random(1)
    values = set()
    for _ in range(20000):
        s = " ".join(generate(rng))
        assert LAYOUT.match(s), s
        assert "0-" not in s and "6-" not in s, s
        toks = s.split()
        values.update(t.lstrip("URDLALy") for t in toks[:9] + toks[10:15])
        assert len(toks) == 15, s
    assert values == {f"{n}{sg}" for n in range(7) for sg in "+-"} - {"0-", "6-"}, sorted(values)
    print("OK:", " ".join(generate(random.Random(7))))


if __name__ == "__main__":
    main()
