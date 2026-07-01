#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"

DOCTOR="$REPO_ROOT/bin/doctor.sh"

# --- Fixture env: a cache-rooted "installed" copy + a "dev" checkout. ---------
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
CACHE="$TMP/.claude/plugins/cache"
INSTALLED="$CACHE/oskr/0.3.5/bin"
DEV="$TMP/projects/oskr/bin"
mkdir -p "$INSTALLED" "$DEV"
# harness-lib.sh is the signature file that marks a dir as an oskr bin/ dir.
touch "$INSTALLED/harness-lib.sh" "$DEV/harness-lib.sh"

# Test 1: a cache-rooted plugin root classifies as "installed".
out=$(source "$DOCTOR" && oskr_doctor_classify "$CACHE/oskr/0.3.5" "$CACHE")
assert_eq "installed" "$out" "classify installed"

# Test 2: a dev checkout classifies as "dev".
out=$(source "$DOCTOR" && oskr_doctor_classify "$TMP/projects/oskr" "$CACHE")
assert_eq "dev" "$out" "classify dev"

# Test 3: one oskr bin dir on PATH -> count 1 (no collision).
out=$(source "$DOCTOR" && oskr_doctor_path_copies "$DEV:/usr/bin:/bin" "harness-lib.sh")
assert_eq "1" "$out" "single copy count"

# Test 4: both copies on PATH -> count 2 (the double-enable condition).
out=$(source "$DOCTOR" && oskr_doctor_path_copies "$DEV:$INSTALLED:/usr/bin" "harness-lib.sh")
assert_eq "2" "$out" "double-enable count"

# Test 5: main warns + exits non-zero on a double-enable collision (PATH has both copies).
collision_out=$(
  CLAUDE_PLUGIN_ROOT="$TMP/projects/oskr" \
  OSKR_DOCTOR_CACHE_ROOT="$CACHE" \
  PATH="$DEV:$INSTALLED:/usr/bin:/bin" \
  bash "$DOCTOR" 2>&1
) && { echo "FAIL: doctor should exit non-zero on collision" >&2; exit 1; } || true
grep -qF "double-enable collision" <<<"$collision_out" \
  || { echo "FAIL: collision message missing" >&2; echo "$collision_out" >&2; exit 1; }

# Test 6: main reports the active DEV copy + exits 0 when only one copy is enabled.
single_out=$(
  CLAUDE_PLUGIN_ROOT="$TMP/projects/oskr" \
  OSKR_DOCTOR_CACHE_ROOT="$CACHE" \
  PATH="$DEV:/usr/bin:/bin" \
  bash "$DOCTOR" 2>&1
)
grep -qF "active copy:  dev" <<<"$single_out" \
  || { echo "FAIL: expected dev active-copy line" >&2; echo "$single_out" >&2; exit 1; }

# Test 7: main reports the active INSTALLED copy.
inst_out=$(
  CLAUDE_PLUGIN_ROOT="$CACHE/oskr/0.3.5" \
  OSKR_DOCTOR_CACHE_ROOT="$CACHE" \
  PATH="$INSTALLED:/usr/bin:/bin" \
  bash "$DOCTOR" 2>&1
)
grep -qF "active copy:  installed" <<<"$inst_out" \
  || { echo "FAIL: expected installed active-copy line" >&2; echo "$inst_out" >&2; exit 1; }

echo "test_doctor: PASS"
