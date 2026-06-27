#!/usr/bin/env bash
# blacksmith_list_board: paginates and assembles a GitHub-native board blob whose
# totalCount and node count match the (single-page) fixture.
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

total=$(echo "$blob" | jq '.data.repository.projectV2.items.totalCount')
count=$(echo "$blob" | jq '.data.repository.projectV2.items.nodes | length')
assert_eq "2" "$total" "list_board preserves totalCount" || exit 1
assert_eq "2" "$count" "list_board assembled all nodes" || exit 1
echo "test_blacksmith_list_board: PASS"
