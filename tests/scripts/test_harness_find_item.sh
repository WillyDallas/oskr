#!/usr/bin/env bash
# blacksmith_find_item: returns the project item id for the issue, filtered to the
# configured project_number (the sample config uses project_number 1, so the
# fixture node under project 99 must be excluded).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/lib/assert.sh"

SHIM_DIR=$(mktemp -d); CACHE_DIR=$(mktemp -d)
trap 'rm -rf "$SHIM_DIR" "$CACHE_DIR"' EXIT
GH_SHIM_CALL_LOG="$SHIM_DIR/gh-calls.log"; : > "$GH_SHIM_CALL_LOG"
cp "$SCRIPT_DIR/lib/gh-shim.sh" "$SHIM_DIR/gh"; chmod +x "$SHIM_DIR/gh"

out=$(PATH="$SHIM_DIR:$PATH" \
  HARNESS_CONFIG="$REPO_ROOT/tests/scripts/fixtures/harness-config.sample.json" \
  GH_SHIM_CALL_LOG="$GH_SHIM_CALL_LOG" \
  GH_SHIM_FIXTURE="$REPO_ROOT/tests/scripts/fixtures/gh-project-discovery.json" \
  GH_SHIM_FIND_ITEM_FIXTURE="$REPO_ROOT/tests/scripts/fixtures/gh-find-item.json" \
  XDG_CACHE_HOME="$CACHE_DIR" \
  bash -c "source '$REPO_ROOT/bin/harness-lib.sh'; blacksmith_find_item 10")

assert_eq "PVTI_target123" "$out" "find_item selects the item for the configured project_number" || exit 1
echo "test_blacksmith_find_item: PASS"
