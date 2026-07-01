#!/usr/bin/env bash
# Forgejo board provisioning (#27 / #58) — hermetic, via curl-shim. provision_board
# asserts the per-repo issue-dependencies unit, then creates the 8 status columns +
# the priority/size/category taxonomy as EXCLUSIVE scoped labels. Live acceptance is
# Area 5 (bin/smoke/forgejo-roundtrip.sh); here we prove the REST shape only.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB="$REPO_ROOT/bin/harness-lib.sh"
FCFG="$REPO_ROOT/tests/scripts/fixtures/harness-config.forgejo.json"
FIX="$REPO_ROOT/tests/scripts/fixtures"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"

SHIM_DIR=$(mktemp -d); trap 'rm -rf "$SHIM_DIR"' EXIT
cp "$SCRIPT_DIR/lib/curl-shim.sh" "$SHIM_DIR/curl"; chmod +x "$SHIM_DIR/curl"
# $1 = call log, $2 = repo fixture (deps on/off), $3 = verb expression
run() { PATH="$SHIM_DIR:$PATH" HARNESS_CONFIG="$FCFG" FORGEJO_TOKEN="test-token" \
        CURL_SHIM_CALL_LOG="$1" CURL_SHIM_REPO_FIXTURE="$2" \
        bash -c "source '$LIB'; ${3}"; }

# --- deps unit ENABLED: provision succeeds -------------------------------------
L1="$SHIM_DIR/ok.log"; : > "$L1"
run "$L1" "$FIX/forgejo-repo-deps-on.json" "blacksmith_provision_board" \
  || { echo "FAIL: provision_board returned nonzero with the deps unit enabled" >&2; exit 1; }

# every label POST carries exclusive:true (single-select / server-enforced eviction).
grep -qF '"exclusive":true' "$L1" \
  || { echo "FAIL: labels not created with exclusive:true" >&2; exit 1; }
# all 8 reshaped status columns are provisioned (the 8-col scheme).
for s in backlog scoping planning plan_approval ready in_progress in_review done; do
  grep -qF "\"name\":\"status/$s\"" "$L1" \
    || { echo "FAIL: status/$s column not provisioned" >&2; exit 1; }
done
# priority / size / category taxonomy (spot-check one slug per scope).
grep -qF '"name":"priority/p1"'      "$L1" || { echo "FAIL: priority taxonomy missing" >&2; exit 1; }
grep -qF '"name":"size/xs"'          "$L1" || { echo "FAIL: size taxonomy missing"     >&2; exit 1; }
grep -qF '"name":"category/feature"' "$L1" || { echo "FAIL: category taxonomy missing" >&2; exit 1; }
# retired 9-col slugs must NOT be provisioned (this is the reshaped 8, not the legacy 9).
if grep -qF '"name":"status/research"' "$L1" || grep -qF '"name":"status/needs_input"' "$L1"; then
  echo "FAIL: a retired 9-col status slug was provisioned" >&2; exit 1
fi

# --- deps unit DISABLED: provision FAILS LOUDLY before touching labels ----------
L2="$SHIM_DIR/off.log"; : > "$L2"
if run "$L2" "$FIX/forgejo-repo-deps-off.json" "blacksmith_provision_board" 2>"$SHIM_DIR/off.err"; then
  echo "FAIL: provision_board succeeded with the deps unit DISABLED" >&2; exit 1
fi
grep -qiF 'issue-dependencies' "$SHIM_DIR/off.err" \
  || { echo "FAIL: no loud issue-dependencies error on stderr" >&2; cat "$SHIM_DIR/off.err" >&2; exit 1; }
if grep -qF '/labels' "$L2"; then
  echo "FAIL: labels created despite a disabled deps unit (gate must run first)" >&2; exit 1
fi

echo "test_blacksmith_forgejo_provision: PASS"
