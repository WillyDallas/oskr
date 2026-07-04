#!/usr/bin/env bash
# blacksmith_remote_exists (init v2, #27 / #57): the one forge-coupled
# mode-detection input. GitHub goes through `gh` (gh-shim); Forgejo through the
# curl transport (curl-shim). Asserts both exists (rc 0) and absent (rc != 0),
# and that the probe actually hit the forge. PATH-boundary shim replay.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FIX="$REPO_ROOT/tests/scripts/fixtures"
LIB="$REPO_ROOT/bin/harness-lib.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"

SHIM_DIR=$(mktemp -d); trap 'rm -rf "$SHIM_DIR"' EXIT
cp "$SCRIPT_DIR/lib/gh-shim.sh"   "$SHIM_DIR/gh";   chmod +x "$SHIM_DIR/gh"
cp "$SCRIPT_DIR/lib/curl-shim.sh" "$SHIM_DIR/curl"; chmod +x "$SHIM_DIR/curl"

# --- GitHub: rc 0 = exists, and the probe hit `gh repo view` ---
GLOG="$SHIM_DIR/gh.log"; : > "$GLOG"
rc=0
PATH="$SHIM_DIR:$PATH" HARNESS_CONFIG="$FIX/harness-config.sample.json" \
  GH_SHIM_CALL_LOG="$GLOG" GH_SHIM_FIXTURE="$FIX/gh-project-discovery.json" \
  GH_SHIM_REPO_VIEW_RC=0 \
  bash -c "source '$LIB'; blacksmith_remote_exists WillyDallas oskr" || rc=$?
assert_eq "0" "$rc" "github probe: existing repo -> rc 0" || exit 1
grep -qF 'repo view' "$GLOG" || { echo "FAIL: github probe did not call gh repo view" >&2; exit 1; }

# --- GitHub: rc != 0 = absent ---
rc=0
PATH="$SHIM_DIR:$PATH" HARNESS_CONFIG="$FIX/harness-config.sample.json" \
  GH_SHIM_CALL_LOG="$SHIM_DIR/gh2.log" GH_SHIM_FIXTURE="$FIX/gh-project-discovery.json" \
  GH_SHIM_REPO_VIEW_RC=1 \
  bash -c "source '$LIB'; blacksmith_remote_exists WillyDallas nope" || rc=$?
assert_eq "1" "$rc" "github probe: missing repo -> rc 1" || exit 1

# --- Forgejo: rc 0 = exists, and the probe GET the repo ---
CLOG="$SHIM_DIR/curl.log"; : > "$CLOG"
rc=0
PATH="$SHIM_DIR:$PATH" HARNESS_CONFIG="$FIX/harness-config.forgejo.json" FORGEJO_TOKEN="t" \
  CURL_SHIM_CALL_LOG="$CLOG" CURL_SHIM_REPO_RC=0 \
  bash -c "source '$LIB'; blacksmith_remote_exists squirrlylabs sluice" || rc=$?
assert_eq "0" "$rc" "forgejo probe: existing repo -> rc 0" || exit 1
grep -qF '/repos/squirrlylabs/sluice' "$CLOG" || { echo "FAIL: forgejo probe did not GET the repo" >&2; exit 1; }

# --- Forgejo: rc != 0 = absent ---
rc=0
PATH="$SHIM_DIR:$PATH" HARNESS_CONFIG="$FIX/harness-config.forgejo.json" FORGEJO_TOKEN="t" \
  CURL_SHIM_CALL_LOG="$SHIM_DIR/curl2.log" CURL_SHIM_REPO_RC=22 \
  bash -c "source '$LIB'; blacksmith_remote_exists squirrlylabs nope" || rc=$?
[[ "$rc" -ne 0 ]] || { echo "FAIL: forgejo probe missing repo should be non-zero" >&2; exit 1; }

echo "test_init_remote_probe: PASS"
