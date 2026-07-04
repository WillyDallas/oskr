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
entries() { grep -cE '^- [0-9]{4}-[0-9]{2}-[0-9]{2} ' "$LOG" || true; }
C1=$'# Board Dispatcher\n\nPolls the board.'

# M6: systems note → wiki/<system>.md + raw archived
hjarne_integrate '#70:board-dispatcher' board-dispatcher "$C1"
test -f "$BRAIN/wiki/board-dispatcher.md" || { echo "FAIL: M6 page not routed to wiki" >&2; exit 1; }
test -f "$(hjarne_raw_path '#70:board-dispatcher')" || { echo "FAIL: M6 raw not archived" >&2; exit 1; }

# M6: research subdir → raw/research/
hjarne_integrate '#71:nutrition-lit' nutrition "$C1" research
RAWR=$(hjarne_raw_path '#71:nutrition-lit' research)
case "$RAWR" in "$BRAIN/raw/research/"*) test -f "$RAWR" || { echo "FAIL: research raw missing" >&2; exit 1; } ;;
  *) echo "FAIL: research subdir not honored" >&2; exit 1 ;; esac

# M5: re-integrate SAME provenance → dedup short-circuit (no v-bump, no 2nd log)
PAGE="$BRAIN/wiki/board-dispatcher.md"
V_BEFORE=$(sed -n 2p "$PAGE"); E_BEFORE=$(entries)
hjarne_integrate '#70:board-dispatcher' board-dispatcher "$C1"
assert_eq "$V_BEFORE" "$(sed -n 2p "$PAGE")" "M5 dedup: page stamp unchanged"
assert_eq "$E_BEFORE" "$(entries)" "M5 dedup: no 2nd log entry"

# M9: two distinct notes, same issue #72, distinct provenance → BOTH land, ZERO short-circuit
E0=$(entries)
hjarne_integrate '#72:find-item'  find-item  "$C1"
hjarne_integrate '#72:move-issue' move-issue "$C1"
test -f "$BRAIN/wiki/find-item.md"  || { echo "FAIL: M9 find-item page missing" >&2; exit 1; }
test -f "$BRAIN/wiki/move-issue.md" || { echo "FAIL: M9 move-issue page missing" >&2; exit 1; }
test -f "$(hjarne_raw_path '#72:find-item')"  || { echo "FAIL: M9 find-item raw missing" >&2; exit 1; }
test -f "$(hjarne_raw_path '#72:move-issue')" || { echo "FAIL: M9 move-issue raw missing" >&2; exit 1; }
[[ "$(entries)" -eq "$((E0 + 2))" ]] || { echo "FAIL: M9 expected 2 new log entries" >&2; exit 1; }

# ---------------------------------------------------------------------------
# M10: NO brain resolves → integrate STAGES to the inbox — nothing dropped, the
# brain is NOT auto-created (optional, never a hard dependency), the note is not
# double-homed (skips the brain write path entirely), and a re-integrate stays
# idempotent (inbox_stage is provenance-keyed). Uses a SEPARATE workspace whose
# hjarne/ was never stamped, so hjarne_resolve_brain succeeds but the brain dir
# is absent — the `[[ ! -d "$brain" ]]` fallback branch.
# ---------------------------------------------------------------------------
WS2=$(cd "$(mktemp -d)" && pwd)              # a workspace whose hjarne/ is NOT stamped
trap 'rm -rf "$WS" "$WS2"' EXIT              # extend cleanup (fixture trap only had $WS)
mkdir -p "$WS2/.oskr"
export OSKR_WORKSPACE="$WS2"
export HJARNE_INBOX_DIR="$WS2/brain-inbox"   # override the repo-side default via env
C2=$'# Move Issue\n\nMoves a card between columns.'
inbox_files() { find "$HJARNE_INBOX_DIR" -maxdepth 1 -name '*.md' 2>/dev/null | grep -c . || true; }

# brain dir absent → integrate stages to the inbox and returns 0 (nothing dropped)
hjarne_integrate '#80:move-issue' move-issue "$C2"
[[ "$(inbox_files)" -eq 1 ]] || { echo "FAIL: M10 no-brain integrate did not stage exactly one inbox note" >&2; exit 1; }
STAGED=$(find "$HJARNE_INBOX_DIR" -maxdepth 1 -name '*.md')
grep -qF 'Moves a card between columns.' "$STAGED" || { echo "FAIL: M10 staged note missing content" >&2; exit 1; }
grep -qF '<!-- hjarne:meta provenance=#80:move-issue' "$STAGED" || { echo "FAIL: M10 staged note missing hjarne:meta fence" >&2; exit 1; }

# brain NOT auto-created, and nothing double-homed (no page under an absent brain)
! test -e "$WS2/hjarne" || { echo "FAIL: M10 integrate auto-created the brain" >&2; exit 1; }
! test -e "$WS2/hjarne/wiki/move-issue.md" || { echo "FAIL: M10 note double-homed into a brain page" >&2; exit 1; }

# idempotent: same provenance → same inbox filename → still exactly one note
hjarne_integrate '#80:move-issue' move-issue "$C2"
[[ "$(inbox_files)" -eq 1 ]] || { echo "FAIL: M10 re-integrate not idempotent (expected exactly one inbox note)" >&2; exit 1; }

echo "test_hjarne_integrate: PASS"
