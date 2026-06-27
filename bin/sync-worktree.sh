#!/usr/bin/env bash
# shellcheck disable=SC1091
# SC1091: harness-lib.sh is sourced and not followed without -x
# Merge the latest origin/<base-branch> into the current feature branch before
# implementation work begins. Companion to sync-development.sh with the
# opposite merge policy by design: the base branch must never grow local-only
# commits (FF-only), while a feature branch absorbs the base via a true merge.
# Closes the resume-mode gap where a branch created by an earlier dispatch
# keeps a stale base while the base branch moves on.
#
# The base branch is read from harness-config.json (.base_branch, default main),
# generalizing the original story-spark version (which hardcoded `development`).
#
# Usage (from inside a consumer repo with harness-config.json):
#   sync-worktree.sh [context-label]
#
# Never auto-resolves conflicts. On conflict the merge is aborted, the branch
# is left exactly as it was, and the script exits non-zero so the caller can
# surface the conflict to the developer.
#
# Exit codes:
#   0  Safe to proceed: branch already contains the base, or merge landed.
#   1  Could not sync (on the base branch itself, dirty tree, diverged local
#      base, fetch failed, or merge conflict). Caller MUST surface this to the
#      developer rather than silently proceed.
#
# All human-readable status goes to stderr; stdout is reserved for the single
# machine-readable status token (in-sync | merged | on-base | dirty |
# diverged | offline-stale | conflict) so callers can branch on it.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/harness-lib.sh"

CONTEXT="${1:-sync}"

# Base branch from harness-config (resolved against CWD's consumer repo); default main.
BASE=$(blacksmith_config_get '.base_branch' 2>/dev/null || echo "main")
[[ -n "$BASE" && "$BASE" != "null" ]] || BASE="main"

note() { echo "[sync-worktree:$CONTEXT] $*" >&2; }

current=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
if [[ -z "$current" || "$current" == "HEAD" ]]; then
  note "not on a branch (detached HEAD or not a git repository)"
  echo "diverged"
  exit 1
fi

if [[ "$current" == "$BASE" ]]; then
  note "on $BASE itself — use sync-development.sh for that."
  echo "on-base"
  exit 1
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
  note "REFUSED — uncommitted tracked changes on '$current'. Commit or stash them, then re-run."
  echo "dirty"
  exit 1
fi

if ! git fetch origin "$BASE" --quiet 2>/dev/null; then
  note "could not fetch origin/$BASE (offline?). Cannot guarantee a current base — verify before trusting the branch state."
  echo "offline-stale"
  exit 1
fi

# True divergence (local base both ahead of AND behind origin) is a repo-health
# stop signal. Local-only commits with nothing new on origin are normal
# (committed but not yet pushed) — merge the local ref in that case, since it
# contains everything origin has plus the unpushed work.
dev_ahead=$(git rev-list --count origin/"$BASE".."$BASE" 2>/dev/null || echo 0)
dev_behind=$(git rev-list --count "$BASE"..origin/"$BASE" 2>/dev/null || echo 0)
if [[ "$dev_ahead" -gt 0 && "$dev_behind" -gt 0 ]]; then
  note "REFUSED — local $BASE has truly diverged ($dev_ahead local-only commit(s), $dev_behind behind origin). Resolve that first; merging around it would hide the divergence."
  echo "diverged"
  exit 1
fi

if [[ "$dev_ahead" -gt 0 ]]; then
  MERGE_REF="$BASE"
else
  MERGE_REF="origin/$BASE"
  # Opportunistically fast-forward the local base ref without leaving this
  # branch. Refspec fetch is FF-only and refuses if the base is checked out in
  # another worktree — harmless either way.
  git fetch origin "$BASE:$BASE" --quiet 2>/dev/null || true
fi

behind=$(git rev-list --count HEAD.."$MERGE_REF" 2>/dev/null || echo 0)
if [[ "$behind" -eq 0 ]]; then
  note "'$current' already contains all of $MERGE_REF."
  echo "in-sync"
  exit 0
fi

if git merge --no-edit "$MERGE_REF" --quiet 2>/dev/null; then
  note "merged $behind commit(s) from $MERGE_REF into '$current'."
  echo "merged"
  exit 0
fi

git merge --abort 2>/dev/null
note "CONFLICT — merging $MERGE_REF into '$current' hit conflicts. Merge aborted, branch unchanged. Resolve manually (git merge $MERGE_REF) before continuing."
echo "conflict"
exit 1
