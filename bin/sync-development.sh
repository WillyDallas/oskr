#!/usr/bin/env bash
# shellcheck disable=SC1091
# SC1091: harness-lib.sh is sourced and not followed without -x
# Fast-forward the local base branch to its origin counterpart before read-only
# work (research, planning) reads the working tree. Prevents agents from
# investigating a stale base — the failure mode behind story-spark issue #447,
# where a researcher on a tree 5 commits behind origin wrongly concluded a
# just-merged model id was unregistered.
#
# The base branch is read from harness-config.json (.base_branch, default main),
# so this generalizes the original story-spark version (which hardcoded
# `development`).
#
# Usage (from inside a consumer repo with harness-config.json):
#   sync-development.sh [context-label]
#
# Fast-forward ONLY — never merges or rebases. If the local branch has diverged
# or the tree is dirty, it refuses and exits non-zero so the caller can inform
# the developer rather than silently proceed on a stale (or wrong) base.
#
# Exit codes:
#   0  Safe to proceed: in sync, fast-forwarded, or deliberately on a feature
#      branch (base-branch staleness reported as a note, not a blocker).
#   1  Stale and could NOT auto-sync (divergence, dirty tree, or fetch failed).
#      Caller MUST inform the developer before proceeding.
#
# All human-readable status goes to stderr; stdout is reserved for the single
# machine-readable status token (in-sync | fast-forwarded | offline-stale |
# diverged | dirty | on-feature-branch) so callers can branch on it.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/harness-lib.sh"

CONTEXT="${1:-sync}"

# Base branch from harness-config (resolved against CWD's consumer repo); default main.
BRANCH=$(harness_config_get '.base_branch' 2>/dev/null || echo "main")
[[ -n "$BRANCH" && "$BRANCH" != "null" ]] || BRANCH="main"

note() { echo "[sync:$CONTEXT] $*" >&2; }

current=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
if [[ -z "$current" ]]; then
  note "not in a git repository"
  echo "diverged"
  exit 1
fi

if ! git fetch origin "$BRANCH" --quiet 2>/dev/null; then
  note "could not fetch origin/$BRANCH (offline?). Working tree may be stale — verify before trusting findings."
  echo "offline-stale"
  exit 1
fi

if [[ "$current" != "$BRANCH" ]]; then
  behind=$(git rev-list --count "$current"..origin/"$BRANCH" 2>/dev/null || echo 0)
  if [[ "$behind" -gt 0 ]]; then
    note "on feature branch '$current', which is $behind commit(s) behind origin/$BRANCH. Proceeding on '$current' as-is (not a $BRANCH session)."
  else
    note "on feature branch '$current' (up to date with origin/$BRANCH). Proceeding."
  fi
  echo "on-feature-branch"
  exit 0
fi

behind=$(git rev-list --count HEAD..origin/"$BRANCH" 2>/dev/null || echo 0)
if [[ "$behind" -eq 0 ]]; then
  note "$BRANCH is up to date with origin/$BRANCH."
  echo "in-sync"
  exit 0
fi

ahead=$(git rev-list --count origin/"$BRANCH"..HEAD 2>/dev/null || echo 0)
if [[ "$ahead" -gt 0 ]]; then
  note "REFUSED — local $BRANCH has diverged ($ahead local commit(s) not on origin, $behind behind). Cannot fast-forward. Resolve manually before proceeding; findings would be based on a divergent base."
  echo "diverged"
  exit 1
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
  note "REFUSED — $BRANCH is $behind commit(s) behind origin but the tree has uncommitted changes. Cannot fast-forward without clobbering them. Commit or stash, then re-run."
  echo "dirty"
  exit 1
fi

if git merge --ff-only origin/"$BRANCH" --quiet 2>/dev/null; then
  note "fast-forwarded $behind commit(s) from origin/$BRANCH."
  echo "fast-forwarded"
  exit 0
fi

note "REFUSED — fast-forward of $behind commit(s) failed unexpectedly. Resolve manually before proceeding."
echo "diverged"
exit 1
