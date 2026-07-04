#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"
source "$REPO_ROOT/bin/harness-lib.sh"   # blacksmith_workspace_dir / _blacksmith_die
source "$REPO_ROOT/bin/hjarne-lib.sh"    # units under test

WS=$(cd "$(mktemp -d)" && pwd)           # canonicalized so /tmp symlinks don't break ==
trap 'rm -rf "$WS"' EXIT
mkdir -p "$WS/.oskr"
bash "$REPO_ROOT/bin/hjarne-skeleton.sh" "$WS/hjarne"
export OSKR_WORKSPACE="$WS"
BRAIN="$WS/hjarne"

CONTENT=$'# Board Dispatcher\n\nThe dispatcher polls the board.'

OUT=$(hjarne_archive_raw '#70:board-dispatcher' "$CONTENT")
EXPECT=$(hjarne_raw_path '#70:board-dispatcher')
assert_eq "$EXPECT" "$OUT" "archive_raw echoes the raw_path"
test -f "$OUT" || { echo "FAIL: archive_raw did not write the file" >&2; exit 1; }
grep -qF 'The dispatcher polls the board.' "$OUT" || { echo "FAIL: content not written" >&2; exit 1; }

# subdir parents created via mkdir -p
OUT2=$(hjarne_archive_raw '#70:lit-review' "$CONTENT" research)
test -f "$OUT2" || { echo "FAIL: subdir archive not written" >&2; exit 1; }
case "$OUT2" in "$BRAIN/raw/research/"*) : ;; *) echo "FAIL: subdir not honored ($OUT2)" >&2; exit 1 ;; esac

echo "test_hjarne_archive_raw: PASS"
