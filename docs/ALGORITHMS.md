# Algorithms card (OLL / PLL practice)

Fifth card in the Wallet stack (3x3, Square-1, Timer, **Algorithms**, About). Purple, with a small last-layer top view (Sune) drawn by `AlgoArt.drawOLL`. Not a `Puzzle` case and has no complication or deep link (like Timer, `showAlgos` in `ContentView`).

## Files (watch app target only)
- `AlgoCases.json` (bundled resource): 81 cases, 57 OLL, 21 PLL, 3 edge-orientation steps (`E-line`, `E-L`, `E-dot`). Per case: `alg`, `pic` (OLL/edge, 21 chars of 0/1: 9 top stickers row-major back row first, then back, right, front, left sides) or `cp`/`ep` (PLL arrows, slot -> home slot; corner slots BL BR FR FL, edge slots B R F L), `setup`/`solve` (scramble from a solved cube and its solution), `aufs` (variants with their own scramble, solution and, for PLL, arrows), `two_look`, `inverseOf`, `inverseKind`.
- `AlgoData.swift`: model, JSON loading, sets (`AlgoSet`), Leitner store (`AlgoStore`), text helpers.
- `AlgoArt.swift`: Canvas drawing of case pictures (`AlgoCaseView`).
- `AlgoScreens.swift`: menu, Learn, Drill/Practice, Quiz, case list, filter, Progress.

## Modes
- **Drill**: next due case (Leitner), random AUF variant, scramble shown, Start, solve, stop by tap or slap (the Timer card's `StopDetector`, `TimerCard.format`), alg revealed, rate **Not yet** / **Know it**. Practice is the same flow over random cases of the set, rated **Slow** / **Good**.
- **Learn**: crown pages through the set; page = picture, name, alg, inverse link. Tap for a big scrollable alg.
- **Quiz**: picture -> pick one of four names, or name -> pick one of four pictures (random per question); updates Leitner like a rating.
- **Set**: All, OLL, PLL, 2-look OLL (3 edge steps + OLL 21-27), 2-look PLL (Aa, E, Ua, Ub, H, Z), Inverse pairs, Weak list (boxes 1-2 or last rating Not yet). Stored in `@AppStorage("algoFilter")`.
- **Progress**: known (box 4-5) per OLL/PLL, box histogram, due count, per-case best time, reset.

## Leitner and persistence
Boxes 1-5, intervals 0/1/2/4/8/16 days (`AlgoStore.intervals`). Good / Know it moves up one box (unseen goes to 2), Not yet / Slow goes to box 1. `bestMs` is the fastest time of a Good rating; `lastMs` is every time. `UserDefaults` key `algoProgress` (JSON, `[caseID: AlgoProgress]`), plus `algoFilter` and `algoInverseBonus`.

## Inverse relations
`inverseOf` is the case whose picture the inverse of this case's alg produces (PLL: exact up to AUF; OLL and edge steps: up to U turns, same kind preferred). `inverseKind` is `self` when that is the case itself, else `pair`. The sim shows Aa/Ab, Ua/Ub and Ga/Gb, Gc/Gd are inverse pairs; H, Z, E, F, T, V, Y, Ja, Jb, Na, Nb, Ra, Rb are self-inverse (order-2 permutations, so Ja and Jb are NOT each other's inverse). Many OLL relations are one-way (OLL 10 -> OLL 8 while OLL 8 -> OLL 5): "inverse" there means the picture the inverse alg produces. The **Inverse pairs** set holds only mutual pairs. Learn shows `Inverse: <case>` (tap to open it) or `Self-inverse`. Drill's **Inverse bonus** (menu toggle, default on) offers the paired case once ("Now its inverse") after a case is rated Good.

## Verifying the data
`python3 -I scripts/verify_algos.py` re-checks every case and AUF variant with the sticker simulator `scripts/cubesim.py` (F2L intact, setup + solve = solved cube, picture/arrows match, OLL picture-driven check, distinctness, inverse fields). `--write` recomputes the inverse fields. It cannot catch a valid alg filed under the wrong number or name: that needs a human check against a published table.

## Not done
No complication (needs an App Group; if added, compile `AlgoArt.swift` into the widget and give it tinted-rendering line art like `PuzzleArtDrawing`), no "full scramble" mode, no custom id subsets, no `alt` algs, no streaks.
