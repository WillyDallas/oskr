#!/usr/bin/env bash
# PR delivery verbs (#101): pr_create / pr_list_merged / pr_open_exists on both
# forges, hermetic via gh-shim + curl-shim. Task 3 appends repo_create coverage.
# Asserts request shape + neutral output contract only — never internals.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB="$REPO_ROOT/bin/harness-lib.sh"
FIX="$REPO_ROOT/tests/scripts/fixtures"
source "$SCRIPT_DIR/lib/assert.sh"

SHIM_DIR=$(mktemp -d); trap 'rm -rf "$SHIM_DIR"' EXIT
cp "$SCRIPT_DIR/lib/gh-shim.sh"   "$SHIM_DIR/gh";   chmod +x "$SHIM_DIR/gh"
cp "$SCRIPT_DIR/lib/curl-shim.sh" "$SHIM_DIR/curl"; chmod +x "$SHIM_DIR/curl"

gh_run() {  # $1 = call log, $2 = pulls fixture, $3 = verb expression
  PATH="$SHIM_DIR:$PATH" HARNESS_CONFIG="$FIX/harness-config.sample.json" \
  GH_SHIM_CALL_LOG="$1" GH_SHIM_FIXTURE="$FIX/gh-project-discovery.json" \
  GH_SHIM_PULLS_FIXTURE="$2" \
  bash -c "source '$LIB'; $3"
}
fj_run() {  # $1 = call log, $2 = pulls fixture, $3 = verb expression
  PATH="$SHIM_DIR:$PATH" HARNESS_CONFIG="$FIX/harness-config.forgejo.json" FORGEJO_TOKEN="test-token" \
  CURL_SHIM_CALL_LOG="$1" CURL_SHIM_PULLS_FIXTURE="$2" \
  bash -c "source '$LIB'; $3"
}

# --- pr_create: GitHub ----------------------------------------------------------
L="$SHIM_DIR/gh-create.log"; : > "$L"
out=$(gh_run "$L" "$FIX/gh-pull-create.json" \
      "blacksmith_pr_create 'feature/61-widget' 'area/pipeline' 'Fix the widget' 'PR body'")
assert_eq '88' "$(jq -r '.number' <<<"$out")"                                "gh pr_create: number" || exit 1
assert_eq 'https://github.com/WillyDallas/oskr/pull/88' "$(jq -r '.url' <<<"$out")" "gh pr_create: url" || exit 1
assert_eq '["number","url"]' "$(jq -c 'keys' <<<"$out")"                     "gh pr_create: neutral keys only" || exit 1
grep -qF 'repos/WillyDallas/oskr/pulls' "$L"  || { echo "FAIL: gh pr_create wrong endpoint" >&2; exit 1; }
grep -qF 'head=feature/61-widget' "$L"        || { echo "FAIL: head not sent" >&2; exit 1; }
grep -qF 'base=area/pipeline' "$L"            || { echo "FAIL: base not sent" >&2; exit 1; }
grep -qF 'title=Fix the widget' "$L"          || { echo "FAIL: title not sent" >&2; exit 1; }
grep -qF 'body=PR body' "$L"                  || { echo "FAIL: body not sent" >&2; exit 1; }

# --- pr_create: Forgejo -----------------------------------------------------------
L="$SHIM_DIR/fj-create.log"; : > "$L"
out=$(fj_run "$L" "$FIX/forgejo-pull-create.json" \
      "blacksmith_pr_create 'feature/61-widget' 'area/pipeline' 'Fix the widget' 'PR body'")
assert_eq '88' "$(jq -r '.number' <<<"$out")"            "fj pr_create: number" || exit 1
assert_eq '["number","url"]' "$(jq -c 'keys' <<<"$out")" "fj pr_create: neutral keys only" || exit 1
grep -qF '/repos/squirrlylabs/sluice/pulls' "$L" || { echo "FAIL: fj pr_create wrong endpoint" >&2; exit 1; }
grep -qF '"head":"feature/61-widget"' "$L"       || { echo "FAIL: fj head not sent" >&2; exit 1; }
grep -qF '"base":"area/pipeline"' "$L"           || { echo "FAIL: fj base not sent" >&2; exit 1; }

# --- pr_list_merged: GitHub (server-side base filter; merged_at != null) ---------
L="$SHIM_DIR/gh-merged.log"; : > "$L"
out=$(gh_run "$L" "$FIX/gh-pulls-closed.json" "blacksmith_pr_list_merged 'area/pipeline'")
assert_eq '[{"number":71,"title":"Task 1","headBranch":"feature/61-widget"},{"number":73,"title":"Task 3","headBranch":"feature/63-seam"}]' \
  "$(jq -c '.' <<<"$out")" "gh pr_list_merged: merged-only neutral list" || exit 1
grep -qF 'pulls?base=area/pipeline&state=closed' "$L" || { echo "FAIL: gh merged-list request shape" >&2; exit 1; }

# --- pr_list_merged: Forgejo (client-side base filter; merged flag) ---------------
L="$SHIM_DIR/fj-merged.log"; : > "$L"
out=$(fj_run "$L" "$FIX/forgejo-pulls-closed.json" "blacksmith_pr_list_merged 'area/pipeline'")
assert_eq '[{"number":71,"title":"Task 1","headBranch":"feature/61-widget"}]' \
  "$(jq -c '.' <<<"$out")" "fj pr_list_merged: merged + base-filtered" || exit 1
grep -qF 'pulls?state=closed' "$L" || { echo "FAIL: fj merged-list request shape" >&2; exit 1; }

# --- pr_open_exists: probe semantics (rc 0 = exists, rc 1 = absent) ---------------
L="$SHIM_DIR/gh-open.log"; : > "$L"
gh_run "$L" "$FIX/gh-pulls-open.json" "blacksmith_pr_open_exists 'area/pipeline' 'main'" \
  || { echo "FAIL: gh pr_open_exists rc!=0 for an existing open PR" >&2; exit 1; }
# GitHub's head filter requires the owner: prefix.
grep -qF 'head=WillyDallas:area/pipeline' "$L" || { echo "FAIL: gh head filter missing owner: prefix" >&2; exit 1; }
grep -qF 'base=main' "$L" && grep -qF 'state=open' "$L" || { echo "FAIL: gh open-probe request shape" >&2; exit 1; }
EMPTY="$SHIM_DIR/empty.json"; printf '[]' > "$EMPTY"
if gh_run "$SHIM_DIR/gh-open2.log" "$EMPTY" "blacksmith_pr_open_exists 'area/pipeline' 'main'"; then
  echo "FAIL: gh pr_open_exists rc 0 with no open PR" >&2; exit 1
fi

fj_run "$SHIM_DIR/fj-open.log" "$FIX/forgejo-pulls-open.json" "blacksmith_pr_open_exists 'area/pipeline' 'main'" \
  || { echo "FAIL: fj pr_open_exists rc!=0 for an existing open PR" >&2; exit 1; }
if fj_run "$SHIM_DIR/fj-open2.log" "$EMPTY" "blacksmith_pr_open_exists 'area/pipeline' 'main'"; then
  echo "FAIL: fj pr_open_exists rc 0 with no open PR" >&2; exit 1
fi

echo "test_blacksmith_pr_ops: PASS"
