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


def main():
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
