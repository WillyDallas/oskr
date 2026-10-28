#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"
source "$REPO_ROOT/bin/harness-lib.sh"    # tail-sources hjarne-lib + learning-lib (unit under test)

WS=$(cd "$(mktemp -d)" && pwd)
trap 'rm -rf "$WS"' EXIT
mkdir -p "$WS/.oskr"
export OSKR_WORKSPACE="$WS"

# fresh workspace: no brain wiki yet -> empty output, exit 0
GOT=$(learning_status)
assert_eq "" "$GOT" "no topics in a fresh workspace"

# Fixture pages written directly (not through the seam) so each stamp date is fixed.
W="$WS/hjarne/wiki"
mkdir -p "$W"
page() {  # page <system-slug> <h1> <stamp-date> [body]
  printf '# %s\n> Written %s · Mode: deep · v1\n\n%s\n' "$2" "$3" "${4:-}" > "$W/$1.md"
}
# rust: pace 1, one stale session
page learning-rust-mission "Mission: Rust" 2026-01-01 $'## Constraints\n- Pace: 1 session a week'
page learning-rust-resources "Rust Resources" 2026-01-01
# french: pace 2; the newest stamp is a record, not the mission
page learning-french-mission "Mission: French" 2026-01-01 $'## Constraints\n- Pace: 2 sessions a week (while in class)'
page learning-french-glossary "French Glossary" 2026-01-03
page learning-french-record-0001-start "Start" 2026-01-08
# french-cooking: its slug extends french's; its newer stamp must not leak into french
page learning-french-cooking-mission "Mission: French Cooking" 2026-01-10 $'- Pace: 1 session a week'
# chess: no Pace line
page learning-chess-mission "Mission: Chess" 2026-01-09 $'## Constraints\n- Short lessons'

BEFORE=$(cat "$W"/*.md | shasum)

EXPECT=$'chess\tChess\t2026-01-09\t-\t1\tno-pace
french\tFrench\t2026-01-08\t2\t2\tok
french-cooking\tFrench Cooking\t2026-01-10\t1\t0\tok
rust\tRust\t2026-01-01\t1\t9\toverdue'
GOT=$(LEARNING_TODAY=2026-01-10 learning_status | LC_ALL=C sort)
assert_eq "$EXPECT" "$GOT" "newest stamp per topic, pace from the mission, overdue past 7/N days"

# boundaries: pace 1 allows 7 days, pace 2 allows 4 (7/2 rounded up)
GOT=$(LEARNING_TODAY=2026-01-08 learning_status | grep '^rust' | cut -f5,6)
assert_eq $'7\tok' "$GOT" "pace 1: day 7 is still ok"
GOT=$(LEARNING_TODAY=2026-01-12 learning_status | grep '^french	' | cut -f5,6)
assert_eq $'4\tok' "$GOT" "pace 2: day 4 is still ok"
GOT=$(LEARNING_TODAY=2026-01-13 learning_status | grep '^french	' | cut -f5,6)
assert_eq $'5\toverdue' "$GOT" "pace 2: day 5 is overdue"

# across a DST change (US: 2026-03-08) the day count stays whole
GOT=$(LEARNING_TODAY=2026-03-10 learning_status | grep '^chess' | cut -f5)
assert_eq "60" "$GOT" "2026-01-09 to 2026-03-10 is 60 days"

# READ-ONLY: no page changed
assert_eq "$BEFORE" "$(cat "$W"/*.md | shasum)" "learning_status never mutates the brain"

# zsh leg: same rows under zsh (null_glob for the record glob; no read-only $status)
if command -v zsh >/dev/null 2>&1; then
  GOT=$(zsh -c "export OSKR_WORKSPACE='$WS' LEARNING_TODAY=2026-01-10; \
    source '$REPO_ROOT/bin/harness-lib.sh'; learning_status" | LC_ALL=C sort) \
    || { echo "FAIL: learning_status failed under zsh" >&2; exit 1; }
  assert_eq "$EXPECT" "$GOT" "same rows under zsh"
fi

echo "test_learning_status: PASS"
