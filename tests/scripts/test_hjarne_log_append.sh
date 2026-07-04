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

LOG="$BRAIN/log.md"
grep -qF '# Log' "$LOG" || { echo "FAIL: skeleton log.md missing its heading" >&2; exit 1; }

# entry count keyed on a dated bullet (the skeleton's example bullet is undated → not counted)
count() { grep -cE '^- [0-9]{4}-[0-9]{2}-[0-9]{2} ' "$LOG" || true; }
[[ "$(count)" -eq 0 ]] || { echo "FAIL: expected 0 dated entries before append" >&2; exit 1; }

hjarne_log_append 'integrated board-dispatcher note'
TODAY=$(date +%F)
[[ "$(count)" -eq 1 ]] || { echo "FAIL: expected exactly 1 dated entry after append" >&2; exit 1; }
tail -1 "$LOG" | grep -qF "$TODAY" || { echo "FAIL: appended line missing today's date" >&2; exit 1; }
tail -1 "$LOG" | grep -qF 'integrated board-dispatcher note' || { echo "FAIL: message not appended" >&2; exit 1; }
grep -qF '# Log' "$LOG" || { echo "FAIL: prior content lost" >&2; exit 1; }

echo "test_hjarne_log_append: PASS"
