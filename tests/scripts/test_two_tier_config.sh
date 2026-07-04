#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"
LIB="$REPO_ROOT/bin/harness-lib.sh"

# Workspace whose global tier defines base_branch + a github.owner.
WS=$(cd "$(mktemp -d)" && pwd)
trap 'rm -rf "$WS"' EXIT
mkdir -p "$WS/.oskr" "$WS/projects/proj"
cp "$REPO_ROOT/tests/scripts/fixtures/oskr-config.global.json" "$WS/.oskr/config.json"
cat > "$WS/projects/proj/harness-config.json" <<'JSON'
{ "github": { "owner": "WillyDallas", "repo": "oskr", "project_number": 1 } }
JSON
PROJ="$WS/projects/proj/harness-config.json"

get() { # get <jq-path> -> stdout
  OSKR_WORKSPACE="$WS" HARNESS_CONFIG="$PROJ" \
    bash -c "source '$LIB' && blacksmith_config_get '$1'"
}

# Test 1: project value wins when both tiers define the key.
assert_eq "WillyDallas" "$(get '.github.owner')" "project wins over global"

# Test 2: key absent from project falls back to the global tier.
assert_eq "trunk" "$(get '.base_branch')" "absent key falls back to global"

# Test 3: key absent from BOTH tiers still fails (non-zero).
if OSKR_WORKSPACE="$WS" HARNESS_CONFIG="$PROJ" \
   bash -c "source '$LIB' && blacksmith_config_get '.nope.missing'" >/dev/null 2>&1; then
  echo "FAIL: key missing in both tiers should fail" >&2; exit 1
fi

# Test 4: regression — with no workspace/global, project-tier read is unchanged.
OUT=$(OSKR_WORKSPACE="" \
  HARNESS_CONFIG="$REPO_ROOT/tests/scripts/fixtures/harness-config.sample.json" \
  bash -c "cd / && source '$LIB' && blacksmith_config_get '.github.owner'")
assert_eq "WillyDallas" "$OUT" "project-tier read unchanged with no workspace"

echo "test_two_tier_config: PASS"
