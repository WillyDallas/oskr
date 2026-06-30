#!/usr/bin/env bash
# blacksmith_add_dep — record "<blocked> is blocked by <blocker>" as a NATIVE typed
# edge on each forge (the write side of blacksmith_read_deps). Pins the ID model:
# GitHub resolves the blocker to its DATABASE id and POSTs to /dependencies/blocked_by;
# Forgejo POSTs IssueMeta{index=<number>} to /issues/<blocked>/dependencies.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/lib/assert.sh"

SHIM_DIR=$(mktemp -d)
trap 'rm -rf "$SHIM_DIR"' EXIT
cp "$SCRIPT_DIR/lib/gh-shim.sh"   "$SHIM_DIR/gh";   chmod +x "$SHIM_DIR/gh"
cp "$SCRIPT_DIR/lib/curl-shim.sh" "$SHIM_DIR/curl"; chmod +x "$SHIM_DIR/curl"
: > "$SHIM_DIR/calls.log"

# --- GitHub backend: #10 blocked-by #4. The shim returns the blocker's db id
#     (555) from GH_SHIM_FIXTURE, which add_dep must use as issue_id on the POST.
PATH="$SHIM_DIR:$PATH" \
  HARNESS_CONFIG="$REPO_ROOT/tests/scripts/fixtures/harness-config.sample.json" \
  GH_SHIM_CALL_LOG="$SHIM_DIR/calls.log" \
  GH_SHIM_FIXTURE="$REPO_ROOT/tests/scripts/fixtures/gh-issue-id.json" \
  bash -c "source '$REPO_ROOT/bin/harness-lib.sh'; blacksmith_add_dep 10 4" \
  || { echo "FAIL: github add_dep returned nonzero" >&2; exit 1; }

# --- Forgejo backend: same edge, IssueMeta{index=4} on /issues/10/dependencies.
PATH="$SHIM_DIR:$PATH" \
  HARNESS_CONFIG="$REPO_ROOT/tests/scripts/fixtures/harness-config.forgejo.json" \
  CURL_SHIM_CALL_LOG="$SHIM_DIR/calls.log" \
  FORGEJO_TOKEN="test-token" \
  bash -c "source '$REPO_ROOT/bin/harness-lib.sh'; blacksmith_add_dep 10 4" \
  || { echo "FAIL: forgejo add_dep returned nonzero" >&2; exit 1; }

# GitHub: must POST the blocked-by edge on #10 with the blocker's DB id (555), not
# the issue number (4) — the ID-model gotcha.
grep -qE 'issues/10/dependencies/blocked_by .*issue_id=555' "$SHIM_DIR/calls.log" \
  || { echo "FAIL: github add_dep must POST blocked_by with the blocker DB id (issue_id=555)" >&2; exit 1; }
# Forgejo: must POST to the bare /dependencies (blocked-by direction) with index=4.
grep -qE 'POST.*issues/10/dependencies' "$SHIM_DIR/calls.log" \
  || { echo "FAIL: forgejo add_dep must POST /issues/10/dependencies" >&2; exit 1; }
grep -qF '"index":4' "$SHIM_DIR/calls.log" \
  || { echo "FAIL: forgejo add_dep must carry IssueMeta index=4" >&2; exit 1; }

echo "test_blacksmith_add_dep: PASS"
