#!/usr/bin/env bash
# blacksmith_create_milestone — idempotent find-or-create of an Epoch milestone by
# TITLE, echoing its native id. Adopt re-emit needs this because set_milestone only
# RESOLVES an existing milestone. Found-path issues no POST; absent-path creates.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB="$REPO_ROOT/bin/harness-lib.sh"
FIX="$REPO_ROOT/tests/scripts/fixtures"
source "$SCRIPT_DIR/lib/assert.sh"

SHIM_DIR=$(mktemp -d); trap 'rm -rf "$SHIM_DIR"' EXIT
cp "$SCRIPT_DIR/lib/gh-shim.sh"   "$SHIM_DIR/gh";   chmod +x "$SHIM_DIR/gh"
cp "$SCRIPT_DIR/lib/curl-shim.sh" "$SHIM_DIR/curl"; chmod +x "$SHIM_DIR/curl"

# --- GitHub found-path: "oskr v1" exists (number 3) -> no POST ---
LOG="$SHIM_DIR/found.log"; : > "$LOG"
n=$(PATH="$SHIM_DIR:$PATH" HARNESS_CONFIG="$FIX/harness-config.sample.json" \
  GH_SHIM_CALL_LOG="$LOG" GH_SHIM_FIXTURE="$FIX/gh-milestones.json" \
  GH_SHIM_MILESTONES_FIXTURE="$FIX/gh-milestones.json" \
  bash -c "source '$LIB'; blacksmith_create_milestone 'oskr v1'")
assert_eq "3" "$n" "github found-path returns existing milestone number" || exit 1
if grep -qF 'title=' "$LOG"; then echo "FAIL: found-path must not POST a create" >&2; exit 1; fi

# --- GitHub create-path: "New Epoch" absent -> POST create, number 9 ---
LOG2="$SHIM_DIR/create.log"; : > "$LOG2"
n2=$(PATH="$SHIM_DIR:$PATH" HARNESS_CONFIG="$FIX/harness-config.sample.json" \
  GH_SHIM_CALL_LOG="$LOG2" GH_SHIM_FIXTURE="$FIX/gh-milestones.json" \
  GH_SHIM_MILESTONES_FIXTURE="$FIX/gh-milestones.json" \
  GH_SHIM_CREATE_MILESTONE_FIXTURE="$FIX/gh-create-milestone.json" \
  bash -c "source '$LIB'; blacksmith_create_milestone 'New Epoch'")
assert_eq "9" "$n2" "github create-path returns new milestone number" || exit 1
grep -qF 'title=New Epoch' "$LOG2" || { echo "FAIL: create-path must POST title=New Epoch" >&2; exit 1; }

# --- Forgejo found-path: "oskr v1" exists (id 42) ---
LOG3="$SHIM_DIR/fj.log"; : > "$LOG3"
fid=$(PATH="$SHIM_DIR:$PATH" HARNESS_CONFIG="$FIX/harness-config.forgejo.json" \
  FORGEJO_TOKEN="test-token" CURL_SHIM_CALL_LOG="$LOG3" \
  CURL_SHIM_MILESTONES_FIXTURE="$FIX/forgejo-milestones.json" \
  bash -c "source '$LIB'; blacksmith_create_milestone 'oskr v1'")
assert_eq "42" "$fid" "forgejo found-path returns existing milestone id" || exit 1

echo "test_blacksmith_create_milestone: PASS"
