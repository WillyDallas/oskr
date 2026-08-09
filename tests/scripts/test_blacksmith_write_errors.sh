#!/usr/bin/env bash
# Write-helper error discrimination (#118): forge write verbs must tolerate ONLY
# the benign conflict for their endpoint (already-exists / already-absent) and
# fail LOUDLY on everything else — the old `>/dev/null 2>&1 || true` made a
# failed write indistinguishable from a successful one. Also proves the
# ensure-then-attach contract: Forgejo's attach-by-name endpoint silently drops
# unknown names with HTTP 200 (verified live on Forgejo 15.0.3), so add_label /
# create_issue / move_issue must guarantee label existence before attaching.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB="$REPO_ROOT/bin/harness-lib.sh"
FIX="$REPO_ROOT/tests/scripts/fixtures"
source "$SCRIPT_DIR/lib/assert.sh"

SHIM_DIR=$(mktemp -d); trap 'rm -rf "$SHIM_DIR"' EXIT
cp "$SCRIPT_DIR/lib/gh-shim.sh"   "$SHIM_DIR/gh";   chmod +x "$SHIM_DIR/gh"
cp "$SCRIPT_DIR/lib/curl-shim.sh" "$SHIM_DIR/curl"; chmod +x "$SHIM_DIR/curl"

# Repo-labels fixture: what "already exists" on the forge for the ensure step.
REPO_LABELS="$SHIM_DIR/repo-labels.json"
printf '%s' '[{"id":30,"name":"existing-label"},{"id":31,"name":"status/backlog"}]' > "$REPO_LABELS"

fj_run() {  # $1 = call log, $2 = verb expression (extra CURL_SHIM_* via env)
  PATH="$SHIM_DIR:$PATH" HARNESS_CONFIG="$FIX/harness-config.forgejo.json" FORGEJO_TOKEN="test-token" \
  CURL_SHIM_CALL_LOG="$1" CURL_SHIM_REPO_LABELS_FIXTURE="$REPO_LABELS" \
  CURL_SHIM_ISSUE_LABELS_FIXTURE="$FIX/forgejo-issue-labels.json" \
  bash -c "source '$LIB'; $2"
}
gh_run() {  # $1 = call log, $2 = verb expression (extra GH_SHIM_* via env)
  PATH="$SHIM_DIR:$PATH" HARNESS_CONFIG="$FIX/harness-config.sample.json" \
  GH_SHIM_CALL_LOG="$1" GH_SHIM_FIXTURE="$FIX/gh-project-discovery.json" \
  bash -c "source '$LIB'; $2"
}

# --- Forgejo: issue_add_label -------------------------------------------------

# Label already on the repo -> NO create POST (get-then-create short-circuits), attach runs, rc 0.
L="$SHIM_DIR/a1.log"; : > "$L"
fj_run "$L" "blacksmith_issue_add_label 61 existing-label"
grep -qF '/issues/61/labels' "$L"          || { echo "FAIL: add_label did not attach" >&2; exit 1; }
grep -qF '"name":"existing-label"' "$L"    && { echo "FAIL: add_label re-created an existing label (duplicate mint)" >&2; exit 1; }

# Label missing from the repo -> ensured (create POST) BEFORE the attach, rc 0.
L="$SHIM_DIR/a2.log"; : > "$L"
fj_run "$L" "blacksmith_issue_add_label 61 area/brand-new"
grep -qF '"name":"area/brand-new"' "$L"    || { echo "FAIL: add_label did not ensure a missing label" >&2; exit 1; }
grep -qF '{"labels":["area/brand-new"]}' "$L" || { echo "FAIL: add_label did not attach after ensure" >&2; exit 1; }

# Attach fails (HTTP 500) -> loud rc 1, and the error names the verb.
L="$SHIM_DIR/a3.log"; : > "$L"
rc=0; err=$(CURL_SHIM_ISSUE_LABELS_STATUS=500 fj_run "$L" "blacksmith_issue_add_label 61 existing-label" 2>&1) || rc=$?
assert_eq 1 "$rc" "fj add_label: HTTP 500 on attach is loud" || exit 1
grep -qF 'issue_add_label' <<<"$err"       || { echo "FAIL: add_label failure did not name the verb: $err" >&2; exit 1; }

# --- Forgejo: ensure_label ----------------------------------------------------

# Create loses a race (422) -> benign, rc 0.
L="$SHIM_DIR/e1.log"; : > "$L"
CURL_SHIM_REPO_LABELS_STATUS=422 fj_run "$L" "blacksmith_ensure_label zz-new '' 888888"
# Create fails for real (500) -> loud rc 1.
L="$SHIM_DIR/e2.log"; : > "$L"
rc=0; CURL_SHIM_REPO_LABELS_STATUS=500 fj_run "$L" "blacksmith_ensure_label zz-new '' 888888" 2>/dev/null || rc=$?
assert_eq 1 "$rc" "fj ensure_label: HTTP 500 is loud" || exit 1

# --- Forgejo: issue_remove_label / DELETE benign-vs-real ----------------------

# 422 on the DELETE (label vanished after the id resolve) -> benign no-op, rc 0.
L="$SHIM_DIR/r1.log"; : > "$L"
CURL_SHIM_ISSUE_LABELS_STATUS=422 fj_run "$L" "blacksmith_issue_remove_label 61 dispatch-incomplete"
# 500 -> loud rc 1.
L="$SHIM_DIR/r2.log"; : > "$L"
rc=0; CURL_SHIM_ISSUE_LABELS_STATUS=500 fj_run "$L" "blacksmith_issue_remove_label 61 dispatch-incomplete" 2>/dev/null || rc=$?
assert_eq 1 "$rc" "fj remove_label: HTTP 500 is loud" || exit 1

# --- Forgejo: issue_comment ---------------------------------------------------

L="$SHIM_DIR/c1.log"; : > "$L"
fj_run "$L" "blacksmith_issue_comment 61 'hello'"
L="$SHIM_DIR/c2.log"; : > "$L"
rc=0; CURL_SHIM_COMMENTS_STATUS=500 fj_run "$L" "blacksmith_issue_comment 61 'hello'" 2>/dev/null || rc=$?
assert_eq 1 "$rc" "fj issue_comment: HTTP 500 is loud" || exit 1

# --- Forgejo: create_issue label attach is loud and names the created issue ---

L="$SHIM_DIR/ci.log"; : > "$L"
rc=0; err=$(CURL_SHIM_CREATE_FIXTURE="$FIX/forgejo-create-issue.json" CURL_SHIM_ISSUE_LABELS_STATUS=500 \
  fj_run "$L" "blacksmith_create_issue 'T' 'B'" 2>&1) || rc=$?
assert_eq 1 "$rc" "fj create_issue: failed label attach is loud" || exit 1
grep -qF '#2' <<<"$err" || { echo "FAIL: create_issue failure did not name the created issue: $err" >&2; exit 1; }

# --- Forgejo: move_issue ensures the status label before attaching ------------

L="$SHIM_DIR/mv.log"; : > "$L"
fj_run "$L" "blacksmith_move_issue 61 ready"
grep -qF '"name":"status/ready"' "$L" || { echo "FAIL: move_issue did not ensure a missing status label" >&2; exit 1; }
grep -qF '"exclusive":true' "$L"      || { echo "FAIL: move_issue minted a non-exclusive status label" >&2; exit 1; }
grep -qF '{"labels":["status/ready"]}' "$L" || { echo "FAIL: move_issue did not attach the status label" >&2; exit 1; }

# --- GitHub: issue_add_label --------------------------------------------------

# Happy path: ensure (label create) precedes the attach (issue edit), rc 0.
L="$SHIM_DIR/g1.log"; : > "$L"
gh_run "$L" "blacksmith_issue_add_label 61 area/brand-new"
grep -qF 'label create area/brand-new' "$L" || { echo "FAIL: gh add_label did not ensure the label" >&2; exit 1; }
grep -qF 'issue edit 61' "$L"               || { echo "FAIL: gh add_label did not edit the issue" >&2; exit 1; }

# "already exists" from label create -> benign; the attach still runs, rc 0.
L="$SHIM_DIR/g2.log"; : > "$L"
GH_SHIM_LABEL_CREATE_ERR="label 'x' already exists; use \`--force\` to update" \
  gh_run "$L" "blacksmith_issue_add_label 61 area/brand-new"
grep -qF 'issue edit 61' "$L" || { echo "FAIL: gh add_label stopped on the benign exists conflict" >&2; exit 1; }

# Any other label-create error -> loud rc 1.
rc=0; GH_SHIM_LABEL_CREATE_ERR="HTTP 403: forbidden" \
  gh_run "$SHIM_DIR/g3.log" "blacksmith_issue_add_label 61 area/brand-new" 2>/dev/null || rc=$?
assert_eq 1 "$rc" "gh add_label: non-exists create failure is loud" || exit 1

# Attach (issue edit) failure -> loud rc 1.
rc=0; GH_SHIM_ISSUE_EDIT_ERR="failed to update: label not found" \
  gh_run "$SHIM_DIR/g4.log" "blacksmith_issue_add_label 61 area/brand-new" 2>/dev/null || rc=$?
assert_eq 1 "$rc" "gh add_label: attach failure is loud" || exit 1

# --- GitHub: issue_comment / issue_remove_label -------------------------------

rc=0; GH_SHIM_ISSUE_COMMENT_ERR="HTTP 502" \
  gh_run "$SHIM_DIR/g5.log" "blacksmith_issue_comment 61 'hi'" 2>/dev/null || rc=$?
assert_eq 1 "$rc" "gh issue_comment: failure is loud" || exit 1

# Absent label (HTTP 404) -> benign no-op, rc 0.
GH_SHIM_API_DELETE_ERR="gh: Not Found (HTTP 404)" \
  gh_run "$SHIM_DIR/g6.log" "blacksmith_issue_remove_label 61 dispatch-incomplete"
# Real failure -> loud rc 1.
rc=0; GH_SHIM_API_DELETE_ERR="gh: Internal Server Error (HTTP 500)" \
  gh_run "$SHIM_DIR/g7.log" "blacksmith_issue_remove_label 61 dispatch-incomplete" 2>/dev/null || rc=$?
assert_eq 1 "$rc" "gh remove_label: HTTP 500 is loud" || exit 1

# Scoped names ride in the URL path -> percent-encoded (a raw slash 404s the route).
L="$SHIM_DIR/g8.log"; : > "$L"
gh_run "$L" "blacksmith_issue_remove_label 61 type/umbrella"
grep -qF 'labels/type%2Fumbrella' "$L" || { echo "FAIL: gh remove_label did not percent-encode the scoped name" >&2; exit 1; }

echo "test_blacksmith_write_errors: PASS"
