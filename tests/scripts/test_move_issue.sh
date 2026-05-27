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

env -i \
  PATH="$SHIM_DIR:/usr/bin:/bin:/usr/local/bin" \
  HOME="$HOME" \
  HARNESS_CONFIG="$REPO_ROOT/tests/scripts/fixtures/harness-config.sample.json" \
  GH_SHIM_CALL_LOG="$GH_SHIM_CALL_LOG" \
  GH_SHIM_FIXTURE="$REPO_ROOT/tests/scripts/fixtures/gh-project-discovery.json" \
  XDG_CACHE_HOME="$CACHE_DIR" \
  HARNESS_TOKEN_REPORT="off" \
  bash "$REPO_ROOT/bin/move-issue.sh" "PVTI_test" "Planning" >/dev/null

grep -qF 'updateProjectV2ItemFieldValue' "$GH_SHIM_CALL_LOG" || { echo FAIL: mutation not invoked; exit 1; }
grep -qF 'opt-planning' "$GH_SHIM_CALL_LOG" || { echo FAIL: planning option UUID not in mutation call; exit 1; }

echo "test_move_issue: PASS"
