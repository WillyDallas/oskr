#!/usr/bin/env bash
# blacksmith_list_board: paginates and assembles the backend-NEUTRAL board shape
# ({ total, items:[ {number,title,status,priority,category,labels,…} ] }) from the
# GitHub-native pages, flattening content/*.name into flat fields.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/lib/assert.sh"

SHIM_DIR=$(mktemp -d); CACHE_DIR=$(mktemp -d)
trap 'rm -rf "$SHIM_DIR" "$CACHE_DIR"' EXIT
GH_SHIM_CALL_LOG="$SHIM_DIR/gh-calls.log"; : > "$GH_SHIM_CALL_LOG"
cp "$SCRIPT_DIR/lib/gh-shim.sh" "$SHIM_DIR/gh"; chmod +x "$SHIM_DIR/gh"

blob=$(PATH="$SHIM_DIR:$PATH" \
  HARNESS_CONFIG="$REPO_ROOT/tests/scripts/fixtures/harness-config.sample.json" \
  GH_SHIM_CALL_LOG="$GH_SHIM_CALL_LOG" \
  GH_SHIM_FIXTURE="$REPO_ROOT/tests/scripts/fixtures/gh-project-discovery.json" \
  GH_SHIM_BOARD_FIXTURE="$REPO_ROOT/tests/scripts/fixtures/gh-board-items.json" \
  XDG_CACHE_HOME="$CACHE_DIR" \
  bash -c "source '$REPO_ROOT/bin/harness-lib.sh'; blacksmith_list_board")

total=$(echo "$blob" | jq '.total')
count=$(echo "$blob" | jq '.items | length')
assert_eq "2" "$total" "list_board preserves total (pagination integrity)" || exit 1
assert_eq "2" "$count" "list_board assembled all items" || exit 1

# Flat neutral item shape — not the GitHub-native content/*.name nesting.
assert_eq "10"      "$(echo "$blob" | jq '.items[0].number')"        "item carries flat number"   || exit 1
assert_eq "A"       "$(echo "$blob" | jq -r '.items[0].title')"      "item carries flat title"    || exit 1
assert_eq "Ready"   "$(echo "$blob" | jq -r '.items[0].status')"     "status flattened to a name" || exit 1
assert_eq "P1"      "$(echo "$blob" | jq -r '.items[0].priority')"   "priority flattened"         || exit 1
assert_eq "null"    "$(echo "$blob" | jq '.items[1].priority')"      "null priority preserved"    || exit 1
assert_eq "[]"      "$(echo "$blob" | jq -c '.items[0].labels')"     "labels flattened to names"  || exit 1
assert_eq "0"       "$(echo "$blob" | jq '.items[0].blocking')"      "blocking is a flat count"   || exit 1
# No GitHub-native leakage in the neutral shape.
assert_eq "null"    "$(echo "$blob" | jq '.data')"                   "no GitHub-native .data wrapper" || exit 1
echo "test_blacksmith_list_board: PASS"
