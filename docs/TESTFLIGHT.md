# Shipping to TestFlight

A GitHub Actions pipeline that archives an Apple app with distribution
signing and hands the build to App Store Connect. It is deliberately
repo-agnostic: everything project-specific lives in `ci/release.config`, so
the workflow itself is copied between repos unchanged.

```
xcodebuild archive        (Release, generic/platform=$PLATFORM, distribution-signed)
        ↓
xcodebuild -exportArchive (method: app-store-connect)  → .ipa kept as a CI artefact
        ↓
xcodebuild -exportArchive (destination: upload)        → App Store Connect
        ↓
Apple processes the build (5–15 min) → appears in TestFlight
```

Signing is **manual** for both archive and export: one persistent **Apple
Distribution** certificate (`APPLE_DIST_CERT_P12`) and one **App Store**
provisioning profile per bundle (`APPLE_PROVISIONING_PROFILES`), named in
`ci/release.config`. No development certificate is involved, and the archive
runs without `-allowProvisioningUpdates`, so CI cannot create certificates,
profiles or App IDs on the developer portal. If something is missing it
fails with a message naming the secret or profile, instead of quietly
minting a throwaway certificate the way automatic signing did (until the
account hit Apple's certificate cap). The API key is used only to upload.

| File | Role |
|---|---|
| [`.github/workflows/testflight.yml`](../.github/workflows/testflight.yml) | The pipeline. Identical in every repo. |
| [`ci/release.config`](../ci/release.config) | The only per-repo file: project, scheme, platform. |
| [`ci/ExportOptions.plist`](../ci/ExportOptions.plist) | Export options; `teamID` and `method` are rewritten at build time. |
| [`Tools/install-testflight-pipeline.sh`](../Tools/install-testflight-pipeline.sh) | Copies all of the above into another repo and detects its config. |

---

## One-time setup

### 1. Apple Developer Program

TestFlight requires a paid Apple Developer Program membership ($99/year). A
free personal team can sideload from Xcode but cannot upload builds.

### 2. Register the bundle ID

In [developer.apple.com → Identifiers](https://developer.apple.com/account/resources/identifiers/list),
register an App ID for every bundle in the archive (the app, and an
embedded watch app or extension). CI signs manually and never creates App
IDs, so this is required: the App Store profiles are created against them.

### 3. Create the App Store Connect app record

App Store Connect → **Apps** → **+** → **New App**. The **Platform** must
match `PLATFORM` in `ci/release.config`. There is no watchOS platform in
that dialog: Apple's "Add watchOS app information" help page says to pick
**iOS** for watch apps, including watch-only ones (they then need Apple
Watch screenshots only). The **Bundle ID** must match the archived
top-level target exactly (for a watch-only app, its container).

The upload fails with "no suitable application record was found" until this
exists.

### 4. Create an App Store Connect API key

App Store Connect → **Users and Access** → **Integrations** → **App Store
Connect API** → **+**. Give it the **App Manager** role.

Record three things:

- **Issuer ID** — shown above the key table.
- **Key ID** — the 10-character ID in the key's row.
- The **`AuthKey_XXXXXXXXXX.p8`** file — *downloadable exactly once*. Save it
  somewhere safe; if you lose it you have to revoke the key and make a new one.

One key works for every app in the team, so this is done once per account,
not once per repo.

### 5. Export the distribution certificate

On a Mac that already has an **Apple Distribution** certificate (Xcode →
Settings → Accounts → Manage Certificates → **+** → Apple Distribution if you
don't):

1. Keychain Access → **My Certificates**
2. Right-click *Apple Distribution: …* → **Export…** → `.p12`
3. Set a password — this becomes `APPLE_DIST_CERT_PASSWORD`
4. Base64-encode it for GitHub:

```sh
base64 -i dist.p12 | pbcopy
```

Export the **certificate row** (the one with a disclosure triangle hiding a
private key), not the bare certificate — the private key must be in the
`.p12` or codesign has nothing to sign with.

Find your Team ID with:

```sh
security find-identity -v -p codesigning | grep "Apple Distribution"
```

The 10-character alphanumeric in parentheses is the Team ID.

### 6. Add the repository secrets

Settings → Secrets and variables → Actions → **New repository secret**:

| Secret | Value |
|---|---|
| `APPLE_TEAM_ID` | 10-character Team ID, e.g. `A1B2C3D4E5` |
| `APPLE_DIST_CERT_P12` | base64 of the `.p12` from step 5 |
| `APPLE_DIST_CERT_PASSWORD` | password you set when exporting the `.p12` |
| `ASC_KEY_ID` | Key ID from step 4 |
| `ASC_ISSUER_ID` | Issuer ID from step 4 |
| `ASC_PRIVATE_KEY` | **entire contents** of the `.p8`, including the `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----` lines |
| `APPLE_PROVISIONING_PROFILES` | base64 of a `.tar.gz` of the App Store `.mobileprovision` files named in `PROVISIONING_PROFILES` (see below) |

No development certificate secret is needed; `APPLE_DEV_CERT_P12` /
`APPLE_DEV_CERT_PASSWORD`, if set from an earlier version of this pipeline,
are ignored and can be deleted.

> GitHub has **no account-level Actions secrets** for personal accounts, and
> organization secrets need an organization. So every repo gets its own copy
> of these — but the first six values are identical across all of them, so
> it's paste-once-per-repo, not set-up-again-per-repo. The profiles are the
> exception: they are per-app.

#### The App Store profiles (`APPLE_PROVISIONING_PROFILES`)

One profile per bundle in the archive — an embedded watch app needs its
own. On [Certificates, Identifiers & Profiles → Profiles](https://developer.apple.com/account/resources/profiles/list)
→ **+** → *Distribution* → **App Store Connect** → pick the App ID → tick the
**Apple Distribution** certificate whose `.p12` is in `APPLE_DIST_CERT_P12`
→ name it exactly as in `PROVISIONING_PROFILES` → **Generate** → **Download**.

```sh
tar czf profiles.tar.gz *.mobileprovision
base64 -i profiles.tar.gz | gh secret set APPLE_PROVISIONING_PROFILES --repo <owner>/<repo>
```

and in `ci/release.config`:

```sh
SIGNING_CERTIFICATE="Apple Distribution"
PROVISIONING_PROFILES="com.example.App=App Store Profile;com.example.App.watchkitapp=Watch App Store Profile"
```

The workflow's *Show and verify signing setup* step lists the identities and
profiles it installed (names and UUIDs only) and fails before archiving if a
named profile is missing, is not an App Store profile, is for another bundle
or team, has expired, or does not include the imported certificate.

Profiles are tied to the certificate. When the Apple Distribution
certificate is renewed (it lasts a year), export the new `.p12` into
`APPLE_DIST_CERT_P12`, edit each profile to tick the new certificate,
re-download, and refresh `APPLE_PROVISIONING_PROFILES`. Profiles also expire
after a year; same refresh. Adding a capability (App Groups, HealthKit, …)
to a target also means regenerating its profile.

Two optional **variables** (same page, *Variables* tab) tune the build:

| Variable | Default | Purpose |
|---|---|---|
| `XCODE_VERSION` | runner default | Pin Xcode, e.g. `26.0`, when the runner image drifts from what the project needs |
| `BUILD_NUMBER_OFFSET` | `100` | Floor for generated build numbers |

### 7. Share the scheme

`xcodebuild -scheme` can only see schemes marked **Shared**. The ones Xcode
autocreates live in `xcuserdata/`, which is per-developer and gitignored, so
CI never sees them.

Xcode → Product → Scheme → **Manage Schemes…** → tick **Shared**, then commit
`<project>.xcodeproj/xcshareddata/xcschemes/`. The workflow checks for this
and fails in seconds with the same instruction if it's missing.

---

## Running a release

**From the Actions tab** — *TestFlight* → **Run workflow**:

- **marketing_version** — blank reads `MARKETING_VERSION` from the project.
- **build_number** — blank uses `BUILD_NUMBER_OFFSET + <run number>`.
- **dry_run** — archives, signs and exports the `.ipa` as an artefact but
  skips the upload. Use this first: it proves the signing setup works without
  burning a build number in App Store Connect.

**By tag** — pushing a `v*` tag runs the same thing and takes the marketing
version from the tag:

```sh
git tag v0.2.0 && git push origin v0.2.0   # → uploads 0.2.0 (<offset + run>)
```

### Version and build numbers

- `MARKETING_VERSION` → `CFBundleShortVersionString`, the version testers see.
- `CURRENT_PROJECT_VERSION` → `CFBundleVersion`, the build number.

App Store Connect rejects a build whose `(version, build)` pair it has already
seen, so the build number must strictly increase within a marketing version.
The default `BUILD_NUMBER_OFFSET + GITHUB_RUN_NUMBER` guarantees that as long
as nobody uploads by hand from a Mac. If someone does and overtakes CI, raise
`BUILD_NUMBER_OFFSET` past the manual number.

`manageAppVersionAndBuildNumber` is `false` in `ci/ExportOptions.plist`
precisely so Xcode doesn't quietly substitute its own numbering.

### After the upload

1. The build shows as *Processing* in App Store Connect → TestFlight for
   5–15 minutes.
2. Export compliance is answered automatically if the project sets
   `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO`, which is correct for
   an app using no encryption beyond OS-provided HTTPS/keychain. Without it
   App Store Connect asks per build.
3. Add yourself to **Internal Testing** (up to 100 App Store Connect users, no
   review needed) and the build is installable immediately.
4. **External Testing** (up to 10,000 testers) needs a one-time Beta App
   Review per version.

For a watch-only app, testers install from the TestFlight app on the *iPhone
paired to the watch*; TestFlight then offers to push the watch app across. It
is still a standalone watch app — the paired phone is only the delivery
channel.

---

## Reusing this in another repo

```sh
Tools/install-testflight-pipeline.sh --check ~/src/OtherApp   # report only
Tools/install-testflight-pipeline.sh         ~/src/OtherApp   # install
```

It copies the workflow, `ci/ExportOptions.plist` and this document, then
writes `ci/release.config` by reading the target's `project.pbxproj` and
filesystem — no Xcode needed, so it runs on Linux too. Existing files are
skipped unless you pass `--force`, which is also how you pull in an improved
workflow later.

It detects the Xcode project or workspace, the shared scheme, the platform
(from `SDKROOT`), and whether the project expects a gitignored xcconfig for
`DEVELOPMENT_TEAM`. It then reports blockers it can see without building:
missing shared scheme, empty `AppIcon.appiconset`, placeholder bundle ID, and
a missing export-compliance key.

Re-run it after the workflow improves; `ci/release.config` is left alone
unless you ask for `--force`.

### `ci/release.config`

| Key | Meaning |
|---|---|
| `XCODE_PROJECT` | Path to the `.xcodeproj` or `.xcworkspace`, relative to the repo root. The workflow picks `-project` or `-workspace` from the extension. |
| `XCODE_SCHEME` | Scheme to archive. Must be Shared and committed. |
| `PLATFORM` | `watchOS` \| `iOS` \| `macOS` \| `visionOS` \| `tvOS`. Becomes `generic/platform=…`. |
| `TEAM_XCCONFIG` | Optional. Gitignored xcconfig the project references for `DEVELOPMENT_TEAM`; CI writes it from `APPLE_TEAM_ID` and deletes it afterwards. Empty to skip. |
| `EXPORT_METHOD` | Optional. `app-store-connect` (Xcode 15.3+) or `app-store` (older). |
| `SIGNING_CERTIFICATE` | Required. `Apple Distribution`. |
| `PROVISIONING_PROFILES` | Required. `<bundle-id>=<profile name>` pairs, `;`-separated, one per bundle in the archive. The installer proposes `<bundle-id> App Store` names. |

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `Missing repository secrets: …` | The preflight step; add the named secrets. |
| `<project> has no shared schemes` | Step 7 above. |
| `ci/release.config not found` | Run the installer, or write the file by hand from the table above. |
| `No signing certificate "Apple Distribution" found` | `.p12` had no private key, or the wrong certificate type was exported. Redo step 5 from **My Certificates**. |
| `errSecInternalComponent` during codesign | The keychain partition list didn't take. Almost always a wrong `APPLE_DIST_CERT_PASSWORD`. |
| `No suitable application record was found` | The App Store Connect app record (step 3) doesn't exist, or was created on the wrong platform. |
| `Authentication credentials are missing or invalid` | `ASC_PRIVATE_KEY` is missing its BEGIN/END lines, or Key ID and Issuer ID are swapped. |
| `The bundle version must be higher than the previously uploaded version` | Build number collision — raise `BUILD_NUMBER_OFFSET` or pass `build_number` explicitly. |
| `Invalid App Store Icon` / `Missing app icon` | The `AppIcon.appiconset` has no image. Add a 1024x1024 PNG — opaque, square, no alpha and no rounded corners — and name it in `Contents.json`. (GoWatch generates its placeholder with `python3 Tools/make_app_icon.py`.) |
| `Choose a certificate to revoke. Your account has reached the maximum number of certificates` | Left over from the old automatic-signing archive, which minted an *Apple Development: Created via API* certificate per run. The current workflow never signs automatically, so this can only appear if the archive step was changed back. On [developer.apple.com → Certificates](https://developer.apple.com/account/resources/certificates/list), revoke the *Created via API* development certificates (safe — their private keys died with the runners). Keep the Apple Distribution certificate the secret holds. |
| `No installed profile is named '…'` / `Profile '…' does not include the Apple Distribution certificate` | `APPLE_PROVISIONING_PROFILES` is stale or for the wrong certificate. Edit the profile on the portal, tick the current Apple Distribution certificate, re-download all profiles, rebuild the secret. |
| `Expected exactly one 'Apple Distribution: …' identity` | `APPLE_DIST_CERT_P12` has no private key, holds a different certificate type, or the certificate was revoked/expired. Redo step 5. |
| `… is an app/extension with no entry in PROVISIONING_PROFILES` | A new target (extension, watch app) joined the archive. Create its App Store profile and add a pair to `ci/release.config`. |
| `profile resolved to '', expected '…'` | The per-bundle profile indirection didn't resolve, e.g. a target computes `PRODUCT_BUNDLE_IDENTIFIER` unusually. Set `CODE_SIGN_STYLE = Manual` and `PROVISIONING_PROFILE_SPECIFIER` for Release on that target in the project instead. |
| `exportArchive: exportOptionsPlist error … method` | Xcode older than 15.3 doesn't know `app-store-connect`. Set `EXPORT_METHOD="app-store"` in `ci/release.config`, or pin a newer Xcode via `XCODE_VERSION`. |

To see what actually got signed, download the run's artefact — it contains the
`.ipa`, `DistributionSummary.plist` and `Packaging.log`.

---

## Known gaps

- **No test gate.** The workflow archives whatever is on the ref. Add a
  prerequisite job if releases should be blocked on a red suite.
- **App Store metadata** (screenshots, description, privacy answers) is only
  needed for App Store release, not TestFlight internal testing.
