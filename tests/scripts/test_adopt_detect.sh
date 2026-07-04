#!/usr/bin/env bash
# adopt-detect.sh (#27 T6): emits the consent-gate verdict for init's adopt mode.
# "existing <N>" => prompt the developer; "empty 0" => no prompt. Hermetic via gh-shim.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FIX="$REPO_ROOT/tests/scripts/fixtures"
source "$SCRIPT_DIR/lib/assert.sh"

SHIM_DIR=$(mktemp -d); CACHE_DIR=$(mktemp -d)
trap 'rm -rf "$SHIM_DIR" "$CACHE_DIR"' EXIT
cp "$SCRIPT_DIR/lib/gh-shim.sh" "$SHIM_DIR/gh"; chmod +x "$SHIM_DIR/gh"
LOG="$SHIM_DIR/gh.log"; : > "$LOG"

detect() {
  PATH="$SHIM_DIR:$PATH" \
    HARNESS_CONFIG="$FIX/harness-config.sample.json" \
    GH_SHIM_CALL_LOG="$LOG" \
    GH_SHIM_FIXTURE="$FIX/gh-project-discovery.json" \
    GH_SHIM_ISSUES_FIXTURE="$1" \
    XDG_CACHE_HOME="$CACHE_DIR" \
    "$REPO_ROOT/bin/adopt-detect.sh"
}

assert_eq "existing 2" "$(detect "$FIX/gh-issues-list.json")"  "existing issues -> prompt verdict" || exit 1
assert_eq "empty 0"    "$(detect "$FIX/gh-issues-empty.json")" "empty repo -> no-prompt verdict"  || exit 1

echo "test_adopt_detect: PASS"
