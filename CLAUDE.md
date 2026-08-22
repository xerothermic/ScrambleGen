## User & account
- **Apple Developer Program subscription is active** — App Store Connect and TestFlight distribution are available; no $99/yr blocker.
- Primary test devices: Apple Watch Ultra 3 (paired to user's iPhone) and a standalone Apple Watch (user's son's — can't be wired to Xcode, so distribution path is **TestFlight**, not direct dev install).

## What this repo is
A standalone **watchOS 10+** app that generates 3x3 Rubik's cube scrambles and shows the resulting cube state as a 2D net. Runs independently of any iPhone companion (`WKRunsIndependentlyOfCompanionApp = YES`).

## Layout
- `RubiksScramble/` — Xcode project + Watch App target.
  - `RubiksScramble Watch App/CubeState.swift` — 54-facelet engine. **Do not change the U,D,F,B,L,R face ordering or the perm tables** without re-running `scripts/verify_cube.py`; they're geometrically generated and verified.
  - `RubiksScramble Watch App/ScrambleGenerator.swift` — WCA-notation scramble generation; never repeats the same face on consecutive moves.
  - `RubiksScramble Watch App/ContentView.swift` — main UI: scramble page + swipe-down cube net.
- `mockup/` — HTML/CSS mockup of the watch screens; `node mockup/shot.mjs` rerenders the PNG previews (uses Playwright + Chromium at `/opt/pw-browsers`).
- `scripts/verify_cube.py` — regenerates and validates the cube turn tables.

## Build & verify (this box is Linux; no Xcode/Swift here)
- Cube engine: `python3 scripts/verify_cube.py`.
- 20k-scramble Python stress test exists for ad-hoc runs (no consecutive faces, every state valid).
- UI mockup: `cd mockup && node shot.mjs` → `scramble.png`, `scramble-focused.png`, `cube.png`, `both.png`.
- Real builds and on-device testing happen in Xcode on a Mac, watchOS 10 simulator or device.

## Design conventions
- Cube colours (also in `CubeState.swift` `stickerColor`):
  - U white, D `#FFD500`, F `#30D158`, B `#0051BA`, L `#FF5800`, R `#CE2029` (fire-truck red).
- `AccentColor` = cube green `#30D158`, so the New Scramble button matches the orientation pill.
- Orientation pill text: **"White top · Green front"** (standard WCA scrambling orientation).
- Scramble formatting: pad every move to 2 chars, single-space joiner, exactly 5 moves per row with explicit `\n` — keeps row width fixed across watch sizes.

## watchOS focus gotcha (already burned us once)
The length pill captures the Digital Crown via `@FocusState`. Use `@FocusState<EnumField?>`, not `@FocusState<Bool>`: setting Bool `false` lets SwiftUI auto-restore focus to the only focusable view on the page, so dismiss gestures look like re-activations. Setting an enum `FocusState` to `nil` actually releases focus.

Gesture model — strictly one-direction, no toggles:
- Tap length pill → `focus = .length` (activate crown for length).
- Tap scramble notation → `focus = nil` (release).
- Tap New Scramble → `focus = nil` + regenerate.

## Distribution
- Bundle ID placeholder is `com.example.RubiksScramble`; user replaces with their own team's reverse-DNS ID before App Store Connect submission.
- App icon: starter at `RubiksScramble/RubiksScramble Watch App/Assets.xcassets/AppIcon.appiconset/icon.png`. Xcode strips the alpha during build, so the rendered PNG is fine as-is for upload.
- TestFlight pipeline: `.github/workflows/testflight.yml`, run from the Actions tab or by pushing a `v*` tag. Per-repo settings are in `ci/release.config`; account setup, the six required repository secrets and troubleshooting are in `docs/TESTFLIGHT.md`. **No secrets are configured yet**, so the workflow currently fails its preflight.
- The scheme is shared and committed under `RubiksScramble.xcodeproj/xcshareddata/xcschemes/`. Do not rely on Xcode's autocreated schemes — they live in `xcuserdata/` and CI never sees them.
