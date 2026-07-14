#!/usr/bin/env bash
# Issue delivery verbs (#101): issue_view / issue_close / issue_remove_label on
# both forges, hermetic via gh-shim + curl-shim. Asserts request shape + the
# neutral output contract only — never internals. Also proves the loud dispatch
# failure for a forge with no implementation.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB="$REPO_ROOT/bin/harness-lib.sh"
FIX="$REPO_ROOT/tests/scripts/fixtures"
source "$SCRIPT_DIR/lib/assert.sh"

SHIM_DIR=$(mktemp -d); trap 'rm -rf "$SHIM_DIR"' EXIT
cp "$SCRIPT_DIR/lib/gh-shim.sh"   "$SHIM_DIR/gh";   chmod +x "$SHIM_DIR/gh"
cp "$SCRIPT_DIR/lib/curl-shim.sh" "$SHIM_DIR/curl"; chmod +x "$SHIM_DIR/curl"

gh_run() {  # $1 = call log, $2 = verb expression
  PATH="$SHIM_DIR:$PATH" HARNESS_CONFIG="$FIX/harness-config.sample.json" \
  GH_SHIM_CALL_LOG="$1" GH_SHIM_FIXTURE="$FIX/gh-project-discovery.json" \
  GH_SHIM_ISSUE_FIXTURE="$FIX/gh-issue-view.json" \
  GH_SHIM_COMMENTS_FIXTURE="$FIX/gh-issue-comments.json" \
  bash -c "source '$LIB'; $2"
}
fj_run() {  # $1 = call log, $2 = verb expression
  PATH="$SHIM_DIR:$PATH" HARNESS_CONFIG="$FIX/harness-config.forgejo.json" FORGEJO_TOKEN="test-token" \
  CURL_SHIM_CALL_LOG="$1" CURL_SHIM_ISSUE_FIXTURE="$FIX/forgejo-issue-view.json" \
  CURL_SHIM_COMMENTS_FIXTURE="$FIX/forgejo-issue-comments.json" \
  CURL_SHIM_ISSUE_LABELS_FIXTURE="$FIX/forgejo-issue-labels.json" \
  bash -c "source '$LIB'; $2"
}

# --- issue_view: GitHub -------------------------------------------------------
L="$SHIM_DIR/gh-view.log"; : > "$L"
out=$(gh_run "$L" "blacksmith_issue_view 61")
# The DoD-frozen minimum keys, asserted verbatim:
assert_eq 'Fix the widget'  "$(jq -r '.title' <<<"$out")"          "gh issue_view: title" || exit 1
assert_eq '## What
Fix it.' "$(jq -r '.body' <<<"$out")"                              "gh issue_view: body" || exit 1
assert_eq '["area/pipeline","dispatch-incomplete"]' "$(jq -c '.labels' <<<"$out")" "gh issue_view: labels are names" || exit 1
assert_eq '["## Research Digest\nfindings","## Implementation Plan\nplan"]' \
  "$(jq -c '.comments' <<<"$out")"                                "gh issue_view: comments are bodies" || exit 1
# The additive keys (clean-up classification + evidence link):
assert_eq 'closed'    "$(jq -r '.state' <<<"$out")"                "gh issue_view: state (REST lowercase)" || exit 1
assert_eq 'completed' "$(jq -r '.stateReason' <<<"$out")"          "gh issue_view: stateReason" || exit 1
assert_eq '61'        "$(jq -r '.number' <<<"$out")"               "gh issue_view: number" || exit 1
assert_eq 'https://github.com/WillyDallas/oskr/issues/61' "$(jq -r '.url' <<<"$out")" "gh issue_view: url" || exit 1
# Request shape: the issue read and the comments read.
grep -qE 'gh api repos/WillyDallas/oskr/issues/61( |$)' "$L" || { echo "FAIL: no issue GET" >&2; exit 1; }
grep -qF 'issues/61/comments' "$L" || { echo "FAIL: no comments GET" >&2; exit 1; }

# --- issue_view: Forgejo (same neutral shape; stateReason null) -----------------
L="$SHIM_DIR/fj-view.log"; : > "$L"
out=$(fj_run "$L" "blacksmith_issue_view 61")
assert_eq 'Fix the widget' "$(jq -r '.title' <<<"$out")"           "fj issue_view: title" || exit 1
assert_eq '["area/pipeline","dispatch-incomplete"]' "$(jq -c '.labels' <<<"$out")" "fj issue_view: labels" || exit 1
assert_eq '["## Research Digest\nfindings"]' \
  "$(jq -c '.comments' <<<"$out")"                                "fj issue_view: comments" || exit 1
assert_eq 'closed' "$(jq -r '.state' <<<"$out")"                   "fj issue_view: state" || exit 1
assert_eq 'null'   "$(jq -r '.stateReason' <<<"$out")"             "fj issue_view: stateReason null (no close reasons)" || exit 1
# Identical key set on both forges — the contract IS the shape.
assert_eq '["body","comments","labels","number","state","stateReason","title","url"]' \
  "$(jq -c 'keys' <<<"$out")" "fj issue_view: neutral key set" || exit 1
grep -qF '/repos/squirrlylabs/sluice/issues/61' "$L" || { echo "FAIL: no fj issue GET" >&2; exit 1; }
grep -qF '/issues/61/comments' "$L" || { echo "FAIL: no fj comments GET" >&2; exit 1; }

# --- issue_close ---------------------------------------------------------------
L="$SHIM_DIR/gh-close.log"; : > "$L"
gh_run "$L" "blacksmith_issue_close 61" >/dev/null
grep -qF 'issues/61' "$L" && grep -qF 'PATCH' "$L" || { echo "FAIL: gh close not a PATCH on the issue" >&2; exit 1; }
grep -qF 'state=closed' "$L"              || { echo "FAIL: gh close missing state=closed" >&2; exit 1; }
grep -qF 'state_reason=completed' "$L"    || { echo "FAIL: gh close missing default state_reason" >&2; exit 1; }
L="$SHIM_DIR/gh-close2.log"; : > "$L"
gh_run "$L" "blacksmith_issue_close 61 not_planned" >/dev/null
grep -qF 'state_reason=not_planned' "$L"  || { echo "FAIL: gh close reason arg not honored" >&2; exit 1; }

L="$SHIM_DIR/fj-close.log"; : > "$L"
fj_run "$L" "blacksmith_issue_close 61" >/dev/null
grep -qF 'PATCH' "$L" && grep -qF '/issues/61' "$L" || { echo "FAIL: fj close not a PATCH" >&2; exit 1; }
grep -qF '"state":"closed"' "$L"          || { echo "FAIL: fj close missing state body" >&2; exit 1; }

# --- issue_remove_label ----------------------------------------------------------
L="$SHIM_DIR/gh-rmlabel.log"; : > "$L"
gh_run "$L" "blacksmith_issue_remove_label 61 dispatch-incomplete" >/dev/null
grep -qF 'DELETE' "$L" && grep -qF 'issues/61/labels/dispatch-incomplete' "$L" \
  || { echo "FAIL: gh remove_label not a DELETE by name" >&2; exit 1; }

L="$SHIM_DIR/fj-rmlabel.log"; : > "$L"
fj_run "$L" "blacksmith_issue_remove_label 61 dispatch-incomplete" >/dev/null
# Forgejo removes BY LABEL ID: name resolved to id 12 off the fixture, then DELETE.
grep -qF 'DELETE' "$L" && grep -qF '/issues/61/labels/12' "$L" \
  || { echo "FAIL: fj remove_label did not resolve name->id 12 and DELETE" >&2; exit 1; }

# --- loud dispatch failure (missing impl) ----------------------------------------
UNKNOWN_CFG="$SHIM_DIR/harness-config.gitlab.json"
printf '{"forge":"gitlab"}' > "$UNKNOWN_CFG"
if HARNESS_CONFIG="$UNKNOWN_CFG" bash -c "source '$LIB'; blacksmith_issue_view 1" 2>"$SHIM_DIR/dispatch.err"; then
  echo "FAIL: issue_view dispatched for a forge with no implementation" >&2; exit 1
fi
grep -qF "has no implementation for 'issue_view'" "$SHIM_DIR/dispatch.err" \
  || { echo "FAIL: missing-impl error not loud" >&2; cat "$SHIM_DIR/dispatch.err" >&2; exit 1; }

echo "test_blacksmith_issue_ops: PASS"
