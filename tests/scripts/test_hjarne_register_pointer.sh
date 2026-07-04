#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"
source "$REPO_ROOT/bin/harness-lib.sh"   # blacksmith_workspace_dir / _blacksmith_die
source "$REPO_ROOT/bin/hjarne-lib.sh"    # unit under test

WS=$(cd "$(mktemp -d)" && pwd)           # canonicalized so /tmp symlinks don't break ==
WS2=$(cd "$(mktemp -d)" && pwd)          # 2nd workspace: brain-absent case
trap 'rm -rf "$WS" "$WS2"' EXIT
mkdir -p "$WS/.oskr"
bash "$REPO_ROOT/bin/hjarne-skeleton.sh" "$WS/hjarne"
export OSKR_WORKSPACE="$WS"
BRAIN="$WS/hjarne"

LOG="$BRAIN/log.md"
# reuse T2's dated-entry counter (|| true: grep -c exits 1 at count 0, fatal under set -e)
count() { grep -cE '^- [0-9]{4}-[0-9]{2}-[0-9]{2} ' "$LOG" || true; }
wiki_md() { find "$BRAIN/wiki" -name '*.md' 2>/dev/null | wc -l | tr -d ' '; }

DATE=$(date +%F)
C1=$'# Research Digest\n\nBLUF: the dispatcher polls the board. [#28]\n'
DIGEST="$BRAIN/raw/research/28-${DATE}/digest.md"

# --- present: 1st run -> +1 INGEST line, digest.md created, ZERO wiki delta ---
L_BEFORE=$(count); W_BEFORE=$(wiki_md)
hjarne_register_pointer '28' "$C1" '28'
[[ "$(count)" -eq "$((L_BEFORE + 1))" ]] \
  || { echo "FAIL: expected exactly +1 INGEST log entry" >&2; exit 1; }
test -f "$DIGEST" || { echo "FAIL: digest.md not created at $DIGEST" >&2; exit 1; }
grep -qF 'BLUF: the dispatcher polls the board.' "$DIGEST" \
  || { echo "FAIL: digest content not deposited" >&2; exit 1; }
tail -1 "$LOG" | grep -qF "INGEST raw/research/28-${DATE}/ (28)" \
  || { echo "FAIL: INGEST log line wrong ($(tail -1 "$LOG"))" >&2; exit 1; }
[[ "$(wiki_md)" -eq "$W_BEFORE" ]] \
  || { echo "FAIL: register_pointer created a wiki page (delta != 0)" >&2; exit 1; }

# --- idempotent (same process): 2nd run -> +0 INGEST, digest byte-identical ---
cp "$DIGEST" "$WS/digest.snapshot"
L_MID=$(count)
hjarne_register_pointer '28' "$C1" '28'
[[ "$(count)" -eq "$L_MID" ]] \
  || { echo "FAIL: 2nd run added an INGEST entry (not idempotent)" >&2; exit 1; }
cmp -s "$DIGEST" "$WS/digest.snapshot" \
  || { echo "FAIL: 2nd run mutated digest.md bytes" >&2; exit 1; }

# --- absent: brain dir NOT stamped -> no-op, 0 files written, exit 0 under set -e ---
mkdir -p "$WS2/.oskr"                     # workspace marker present, brain NOT stamped
export OSKR_WORKSPACE="$WS2"
hjarne_register_pointer '28' "$C1" '28'   # must no-op cleanly (exit 0)
test ! -e "$WS2/hjarne" \
  || { echo "FAIL: brain-absent case created $WS2/hjarne" >&2; exit 1; }
FILES=$(find "$WS2" -type f | wc -l | tr -d ' ')
[[ "$FILES" -eq 0 ]] \
  || { echo "FAIL: brain-absent case wrote $FILES files (expected 0)" >&2; exit 1; }
export OSKR_WORKSPACE="$WS"

# --- never routes/writes a wiki page: the function body forbids the page writers ---
LIB="$REPO_ROOT/bin/hjarne-lib.sh"
if awk '/^hjarne_register_pointer\(\)/{f=1} f' "$LIB" | grep -qE 'hjarne_route|hjarne_write_page'; then
  echo "FAIL: hjarne_register_pointer body references hjarne_route/hjarne_write_page" >&2; exit 1
fi

echo "test_hjarne_register_pointer: PASS"
