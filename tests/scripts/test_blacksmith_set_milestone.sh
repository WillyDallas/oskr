#!/usr/bin/env bash
# blacksmith_set_milestone — resolve a milestone TITLE to the backend's native id
# (GitHub: milestone number; Forgejo: milestone id) and PATCH the issue. The
# milestone must already exist (creating Epoch milestones is a manual setup step).
# Both backends pinned via the call log: the resolution GET + the PATCH payload.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/lib/assert.sh"

SHIM_DIR=$(mktemp -d)
trap 'rm -rf "$SHIM_DIR"' EXIT
cp "$SCRIPT_DIR/lib/gh-shim.sh"   "$SHIM_DIR/gh";   chmod +x "$SHIM_DIR/gh"
cp "$SCRIPT_DIR/lib/curl-shim.sh" "$SHIM_DIR/curl"; chmod +x "$SHIM_DIR/curl"
: > "$SHIM_DIR/calls.log"

# --- GitHub backend (forge=github) ---
PATH="$SHIM_DIR:$PATH" \
  HARNESS_CONFIG="$REPO_ROOT/tests/scripts/fixtures/harness-config.sample.json" \
  GH_SHIM_CALL_LOG="$SHIM_DIR/calls.log" \
  GH_SHIM_FIXTURE="$REPO_ROOT/tests/scripts/fixtures/gh-milestones.json" \
  GH_SHIM_MILESTONES_FIXTURE="$REPO_ROOT/tests/scripts/fixtures/gh-milestones.json" \
  bash -c "source '$REPO_ROOT/bin/harness-lib.sh'; blacksmith_set_milestone 7 'oskr v1'" \
  || { echo "FAIL: github set_milestone returned nonzero" >&2; exit 1; }

# --- Forgejo backend (forge=forgejo) ---
PATH="$SHIM_DIR:$PATH" \
  HARNESS_CONFIG="$REPO_ROOT/tests/scripts/fixtures/harness-config.forgejo.json" \
  CURL_SHIM_CALL_LOG="$SHIM_DIR/calls.log" \
  CURL_SHIM_MILESTONES_FIXTURE="$REPO_ROOT/tests/scripts/fixtures/forgejo-milestones.json" \
  FORGEJO_TOKEN="test-token" \
  bash -c "source '$REPO_ROOT/bin/harness-lib.sh'; blacksmith_set_milestone 7 'oskr v1'" \
  || { echo "FAIL: forgejo set_milestone returned nonzero" >&2; exit 1; }

# GitHub: resolve via milestones list, then PATCH issue 7 with the NUMBER (3).
grep -qF 'milestones?state=all'      "$SHIM_DIR/calls.log" || { echo "FAIL: github must list milestones to resolve title" >&2; exit 1; }
grep -qE 'issues/7 .*milestone=3'    "$SHIM_DIR/calls.log" || { echo "FAIL: github must PATCH issue 7 with milestone=3" >&2; exit 1; }
# Forgejo: PATCH issue 7 with the resolved ID (42) in the JSON body.
grep -qE 'PATCH.*issues/7'           "$SHIM_DIR/calls.log" || { echo "FAIL: forgejo must PATCH issue 7" >&2; exit 1; }
grep -qF '"milestone":42'            "$SHIM_DIR/calls.log" || { echo "FAIL: forgejo must set milestone id 42" >&2; exit 1; }

# Title-not-found must FAIL (never silently no-op) — creating milestones is manual.
if PATH="$SHIM_DIR:$PATH" \
   HARNESS_CONFIG="$REPO_ROOT/tests/scripts/fixtures/harness-config.sample.json" \
   GH_SHIM_CALL_LOG="$SHIM_DIR/calls.log" \
   GH_SHIM_FIXTURE="$REPO_ROOT/tests/scripts/fixtures/gh-milestones.json" \
   GH_SHIM_MILESTONES_FIXTURE="$REPO_ROOT/tests/scripts/fixtures/gh-milestones.json" \
   bash -c "source '$REPO_ROOT/bin/harness-lib.sh'; blacksmith_set_milestone 7 'no-such-epoch'" 2>/dev/null; then
  echo "FAIL: set_milestone must fail on an unknown milestone title" >&2; exit 1
fi

echo "test_blacksmith_set_milestone: PASS"
