#!/usr/bin/env bash
# blacksmith_base_branch — resolve a task's PR base: the Area branch recorded on
# its umbrella PRD ("Area branch: <b>"), else config .base_branch (default main).
# Own-body + fallback are covered here on BOTH forges; the parent-walk is
# live-validated against the real tree in the build (the single-fixture shims
# can't return two different issue bodies in one run).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/lib/assert.sh"

SHIM_DIR=$(mktemp -d)
trap 'rm -rf "$SHIM_DIR"' EXIT
cp "$SCRIPT_DIR/lib/gh-shim.sh"   "$SHIM_DIR/gh";   chmod +x "$SHIM_DIR/gh"
cp "$SCRIPT_DIR/lib/curl-shim.sh" "$SHIM_DIR/curl"; chmod +x "$SHIM_DIR/curl"
: > "$SHIM_DIR/calls.log"

GHCFG="$REPO_ROOT/tests/scripts/fixtures/harness-config.sample.json"
FJCFG="$REPO_ROOT/tests/scripts/fixtures/harness-config.forgejo.json"
AB="$REPO_ROOT/tests/scripts/fixtures/fixture-issue-areabranch.json"
PLAIN="$REPO_ROOT/tests/scripts/fixtures/fixture-issue-plain.json"
GH_DEFAULT=$(jq -r '.base_branch // "main"' "$GHCFG")
FJ_DEFAULT=$(jq -r '.base_branch // "main"' "$FJCFG")

# GitHub: own-body hit — the issue's own PRD carries the Area branch.
out=$(PATH="$SHIM_DIR:$PATH" HARNESS_CONFIG="$GHCFG" GH_SHIM_CALL_LOG="$SHIM_DIR/calls.log" \
  GH_SHIM_FIXTURE="$AB" bash -c "set -euo pipefail; source '$REPO_ROOT/bin/harness-lib.sh'; blacksmith_base_branch 43")
assert_eq "WillyDallas/area-x" "$out" "github: own-body Area branch" || exit 1

# GitHub: fallback — no Area branch anywhere → the configured default base.
out=$(PATH="$SHIM_DIR:$PATH" HARNESS_CONFIG="$GHCFG" GH_SHIM_CALL_LOG="$SHIM_DIR/calls.log" \
  GH_SHIM_FIXTURE="$PLAIN" bash -c "set -euo pipefail; source '$REPO_ROOT/bin/harness-lib.sh'; blacksmith_base_branch 99")
assert_eq "$GH_DEFAULT" "$out" "github: fallback to default base" || exit 1

# Forgejo: own-body hit.
out=$(PATH="$SHIM_DIR:$PATH" HARNESS_CONFIG="$FJCFG" CURL_SHIM_CALL_LOG="$SHIM_DIR/calls.log" \
  CURL_SHIM_ISSUE_FIXTURE="$AB" FORGEJO_TOKEN="test-token" bash -c "set -euo pipefail; source '$REPO_ROOT/bin/harness-lib.sh'; blacksmith_base_branch 43")
assert_eq "WillyDallas/area-x" "$out" "forgejo: own-body Area branch" || exit 1

# Forgejo: fallback.
out=$(PATH="$SHIM_DIR:$PATH" HARNESS_CONFIG="$FJCFG" CURL_SHIM_CALL_LOG="$SHIM_DIR/calls.log" \
  CURL_SHIM_ISSUE_FIXTURE="$PLAIN" FORGEJO_TOKEN="test-token" bash -c "set -euo pipefail; source '$REPO_ROOT/bin/harness-lib.sh'; blacksmith_base_branch 99")
assert_eq "$FJ_DEFAULT" "$out" "forgejo: fallback to default base" || exit 1

echo "test_blacksmith_base_branch: PASS"
