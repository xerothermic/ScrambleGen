# Watch-face complication

A WidgetKit extension (`ScrambleWidgetExtension`, watchOS 10.0+) embedded in the
watch app. Patrick's request: "add watch face plugin to be able to quickly open
the app. Customizable which scramble."

## Behaviour

- Families: `accessoryCircular`, `accessoryRectangular`, `accessoryCorner`,
  `accessoryInline`. Circular, rectangular and corner
  draw the puzzle with SwiftUI `Canvas` paths (`PuzzleArt`): an isometric
  three-face cube for 3x3 (rectangular title "3×3 Cube") and a top view of kite
  (corner) and edge pieces with coloured rims for Square-1. Colours come from
  `CubeFace.stickerColor`; in tinted/vibrant rendering the same pieces are drawn
  in greys (luminance differences) and the art is `widgetAccentable`. The **Timer** option (and the app's Timer card) draws a generic speed cube timer in the
  style of a Stackmat/Speed Stacks pad, no branding (`drawTimerColour`: dark bow-tie body,
  silver centre panel, LCD showing 0.00, two round yellow hand pads; tinted: body outline
  and digits accentable, pads 0.6, centre panel 0.32;
  inline uses `stopwatch.fill`). Inline can
  only show text and SF Symbols, so it keeps `cube.fill` /
  `square.split.diagonal` plus the name. Card colours still come from
  `Puzzle.cardColor`.
- Long-press the face, tap Edit, tap the complication, and pick **Puzzle**: 3x3
  or Square-1. The gallery also lists both as ready-made suggestions.
- Tapping it opens the app straight on that puzzle's page, or on the Timer card
  for the Timer option (`scramblegen://timer`).

## How it works

| Piece | Where |
|---|---|
| Widget, intent, timeline, views | `RubiksScramble/ScrambleWidget/ScrambleWidget.swift` |
| Extension Info.plist (`NSExtensionPointIdentifier = com.apple.widgetkit-extension`) | `RubiksScramble/ScrambleWidget/Info.plist` |
| Shared puzzle styling and deep-link format | `RubiksScramble/RubiksScramble Watch App/PuzzleStyle.swift` |
| `.onOpenURL` handler | `ContentView.swift` (`ContentView.body`) |

- **Options.** The intent parameter is `ComplicationTarget` (in `PuzzleStyle.swift`):
  the `Puzzle` cases plus `.timer`, which is not a `Puzzle`. Its `AppEnum`
  conformance and display titles live in `ScrambleWidget.swift`; raw values match
  `Puzzle`'s, so existing complications keep their choice. The widget target compiles the app's own `ScrambleGenerator.swift`
  (the `Puzzle` enum), `CubeState.swift`, `Square1Scrambler.swift` and
  `PuzzleStyle.swift`. `extension Puzzle: AppEnum` (in `ScrambleWidget.swift`) maps
  every case to a `DisplayRepresentation`, and `SelectPuzzleIntent`
  (`WidgetConfigurationIntent`) has `@Parameter var puzzle: Puzzle`. The options
  list is `ComplicationTarget.allCases`: **adding a Puzzle case needs a
  `ComplicationTarget` case, one line in `caseDisplayRepresentations`** (the
  compiler complains if missing) and a `PuzzleStyle.swift` entry.
- **Deep link.** The view sets `.widgetURL(puzzle.deepLink)`, i.e.
  `scramblegen://puzzle/3x3`, `scramblegen://puzzle/square1` or
  `scramblegen://timer`.
  `ContentView` handles it with `.onOpenURL`: parse with `ComplicationTarget(deepLink:)`,
  set the `puzzle` AppStorage value, clear About, and set `openPuzzle` (or
  `showTimer` for the Timer link) inside
  the usual spring animation, the same state change as tapping a wallet card.
  A custom scheme does not need registering for `widgetURL` (watchOS has no
  `CFBundleURLTypes`).
- **Timeline.** One static entry, `.never` refresh. No network, no new
  dependencies, no App Group (the intent value lives in the widget's own
  configuration, the app never reads it).

## Project / signing

- `project.pbxproj` is hand edited. New target `ScrambleWidgetExtension`
  (`com.apple.product-type.app-extension`), bundle id
  **`com.pcintaiwan.scramblegen.watch.widget`**, SDK watchos, deployment 10.0,
  `SKIP_INSTALL = YES`. The watch app depends on it and embeds it in
  `PlugIns/` via the "Embed Foundation Extensions" copy phase.
- Version matching: the extension has `MARKETING_VERSION` and
  `CURRENT_PROJECT_VERSION` build settings like the watch app. CI passes both
  on the `xcodebuild archive` command line, which overrides every target, so the
  extension always gets the same `CFBundleShortVersionString` and
  `CFBundleVersion` as the watch app (Apple rejects a mismatch). **Keep the
  project defaults equal when bumping the version by hand** (three targets now
  hold `MARKETING_VERSION`).
- Signing: same manual scheme as the other bundles. `ci/release.config` has a
  third `PROVISIONING_PROFILES` entry, profile name
  **`ScrambleGen Watch Widget App Store`**. The workflows' "Verify archive signing
  settings" step fails early when any app/appex has no entry.
- Secret: `PROVISIONING_PROFILE_WATCH_WIDGET_BASE64` (base64 of the single
  `.mobileprovision`; the other two profiles still come from the tar.gz in
  `APPLE_PROVISIONING_PROFILES`). `testflight.yml` and `release.yml` both
  require it and install it with the other profiles. **Until Patrick adds it,
  every TestFlight/release run fails at "Check required secrets"**, which is why
  commits on this branch carry `[skip ci]`.
- `ci/ExportOptions.plist` needs no per-bundle entry (the workflow fills
  `provisioningProfiles` from `PROVISIONING_PROFILES`); only its comment changed.

## Compile check (no signing, no upload)

`.github/workflows/compile-check.yml` (manual `workflow_dispatch`):

```sh
gh workflow run compile-check.yml --ref bob/watch-complication
```

It builds the `CubeScramble` scheme for `generic/platform=watchOS Simulator`
with `CODE_SIGNING_ALLOWED=NO`, then checks the `.appex` is embedded in the watch
app and has identical `CFBundleShortVersionString`/`CFBundleVersion`. It proves
the code compiles, not that signing works.

## Checklist for Patrick (Apple side, one time)

Only the account holder can do this. Do it before merging this PR.

1. Open https://developer.apple.com/account/resources/identifiers/list and click
   **+** (next to "Identifiers").
2. Choose **App IDs**, **Continue**, then **App**, **Continue**.
3. Description: `ScrambleGen Watch Widget`. Bundle ID: choose **Explicit** and
   enter `com.pcintaiwan.scramblegen.watch.widget`.
4. Capabilities: leave everything unticked (the complication needs none; no App
   Groups, no push). **Continue**, **Register**.
5. Open https://developer.apple.com/account/resources/profiles/list, click **+**.
6. Under *Distribution* choose **App Store Connect**, **Continue**.
7. App ID: pick `ScrambleGen Watch Widget (com.pcintaiwan.scramblegen.watch.widget)`,
   **Continue**.
8. Certificate: tick the existing **Apple Distribution** certificate, the same
   one whose `.p12` is in `APPLE_DIST_CERT_P12`. **Continue**.
9. Provisioning Profile Name: exactly `ScrambleGen Watch Widget App Store`.
   **Generate**, then **Download**.
10. On the Mac, base64 the downloaded file and copy it (adjust the file name to
    what was downloaded):

    ```sh
    base64 -i ~/Downloads/ScrambleGen_Watch_Widget_App_Store.mobileprovision | pbcopy
    ```

11. Go to https://github.com/xerothermic/ScrambleGen/settings/secrets/actions,
    **New repository secret**, name `PROVISIONING_PROFILE_WATCH_WIDGET_BASE64`,
    paste, **Add secret**.

Nothing else is needed on Apple's side: no App Store Connect change (the
extension ships inside the existing watch-only app record; it is not a separate
app), no new capability, no new certificate or API key. Profiles expire after a
year and when the Apple Distribution certificate is replaced, like the others
(edit the profile, tick the new certificate, download, redo steps 10 and 11).
After the secret exists, run TestFlight (`gh workflow run testflight.yml --ref
bob/watch-complication`) to confirm the signed archive and upload.

## Timer card notes (same change)

- Setup screen shows a dimmed tip: turn off Settings > Gestures > Wrist Flick for
  solving (Wrist Flick drops the app back to the clock mid-solve). Hidden while
  the timer runs.
- Always On: the countdown and run digits are driven by `TimelineView`; when
  `isLuminanceReduced` they use a 1 Hz `.periodic` schedule (whole seconds, no
  sub-second digits), otherwise `.animation`. Motion detection and the extended
  runtime session are unchanged.

## Editor labels (Timer row)

The gallery row text comes from `recommendations()`. Each entry now sets an explicit
`Text(verbatim:)` label per `ComplicationTarget` ("3×3 Cube", "Square-1", "Timer"), and
the intent declares `parameterSummary` (`\(\.$puzzle)`). A screenshot had shown
"Square-1" beside the Timer row; the old code derived it from `name`, which was already
"Timer", so a stale cached gallery from an earlier build is also possible (remove and
re-add the complication). Untested on a watch.
