#!/usr/bin/env bash
#
# Install the TestFlight release pipeline into another Apple app repo.
#
#   Tools/install-testflight-pipeline.sh ~/src/OtherApp
#   Tools/install-testflight-pipeline.sh --check ~/src/OtherApp
#
# Copies the workflow, export options and docs, then writes ci/release.config
# by inspecting the target's Xcode project. Everything project-specific ends
# up in that config, so the workflow itself stays byte-identical across repos
# and can be re-copied whenever it improves.
#
# Runs on macOS or Linux; no Xcode required (detection reads the pbxproj and
# the filesystem, not xcodebuild).

set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

FORCE=0
CHECK_ONLY=0
TARGET=""

usage() {
    sed -n '3,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    echo "Options:"
    echo "  --force   Overwrite files that already exist in the target"
    echo "  --check   Report on the target repo without copying anything"
    exit "${1:-0}"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --force) FORCE=1 ;;
        --check) CHECK_ONLY=1 ;;
        -h|--help) usage 0 ;;
        -*) echo "Unknown option: $1" >&2; usage 1 ;;
        *) TARGET="$1" ;;
    esac
    shift
done

[ -n "$TARGET" ] || usage 1
[ -d "$TARGET" ] || { echo "Not a directory: $TARGET" >&2; exit 1; }
TARGET="$(cd "$TARGET" && pwd)"
[ "$TARGET" != "$SOURCE_ROOT" ] || { echo "Target is this repo; nothing to do." >&2; exit 1; }

# Collected by the checks below and printed as a to-do list at the end.
BLOCKERS=""
NOTES=""
blocker() { BLOCKERS="${BLOCKERS}  ✗ $1"$'\n'; }
note()    { NOTES="${NOTES}  · $1"$'\n'; }

# ---------------------------------------------------------------- detection

# Prefer a workspace, but not the project.xcworkspace that lives inside every
# .xcodeproj. Shallowest path wins when there are several candidates.
find_container() {
    local ext="$1"
    find "$TARGET" -name "*.$ext" -not -path '*/.git/*' -not -path '*.xcodeproj/*' \
        | awk -F/ '{print NF"\t"$0}' | sort -n | cut -f2-
}

XCODE_PROJECT_ABS="$(find_container xcworkspace | head -1)"
[ -n "$XCODE_PROJECT_ABS" ] || XCODE_PROJECT_ABS="$(find_container xcodeproj | head -1)"

if [ -z "$XCODE_PROJECT_ABS" ]; then
    echo "No .xcodeproj or .xcworkspace found under $TARGET" >&2
    exit 1
fi
XCODE_PROJECT="${XCODE_PROJECT_ABS#"$TARGET"/}"

candidates="$( { find_container xcworkspace; find_container xcodeproj; } | wc -l | tr -d ' ')"
if [ "$candidates" -gt 1 ]; then
    note "Several Xcode containers found; picked $XCODE_PROJECT. Edit ci/release.config if that's wrong."
fi

# Only shared schemes reach CI. Autocreated ones live in xcuserdata, which is
# per-developer and gitignored, so xcodebuild -scheme fails without these.
SCHEME_DIR=""
for dir in "$XCODE_PROJECT_ABS/xcshareddata/xcschemes" \
           "$(dirname "$XCODE_PROJECT_ABS")"/*.xcodeproj/xcshareddata/xcschemes; do
    if [ -d "$dir" ] && compgen -G "$dir/*.xcscheme" > /dev/null; then SCHEME_DIR="$dir"; break; fi
done

XCODE_SCHEME=""
if [ -n "$SCHEME_DIR" ]; then
    scheme_count=0
    for s in "$SCHEME_DIR"/*.xcscheme; do
        scheme_count=$((scheme_count + 1))
        [ -n "$XCODE_SCHEME" ] || XCODE_SCHEME="$(basename "$s" .xcscheme)"
    done
    [ "$scheme_count" -eq 1 ] || note "$scheme_count shared schemes; picked '$XCODE_SCHEME'."
else
    XCODE_SCHEME="CHANGE_ME"
    blocker "No shared scheme committed. In Xcode: Product → Scheme → Manage Schemes → tick 'Shared', then commit <project>.xcodeproj/xcshareddata/. Until then xcodebuild -scheme cannot find anything in CI."
fi

# Platform from the target's SDKROOT.
PBXPROJ="$(find "$TARGET" -name project.pbxproj -not -path '*/.git/*' | head -1)"
PLATFORM="iOS"
if [ -n "$PBXPROJ" ]; then
    case "$(grep -o 'SDKROOT = [a-z]*' "$PBXPROJ" | head -1)" in
        *watchos)   PLATFORM="watchOS" ;;
        *iphoneos)  PLATFORM="iOS" ;;
        *macosx)    PLATFORM="macOS" ;;
        *xros)      PLATFORM="visionOS" ;;
        *appletvos) PLATFORM="tvOS" ;;
        *) note "Could not read SDKROOT; defaulted PLATFORM to iOS." ;;
    esac
fi

# A baseConfigurationReference pointing at a file that isn't in the repo means
# the project expects a gitignored per-developer xcconfig, which CI must write.
TEAM_XCCONFIG=""
if [ -n "$PBXPROJ" ]; then
    while IFS= read -r name; do
        [ -n "$name" ] || continue
        if [ -z "$(find "$TARGET" -name "$name" -not -path '*/.git/*' | head -1)" ]; then
            TEAM_XCCONFIG="$name"
            note "Project references '$name', which isn't committed — CI will write it from APPLE_TEAM_ID."
            break
        fi
    done <<< "$(grep -o 'path = [^;]*\.xcconfig' "$PBXPROJ" | sed 's/path = //; s/"//g' | xargs -n1 basename 2>/dev/null | sort -u)"
fi

# ------------------------------------------------------------------- checks

while IFS= read -r iconset; do
    [ -n "$iconset" ] || continue
    compgen -G "$iconset/*.png" > /dev/null || compgen -G "$iconset/*.jpg" > /dev/null || \
        blocker "$(basename "$(dirname "$iconset")")/$(basename "$iconset") has no image. App Store Connect rejects builds without an app icon."
done <<< "$(find "$TARGET" -type d -name 'AppIcon.appiconset' -not -path '*/.git/*')"

if [ -n "$PBXPROJ" ]; then
    bundle_id="$(grep -o 'PRODUCT_BUNDLE_IDENTIFIER = [^;]*' "$PBXPROJ" | head -1 | sed 's/.*= //; s/"//g')"
    case "$bundle_id" in
        *com.example*|*com.yourcompany*)
            blocker "Bundle ID is still the placeholder '$bundle_id'. Change it to your own reverse-DNS ID and register it in App Store Connect." ;;
        "") : ;;
        *) note "Bundle ID: $bundle_id — the App Store Connect app record must use exactly this." ;;
    esac

    # SKIP_INSTALL keeps a product out of the archive's Products/Applications.
    # That is right for a watch app or extension embedded in a containing app,
    # and fatal for whatever the archive itself is meant to export.
    if awk '
        /buildSettings = \{/        { inblock = 1; bid = 0; skip = 0 }
        inblock && /PRODUCT_BUNDLE_IDENTIFIER/ { bid = 1 }
        inblock && /SKIP_INSTALL = YES/        { skip = 1 }
        inblock && /^[[:space:]]*\};/          { if (bid && skip) found = 1; inblock = 0 }
        END { exit found ? 0 : 1 }
    ' "$PBXPROJ"; then
        blocker "An app target sets SKIP_INSTALL = YES. Unless that target is embedded in a containing app, the archive will hold no exportable app and exportArchive fails with \"does not contain a single-bundle app\". Set SKIP_INSTALL = NO."
    fi

    grep -q 'ITSAppUsesNonExemptEncryption' "$PBXPROJ" || \
        note "No ITSAppUsesNonExemptEncryption in the project. Without it App Store Connect asks the export-compliance question on every build; set INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO if the app uses no non-exempt encryption."
fi

# -------------------------------------------------------------------- copy

copy_in() {
    local rel="$1" dest="$TARGET/$1"
    if [ -e "$dest" ] && [ "$FORCE" -eq 0 ]; then
        echo "  skip    $rel (exists; --force to overwrite)"
        return
    fi
    mkdir -p "$(dirname "$dest")"
    cp -p "$SOURCE_ROOT/$rel" "$dest"
    echo "  copied  $rel"
}

if [ "$CHECK_ONLY" -eq 1 ]; then
    echo "Checking $TARGET (no files written)"
else
    echo "Installing into $TARGET"
    copy_in .github/workflows/testflight.yml
    copy_in ci/ExportOptions.plist
    copy_in docs/TESTFLIGHT.md
    # Ship the installer too, so the target can seed the next repo and the
    # links in its copy of TESTFLIGHT.md resolve.
    copy_in Tools/install-testflight-pipeline.sh

    if [ -e "$TARGET/ci/release.config" ] && [ "$FORCE" -eq 0 ]; then
        echo "  skip    ci/release.config (exists; --force to overwrite)"
    else
        mkdir -p "$TARGET/ci"
        cat > "$TARGET/ci/release.config" <<CONFIG
# Release configuration for .github/workflows/testflight.yml
#
# Written by install-testflight-pipeline.sh from the project's own settings.
# The workflow is repo-agnostic; every project-specific value lives here.
# Sourced as a shell fragment, so keep it to plain KEY="value" lines.

# Path to the .xcodeproj or .xcworkspace, relative to the repo root.
XCODE_PROJECT="$XCODE_PROJECT"

# Scheme to archive. Must be marked "Shared" in Xcode and committed under
# <project>/xcshareddata/xcschemes/ — CI cannot see schemes in xcuserdata.
XCODE_SCHEME="$XCODE_SCHEME"

# Archive destination: watchOS | iOS | macOS | visionOS | tvOS
PLATFORM="$PLATFORM"

# Optional. Path to a gitignored xcconfig the project references for
# DEVELOPMENT_TEAM; CI writes it from the APPLE_TEAM_ID secret before
# building. Leave empty for projects that don't use one.
TEAM_XCCONFIG="$TEAM_XCCONFIG"

# Optional. Xcode 15.3+ wants "app-store-connect"; older Xcode wants
# "app-store". Defaults to app-store-connect.
EXPORT_METHOD="app-store-connect"
CONFIG
        echo "  wrote   ci/release.config"
    fi
fi

# ------------------------------------------------------------------ report

echo
echo "Detected:"
printf '  %-16s %s\n' project "$XCODE_PROJECT" scheme "$XCODE_SCHEME" \
                      platform "$PLATFORM" "team xcconfig" "${TEAM_XCCONFIG:-<none>}"

if [ -n "$BLOCKERS" ]; then
    echo
    echo "Blocking — the upload will fail until these are fixed:"
    printf '%s' "$BLOCKERS"
fi

if [ -n "$NOTES" ]; then
    echo
    echo "Notes:"
    printf '%s' "$NOTES"
fi

cat <<'NEXT'

Still to do by hand in the target repo (see its docs/TESTFLIGHT.md):
  · Create the App Store Connect app record on the right platform.
  · Add the six repository secrets: APPLE_TEAM_ID, APPLE_DIST_CERT_P12,
    APPLE_DIST_CERT_PASSWORD, ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY.
    GitHub has no account-level Actions secrets, so every repo needs its
    own copy — the same values work across all of them.
  · Run the workflow once with dry_run: true to prove signing works.
NEXT
