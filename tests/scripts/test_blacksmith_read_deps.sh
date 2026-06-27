#!/usr/bin/env bash
# blacksmith_read_deps — native blocked-by on BOTH forges, normalized to one shape.
# This is the #26 neutrality probe: the GitHub backend (via gh-shim, native
# dependencies API) and the Forgejo backend (via curl-shim, native dependencies
# API) must return the SAME neutral edge list, modulo the host-specific url.
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
gh_out=$(PATH="$SHIM_DIR:$PATH" \
  HARNESS_CONFIG="$REPO_ROOT/tests/scripts/fixtures/harness-config.sample.json" \
  GH_SHIM_CALL_LOG="$SHIM_DIR/calls.log" \
  GH_SHIM_FIXTURE="$REPO_ROOT/tests/scripts/fixtures/gh-deps-blocked-by.json" \
  bash -c "source '$REPO_ROOT/bin/harness-lib.sh'; blacksmith_read_deps 5")

# --- Forgejo backend (forge=forgejo) ---
fj_out=$(PATH="$SHIM_DIR:$PATH" \
  HARNESS_CONFIG="$REPO_ROOT/tests/scripts/fixtures/harness-config.forgejo.json" \
  CURL_SHIM_CALL_LOG="$SHIM_DIR/calls.log" \
  CURL_SHIM_DEPS_FIXTURE="$REPO_ROOT/tests/scripts/fixtures/forgejo-deps.json" \
  FORGEJO_TOKEN="test-token" \
  bash -c "source '$REPO_ROOT/bin/harness-lib.sh'; blacksmith_read_deps 5")

# Each backend: 2 blockers, exactly 1 open (the mechanical auto-grab gate input).
assert_eq "2" "$(jq 'length' <<<"$gh_out")"                              "github: 2 blockers"     || exit 1
assert_eq "2" "$(jq 'length' <<<"$fj_out")"                              "forgejo: 2 blockers"    || exit 1
assert_eq "1" "$(jq '[.[]|select(.state=="open")]|length' <<<"$gh_out")" "github: 1 open blocker"  || exit 1
assert_eq "1" "$(jq '[.[]|select(.state=="open")]|length' <<<"$fj_out")" "forgejo: 1 open blocker" || exit 1

# Neutrality: the two backends produce an identical neutral shape (drop host-specific url).
gh_norm=$(jq -cS 'map(del(.url))' <<<"$gh_out")
fj_norm=$(jq -cS 'map(del(.url))' <<<"$fj_out")
assert_eq "$gh_norm" "$fj_norm" "read_deps is neutral across forges" || exit 1

# The Forgejo edge carries cross-repo target + state natively (no prose parse).
assert_eq "squirrlylabs/sluice" "$(jq -r '.[0].repository' <<<"$fj_out")" "forgejo: repository on edge" || exit 1

echo "test_blacksmith_read_deps: PASS"
