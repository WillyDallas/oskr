#!/usr/bin/env bash
# blacksmith_count_issues (#27 T6): forge-dispatched count of EXISTING issues for
# the adopt consent gate. GitHub excludes PRs (the REST issues list interleaves
# them); Forgejo's ?type=issues already excludes them. Hermetic via gh/curl shims.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB="$REPO_ROOT/bin/harness-lib.sh"
FIX="$REPO_ROOT/tests/scripts/fixtures"
source "$SCRIPT_DIR/lib/assert.sh"

SHIM_DIR=$(mktemp -d); CACHE_DIR=$(mktemp -d)
trap 'rm -rf "$SHIM_DIR" "$CACHE_DIR"' EXIT
cp "$SCRIPT_DIR/lib/gh-shim.sh" "$SHIM_DIR/gh"; chmod +x "$SHIM_DIR/gh"
LOG="$SHIM_DIR/gh.log"; : > "$LOG"

gh_count() {
  PATH="$SHIM_DIR:$PATH" \
    HARNESS_CONFIG="$FIX/harness-config.sample.json" \
    GH_SHIM_CALL_LOG="$LOG" \
    GH_SHIM_FIXTURE="$FIX/gh-project-discovery.json" \
    GH_SHIM_ISSUES_FIXTURE="$1" \
    XDG_CACHE_HOME="$CACHE_DIR" \
    bash -c "source '$LIB'; blacksmith_count_issues"
}

# GitHub: two issues + one PR -> 2 (PR excluded).
assert_eq "2" "$(gh_count "$FIX/gh-issues-list.json")"  "github count excludes PRs" || exit 1
# GitHub: empty list -> 0 (the empty-repo adopt path: no prompt).
assert_eq "0" "$(gh_count "$FIX/gh-issues-empty.json")" "github count empty -> 0"   || exit 1

# --- Forgejo (curl-shim) ---------------------------------------------------
CSHIM_DIR=$(mktemp -d); trap 'rm -rf "$SHIM_DIR" "$CACHE_DIR" "$CSHIM_DIR"' EXIT
cp "$SCRIPT_DIR/lib/curl-shim.sh" "$CSHIM_DIR/curl"; chmod +x "$CSHIM_DIR/curl"
CLOG="$CSHIM_DIR/curl.log"; : > "$CLOG"

fj_count() {
  PATH="$CSHIM_DIR:$PATH" \
    HARNESS_CONFIG="$FIX/harness-config.forgejo.json" \
    FORGEJO_TOKEN="test-token" \
    CURL_SHIM_CALL_LOG="$CLOG" \
    CURL_SHIM_LIST_FIXTURE="$1" \
    bash -c "source '$LIB'; blacksmith_count_issues"
}

# Forgejo: the 2-issue list fixture -> 2.
assert_eq "2" "$(fj_count "$FIX/forgejo-issues-list.json")" "forgejo count -> 2" || exit 1
# Forgejo: no list fixture -> shim returns [] -> 0.
assert_eq "0" "$(fj_count "")"                              "forgejo count empty -> 0" || exit 1

echo "test_blacksmith_count_issues: PASS"
