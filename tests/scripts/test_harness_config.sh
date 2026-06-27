#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"

# Test 1: resolve config from $PWD
HARNESS_CONFIG="$REPO_ROOT/tests/scripts/fixtures/harness-config.sample.json" \
  bash -c "source '$REPO_ROOT/bin/harness-lib.sh' && [[ \$(blacksmith_config_get '.github.owner') == 'WillyDallas' ]]"

# Test 2: missing config exits non-zero
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
TEST2_OUT=$(
  cd "$TMPDIR" && \
    HARNESS_CONFIG="" bash -c "source '$REPO_ROOT/bin/harness-lib.sh' && blacksmith_config_path" 2>&1 \
  || true
)
grep -qF "not in an oskr project" <<<"$TEST2_OUT"

# Test 3: malformed JSON propagates jq error
HARNESS_CONFIG="$REPO_ROOT/tests/scripts/fixtures/harness-config.malformed.json" \
  bash -c "source '$REPO_ROOT/bin/harness-lib.sh' && blacksmith_config_get '.github.owner'" 2>/dev/null \
  && { echo "FAIL: expected non-zero on malformed JSON"; exit 1; } || true

echo "test_blacksmith_config: PASS"
