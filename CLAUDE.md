## User & account
- **Apple Developer Program subscription is active** — App Store Connect and TestFlight distribution are available; no $99/yr blocker.
- Primary test devices: Apple Watch Ultra 3 (paired to user's iPhone) and a standalone Apple Watch (user's son's — can't be wired to Xcode, so distribution path is **TestFlight**, not direct dev install).

## What this repo is
A standalone **watchOS 10+** app that generates **3x3 and Square-1** scrambles and shows the resulting puzzle state as a map (3x3 net, or a WCA-style Square-1 top/bottom diagram). Runs independently of any iPhone companion (`WKRunsIndependentlyOfCompanionApp = YES`).

## Layout
- `RubiksScramble/` — Xcode project + Watch App target.
  - `RubiksScramble Watch App/CubeState.swift` — 54-facelet engine. **Do not change the U,D,F,B,L,R face ordering or the perm tables** without re-running `scripts/verify_cube.py`; they're geometrically generated and verified.
  - `RubiksScramble Watch App/ScrambleGenerator.swift` — WCA-notation 3x3 scramble generation (never repeats the same face on consecutive moves), plus the `Puzzle` enum (3x3 / Square-1) that maps each puzzle to its generator, length range and label.
  - `RubiksScramble Watch App/Square1Scrambler.swift` — random-move Square-1 scrambles, `(x,y)/` tokens, x/y in −5…6. Tracks layer shape so every turn leaves both layers sliceable. Model and sign convention follow csTimer's random-move generator; from solved, `(1,0)` and `(0,-1)` are legal but `(-1,0)` / `(0,1)` are not — any change must keep that. Re-run `scripts/verify_square1.py` after touching it (mirrors the Swift and replays every scramble on an independent boundary model).
  - `RubiksScramble Watch App/ContentView.swift` — main UI. Root is a horizontal `.page` TabView: swipe left/right between the 3x3 and Square-1 pages (selection persisted via `@AppStorage("puzzle")`; no switcher buttons — the page title, `Puzzle.name`, says which puzzle you're on). Each puzzle keeps its own scramble (`moves: [Puzzle: [String]]`) and length. Each puzzle page nests a `.verticalPage` TabView: scramble, then swipe down for its map (`CubeMapView` for 3x3, `Square1MapView` for Square-1).
  - `RubiksScramble Watch App/Square1MapView.swift` — `Square1State` (piece-level state in TNoodle's exact cell model: same turn/slice code, plus the middle-layer flip) and a Canvas port of TNoodle's `drawScramble`, so the map matches WCA scramble-sheet images: top face, middle-layer bar (one bar when solved, split red/orange when flipped), bottom face. Uses the WCA Square-1 colour scheme — **yellow top, red front** (L blue, B orange, R green, D white) — which differs from the 3x3 net's white-top/green-front.
- `mockup/` — HTML/CSS mockup of the watch screens; `node mockup/shot.mjs` rerenders the PNG previews (uses Playwright + Chromium at `/opt/pw-browsers`).
- `scripts/verify_cube.py` — regenerates and validates the cube turn tables.
- `scripts/verify_square1.py` — validates the Square-1 scrambler.

## Build & verify (this box is Linux; no Xcode/Swift here)
- Cube engine: `python3 scripts/verify_cube.py`.
- Square-1: `python3 scripts/verify_square1.py`.
- 20k-scramble Python stress test exists for ad-hoc runs (no consecutive faces, every state valid).
- UI mockup: `cd mockup && node shot.mjs` → `scramble.png`, `scramble-focused.png`, `cube.png`, `both.png`.
- Real builds and on-device testing happen in Xcode on a Mac, watchOS 10 simulator or device — or push to this branch: the TestFlight workflow compiles and ships it.

## Design conventions
- Cube colours (also in `CubeState.swift` `stickerColor`):
  - U white, D `#FFD500`, F `#30D158`, B `#0051BA`, L `#FF5800`, R `#CE2029` (fire-truck red).
- `AccentColor` = cube green `#30D158`, so the New Scramble button matches the orientation pill.
- Orientation pill text: **"White top · Green front"** (standard WCA scrambling orientation) for 3x3; for Square-1 it reads **"(top, bottom) · / = slice"** as a notation key.
- Scramble formatting: every move padded to its puzzle's widest token, single-space joiner, explicit `\n` rows — 3x3: 2-char columns, 5 per row, 19pt; Square-1: each number right-aligned in a 2-char column (`( 1, 0)/`, display only — stored moves stay unpadded), 8-char tokens, 2 per row, 16pt, rows left-aligned. Keeps row width fixed across watch sizes.
- Length per puzzle: 3x3 counts face turns (default 20, 1–50, label "Length"); Square-1 counts slices (default 15, 1–30, label "Slices").

## watchOS focus gotcha (already burned us once)
The length pill captures the Digital Crown via `@FocusState`. Use `@FocusState<EnumField?>`, not `@FocusState<Bool>`: setting Bool `false` lets SwiftUI auto-restore focus to the only focusable view on the page, so dismiss gestures look like re-activations. Setting an enum `FocusState` to `nil` actually releases focus.

Gesture model — strictly one-direction, no toggles:
- Tap length pill → `focus = .length` (activate crown for length).
- Tap scramble notation → `focus = nil` (release).
- Tap New Scramble → `focus = nil` + regenerate.

## Distribution (TestFlight via CI, ported from xerothermic/GoWatch)
- **Ships as "CubeScramble"** — "Rubik's" is a live trademark, so display names and the App Store Connect record avoid it.
- **Watch-only (no iPhone app)**: the watch target sets `WKWatchOnly = YES` and has no `WKCompanionAppBundleIdentifier`. Xcode has no App Store distribution method for a bare watchOS archive, so the `CubeScramble` target is a code-less **watch-only container** (`productType = com.apple.product-type.application.watchapp2-container`, iOS SDK, no sources, no icon) that embeds the watch app under `Watch/` — the same shape Xcode's "Watch App" template generates. Watch target keeps `SKIP_INSTALL = YES` (correct ONLY because it's embedded in the container). No iPhone UI exists, so App Store Connect needs Apple Watch screenshots only (avoids the 4.2 thin-iPhone-app risk).
- Bundle IDs: container `com.pcintaiwan.scramblegen` (parent — this is what the ASC app record binds to; the record's platform is iOS, Apple has no watchOS record type), watch `com.pcintaiwan.scramblegen.watch`.
- Privacy manifest: `RubiksScramble Watch App/PrivacyInfo.xcprivacy` declares UserDefaults reason `CA92.1` for `@AppStorage("puzzle")`. Update it if new required-reason APIs are used.
- CI: `.github/workflows/testflight.yml` (repo-agnostic; per-repo values in `ci/release.config`). Archives shared scheme `CubeScramble` (the container; the scheme runs the watch app) for `PLATFORM=iOS` on a `macos-26` runner and uploads to App Store Connect.
- **Seven** GitHub Actions secrets required, not six: `APPLE_TEAM_ID`, `APPLE_DIST_CERT_P12`, `APPLE_DIST_CERT_PASSWORD`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY`, plus `APPLE_PROVISIONING_PROFILES` (base64 tar.gz of the App Store `.mobileprovision` files — per-app, this repo needs its OWN profiles, named exactly "ScrambleGen App Store" / "ScrambleGen Watch App Store" to match `PROVISIONING_PROFILES` in the config). Two more are optional but strongly recommended: `APPLE_DEV_CERT_P12`/`APPLE_DEV_CERT_PASSWORD` — without a persistent development identity, every run mints a throwaway "Apple Development: Created via API" cert until the account hits Apple's certificate cap (details in `docs/TESTFLIGHT.md`).
- Named profiles + `Apple Distribution` cert are deliberate: cloud signing fails with a Developer-role ASC key ("Cloud signing permission error").
- App icons: 1024 RGB (no alpha) PNGs already in both targets' `AppIcon.appiconset` — an empty icon set passes the build and fails Apple validation ~20 min later.
