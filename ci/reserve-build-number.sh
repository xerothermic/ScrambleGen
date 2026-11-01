#!/usr/bin/env bash
# Reserve the next build number from ci/build-number and print it on stdout.
#
# The counter is one integer in the repo. Each build adds 1 and commits it back
# ("[skip ci]", pushed with GITHUB_TOKEN, which never triggers workflows) to the
# branch being built, or to main for tag builds. The push is fast-forward only,
# so two writers can never take the same number: the loser re-reads and retries.
# A missing file counts as 0. A failed build still consumes its number; gaps are
# fine to App Store Connect, reuse is not.
#
# Env: GITHUB_REF (required), RUNNER_TEMP (required), DRY_RUN=true to read the
# next number without committing. Progress goes to stderr.
set -euo pipefail

FILE=ci/build-number
case "$GITHUB_REF" in
  refs/heads/*) TARGET="${GITHUB_REF#refs/heads/}" ;;
  *)            TARGET=main ;;   # tags: the counter lives on main
esac

git config user.name  "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

WT="$RUNNER_TEMP/build-number-worktree"
for attempt in 1 2 3 4 5; do
  git fetch --quiet origin "$TARGET" >&2
  git worktree remove --force "$WT" >&2 2>/dev/null || true
  git worktree add --quiet --detach "$WT" FETCH_HEAD >&2

  cur="$(tr -d '[:space:]' < "$WT/$FILE" 2>/dev/null || true)"
  cur="${cur:-0}"
  if ! [[ "$cur" =~ ^[0-9]+$ ]]; then
    echo "::error::$FILE on $TARGET does not hold a single integer: '$cur'" >&2
    exit 1
  fi
  next=$((cur + 1))

  if [ "${DRY_RUN:-false}" = "true" ]; then
    echo "Dry run: would use build number $next (counter on $TARGET is $cur)." >&2
    echo "$next"
    exit 0
  fi

  echo "$next" > "$WT/$FILE"
  git -C "$WT" add "$FILE"
  git -C "$WT" commit --quiet -m "Build number $next [skip ci]" >&2
  if git -C "$WT" push --quiet origin "HEAD:refs/heads/$TARGET" >&2; then
    echo "Reserved build number $next on $TARGET (attempt $attempt)." >&2
    echo "$next"
    exit 0
  fi
  echo "Push to $TARGET rejected (attempt $attempt); retrying." >&2
  sleep $((attempt * 3))
done
echo "::error::Could not push the build number bump to $TARGET after 5 attempts. If the branch is protected, allow github-actions[bot] to push or pass build_number by hand." >&2
exit 1
