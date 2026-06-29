#!/usr/bin/env bash
# blacksmith_link_parent + blacksmith_list_children (GitHub, #26 slice 4):
# native sub-issues. Guards the capability-doc gotcha: the link API takes the
# child's DATABASE id, not its issue number.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB="$REPO_ROOT/bin/harness-lib.sh"
CFG="$REPO_ROOT/tests/scripts/fixtures/harness-config.sample.json"
source "$SCRIPT_DIR/lib/assert.sh"

SHIM_DIR=$(mktemp -d)
trap 'rm -rf "$SHIM_DIR"' EXIT
cp "$SCRIPT_DIR/lib/gh-shim.sh" "$SHIM_DIR/gh"; chmod +x "$SHIM_DIR/gh"

# --- link_parent: child #7 (db id 9001) under parent #3 ---
LOG="$SHIM_DIR/link.log"; : > "$LOG"
PATH="$SHIM_DIR:$PATH" HARNESS_CONFIG="$CFG" GH_SHIM_CALL_LOG="$LOG" \
  GH_SHIM_FIXTURE="$REPO_ROOT/tests/scripts/fixtures/gh-issue-single.json" \
  bash -c "source '$LIB'; blacksmith_link_parent 3 7"

grep -qF 'issues/7' "$LOG"            || { echo "FAIL: child #7 not resolved" >&2; exit 1; }
grep -qF 'issues/3/sub_issues' "$LOG" || { echo "FAIL: not linked under parent #3" >&2; exit 1; }
grep -qF 'sub_issue_id=9001' "$LOG"   || { echo "FAIL: did not link by child DATABASE id" >&2; exit 1; }
if grep -qF 'sub_issue_id=7' "$LOG"; then echo "FAIL: linked by issue number, not db id" >&2; exit 1; fi

# --- list_children: parent #3 -> two children, normalized ---
LOG2="$SHIM_DIR/list.log"; : > "$LOG2"
out=$(PATH="$SHIM_DIR:$PATH" HARNESS_CONFIG="$CFG" GH_SHIM_CALL_LOG="$LOG2" \
  GH_SHIM_FIXTURE="$REPO_ROOT/tests/scripts/fixtures/gh-issue-single.json" \
  GH_SHIM_SUBISSUES_FIXTURE="$REPO_ROOT/tests/scripts/fixtures/gh-subissues.json" \
  bash -c "source '$LIB'; blacksmith_list_children 3")

assert_eq "2"      "$(jq 'length' <<<"$out")"        "list_children: 2 children"  || exit 1
assert_eq "7"      "$(jq -r '.[0].number' <<<"$out")" "first child number"        || exit 1
assert_eq "open"   "$(jq -r '.[0].state'  <<<"$out")" "first child state"         || exit 1
assert_eq "closed" "$(jq -r '.[1].state'  <<<"$out")" "second child state"        || exit 1

echo "test_blacksmith_link_children: PASS"
