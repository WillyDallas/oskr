#!/usr/bin/env bash
# blacksmith_list_issues (adopt harvest read primitive): list ALL repo issues
# (open+closed; PRs excluded) as the neutral [ {number,title,state,body,labels} ]
# array, on both forges. The off-board backlog source for full-migration adopt.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB="$REPO_ROOT/bin/harness-lib.sh"
FIX="$REPO_ROOT/tests/scripts/fixtures"
source "$SCRIPT_DIR/lib/assert.sh"

SHIM_DIR=$(mktemp -d); trap 'rm -rf "$SHIM_DIR"' EXIT
cp "$SCRIPT_DIR/lib/gh-shim.sh"   "$SHIM_DIR/gh";   chmod +x "$SHIM_DIR/gh"
cp "$SCRIPT_DIR/lib/curl-shim.sh" "$SHIM_DIR/curl"; chmod +x "$SHIM_DIR/curl"

# --- GitHub: all issues, PRs filtered ---
LOG="$SHIM_DIR/gh.log"; : > "$LOG"
out=$(PATH="$SHIM_DIR:$PATH" \
  HARNESS_CONFIG="$FIX/harness-config.sample.json" \
  GH_SHIM_CALL_LOG="$LOG" \
  GH_SHIM_FIXTURE="$FIX/gh-existing-issues.json" \
  bash -c "source '$LIB'; blacksmith_list_issues")

assert_eq "2"  "$(jq 'length' <<<"$out")"            "github: PRs filtered, 2 issues" || exit 1
assert_eq "12" "$(jq -r '.[0].number' <<<"$out")"    "github: first issue number"     || exit 1
assert_eq "open"   "$(jq -r '.[0].state' <<<"$out")" "github: first issue state"      || exit 1
assert_eq '["bug"]' "$(jq -c '.[0].labels' <<<"$out")" "github: labels normalized to names" || exit 1
if jq -e '.[] | select(.number==5)' <<<"$out" >/dev/null; then echo "FAIL: PR #5 not filtered" >&2; exit 1; fi
grep -qF 'issues?state=all' "$LOG" || { echo "FAIL: did not list all repo issues" >&2; exit 1; }

# --- Forgejo: same neutral shape from the gitea issues list ---
LOG2="$SHIM_DIR/curl.log"; : > "$LOG2"
fout=$(PATH="$SHIM_DIR:$PATH" \
  HARNESS_CONFIG="$FIX/harness-config.forgejo.json" \
  FORGEJO_TOKEN="test-token" \
  CURL_SHIM_CALL_LOG="$LOG2" \
  CURL_SHIM_LIST_FIXTURE="$FIX/forgejo-issues-list.json" \
  bash -c "source '$LIB'; blacksmith_list_issues")

assert_eq "2"  "$(jq 'length' <<<"$fout")"         "forgejo: 2 issues"      || exit 1
assert_eq "10" "$(jq -r '.[0].number' <<<"$fout")" "forgejo: first number"  || exit 1
grep -qF 'type=issues' "$LOG2" || { echo "FAIL: forgejo must request type=issues (exclude PRs)" >&2; exit 1; }

echo "test_blacksmith_list_issues: PASS"
