#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/lib/assert.sh"

SHIM_DIR=$(mktemp -d); trap 'rm -rf "$SHIM_DIR"' EXIT
GH_SHIM_CALL_LOG="$SHIM_DIR/gh-calls.log"
GH_SHIM_FIXTURE="$REPO_ROOT/tests/scripts/fixtures/gh-project-discovery.json"
: > "$GH_SHIM_CALL_LOG"

# Install the shim as `gh` on PATH
cp "$SCRIPT_DIR/lib/gh-shim.sh" "$SHIM_DIR/gh"
chmod +x "$SHIM_DIR/gh"

# Use sample config and isolate the cache dir
XDG_CACHE_HOME=$(mktemp -d)

PATH="$SHIM_DIR:$PATH" \
  HARNESS_CONFIG="$REPO_ROOT/tests/scripts/fixtures/harness-config.sample.json" \
  GH_SHIM_CALL_LOG="$GH_SHIM_CALL_LOG" \
  GH_SHIM_FIXTURE="$GH_SHIM_FIXTURE" \
  XDG_CACHE_HOME="$XDG_CACHE_HOME" \
  bash -c "
    source '$REPO_ROOT/scripts/harness-lib.sh'
    [[ \$(harness_project_id) == 'PVT_kwTEST123' ]] || { echo FAIL project_id; exit 1; }
    [[ \$(harness_status_field_id) == 'PVTSSF_statusTEST' ]] || { echo FAIL status_field_id; exit 1; }
    [[ \$(harness_field_id 'Priority') == 'PVTSSF_priorityTEST' ]] || { echo FAIL priority_field_id; exit 1; }
  "

echo "test_harness_project_discovery: PASS"
