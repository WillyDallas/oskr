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

echo "test_doctor: PASS"
