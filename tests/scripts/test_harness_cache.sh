#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

SHIM_DIR=$(mktemp -d); CACHE_DIR=$(mktemp -d)
trap 'rm -rf "$SHIM_DIR" "$CACHE_DIR"' EXIT
GH_SHIM_CALL_LOG="$SHIM_DIR/gh-calls.log"
: > "$GH_SHIM_CALL_LOG"
cp "$SCRIPT_DIR/lib/gh-shim.sh" "$SHIM_DIR/gh"
chmod +x "$SHIM_DIR/gh"

PATH="$SHIM_DIR:$PATH" \
  HARNESS_CONFIG="$REPO_ROOT/tests/scripts/fixtures/harness-config.sample.json" \
  GH_SHIM_CALL_LOG="$GH_SHIM_CALL_LOG" \
  GH_SHIM_FIXTURE="$REPO_ROOT/tests/scripts/fixtures/gh-project-discovery.json" \
  XDG_CACHE_HOME="$CACHE_DIR" \
  bash -c "
    source '$REPO_ROOT/bin/harness-lib.sh'
    harness_project_id >/dev/null
    harness_status_field_id >/dev/null
    harness_field_id 'Priority' >/dev/null
    [[ \$(wc -l < '$GH_SHIM_CALL_LOG') -eq 1 ]] || { echo FAIL: expected 1 gh call, got \$(wc -l < '$GH_SHIM_CALL_LOG'); exit 1; }
    test -f '$CACHE_DIR/oskr/1-WillyDallas-oskr.json' || { echo FAIL: cache file missing; exit 1; }
    harness_cache_clear
    test ! -f '$CACHE_DIR/oskr/1-WillyDallas-oskr.json' || { echo FAIL: cache_clear did not remove file; exit 1; }
    harness_project_id >/dev/null
    [[ \$(wc -l < '$GH_SHIM_CALL_LOG') -eq 2 ]] || { echo FAIL: expected 2 gh calls after clear, got \$(wc -l < '$GH_SHIM_CALL_LOG'); exit 1; }
  "

echo "test_harness_cache: PASS"
