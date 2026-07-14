#!/usr/bin/env bash
# init_import_local (#103): relocating a local repo into the workspace is a MOVE
# that preserves uncommitted + unpushed state by construction, refuses an
# existing destination, and only accepts a repo ROOT (moving a subdirectory
# would strip it from its .git). Real git fixture repo, no shims.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"
LIB="$REPO_ROOT/bin/init-lib.sh"

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
imp() { bash -c "source '$LIB'; init_import_local \"\$@\"" _ "$@"; }

# Fixture: a repo with a commit, an unpushed branch, an uncommitted modification,
# and an untracked file — the exact state the AC says must survive.
SRC="$WORK/dev/myrepo"; mkdir -p "$SRC"
git -C "$SRC" init -q -b main
echo v1 > "$SRC/tracked.txt"
git -C "$SRC" add tracked.txt
git -C "$SRC" -c user.email=t@t -c user.name=t commit -qm init
git -C "$SRC" branch unpushed-work
echo v2-dirty > "$SRC/tracked.txt"      # uncommitted modification
echo scratch > "$SRC/untracked.txt"     # untracked file

DEST="$WORK/ws/projects/myrepo"
imp "$SRC" "$DEST" || { echo "FAIL: import of a clean fixture repo failed" >&2; exit 1; }

[[ ! -e "$SRC" ]]        || { echo "FAIL: source still exists — move, not copy" >&2; exit 1; }
[[ -d "$DEST/.git" ]]    || { echo "FAIL: .git did not travel" >&2; exit 1; }
assert_eq "v2-dirty" "$(cat "$DEST/tracked.txt")" "uncommitted modification survives" || exit 1
[[ -f "$DEST/untracked.txt" ]] || { echo "FAIL: untracked file lost" >&2; exit 1; }
git -C "$DEST" rev-parse --verify -q unpushed-work >/dev/null \
  || { echo "FAIL: unpushed branch lost" >&2; exit 1; }
[[ -n "$(git -C "$DEST" status --porcelain)" ]] \
  || { echo "FAIL: working-tree state was cleaned by the move" >&2; exit 1; }

# Refusal: existing destination — and the source is left untouched.
SRC2="$WORK/dev/another"; mkdir -p "$SRC2"
git -C "$SRC2" init -q -b main
assert_exit 1 imp "$SRC2" "$DEST" || exit 1
[[ -d "$SRC2/.git" ]] || { echo "FAIL: refused import still moved the source" >&2; exit 1; }

# Refusal: a subdirectory of a repo is not importable (its .git lives at the root).
mkdir -p "$SRC2/subdir"
assert_exit 1 imp "$SRC2/subdir" "$WORK/ws/projects/subdir" || exit 1

# Refusal: not a git repository at all.
PLAIN="$WORK/dev/plain"; mkdir -p "$PLAIN"
assert_exit 1 imp "$PLAIN" "$WORK/ws/projects/plain" || exit 1

echo "test_init_import_local: PASS"
