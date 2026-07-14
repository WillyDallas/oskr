#!/usr/bin/env bash
# Opt-in LIVE smoke for the Forgejo backend — the #26 acceptance gate, extended
# in #104 to the delivery verbs #101 added. Drives a full onboarding round-trip
# against a real Forgejo instance entirely through the public blacksmith verbs
# (so it exercises forge dispatch, not the impls directly): repo create -> board
# provision -> issue create/move/view/label-remove/close -> PR create/probe/
# list-merged.
#
# NOT part of the hermetic CI suite: it needs network, a PAT, and permission to
# create+delete a repo. Every verb here is curl-shim-proven hermetically in the
# tests/ suite; THIS live round-trip against a real Forgejo is their acceptance
# gate and is deferred to the onboarding Area (#29). The run creates its own
# throwaway repo and DELETES it on success, so a green run leaves nothing behind;
# a FAILED run keeps the repo for inspection.
#
# Run:
#   set -a; . ~/WillyDev/squirrlylabs/.env; set +a   # loads FORGEJO_TOKEN
#   bin/smoke/forgejo-roundtrip.sh
# Config via env (defaults shown):
#   FORGEJO_BASE_URL=https://git.squirrlylabs.xyz
#   FORGEJO_SMOKE_OWNER=squirrlylabs
#   FORGEJO_SMOKE_REPO=blacksmith-smoke-<epoch>   # must NOT already exist
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../harness-lib.sh"

: "${FORGEJO_TOKEN:?set FORGEJO_TOKEN first (e.g. source your workspace .env)}"
BASE="${FORGEJO_BASE_URL:-https://git.squirrlylabs.xyz}"
OWNER="${FORGEJO_SMOKE_OWNER:-squirrlylabs}"
REPO="${FORGEJO_SMOKE_REPO:-blacksmith-smoke-$(date +%s)}"
BASE_BRANCH=main
HEAD_BRANCH=smoke-pr

CFG=$(mktemp); export HARNESS_CONFIG="$CFG"
cat > "$CFG" <<JSON
{ "name": "$REPO", "forge": "forgejo",
  "forgejo": { "base_url": "$BASE", "owner": "$OWNER", "repo": "$REPO" },
  "workflow": { "kind": "delivery-8col", "column_names": {}, "actionable_columns": ["ready"] } }
JSON

# Keep the repo on failure (for inspection); delete only after a clean PASS.
KEEP_REPO=1
cleanup() {
  # Delete the repo BEFORE removing $CFG — _blacksmith_forgejo_curl re-reads
  # base_url from the config file, so it must still exist at delete time.
  if [[ "$KEEP_REPO" == 0 ]]; then
    if _blacksmith_forgejo_curl DELETE "/repos/${OWNER}/${REPO}" >/dev/null 2>&1; then
      echo "  ok  throwaway repo ${OWNER}/${REPO} deleted"
    else
      echo "  ..  could not delete ${OWNER}/${REPO} (delete it by hand)" >&2
    fi
  else
    echo "  !!  FAILED — repo ${OWNER}/${REPO} left for inspection" >&2
  fi
  rm -f "$CFG"
}
trap cleanup EXIT

ok(){ echo "  ok  $1"; }
no(){ echo "  XX  $1" >&2; exit 1; }
eq(){ [[ "$1" == "$2" ]] || no "$3 (expected '$1', got '$2')"; ok "$3"; }

# Raw Forgejo plumbing used ONLY to seed git objects a PR needs (test
# scaffolding, not a verb under test). Commits <content> to <path> on <branch>,
# optionally branching a NEW branch off it.
seed_commit() {
  local path="$1" msg="$2" branch="$3" new_branch="${4:-}" content b64 payload
  content="seed $(date +%s%N)"
  b64=$(printf '%s\n' "$content" | base64 | tr -d '\n')
  payload=$(jq -nc --arg c "$b64" --arg m "$msg" --arg b "$branch" --arg nb "$new_branch" \
    'if $nb == "" then {content:$c, message:$m, branch:$b}
     else {content:$c, message:$m, branch:$b, new_branch:$nb} end')
  _blacksmith_forgejo_curl POST "/repos/${OWNER}/${REPO}/contents/${path}" "$payload" >/dev/null
}

echo "blacksmith Forgejo live smoke -> $OWNER/$REPO @ $BASE"
eq forgejo "$(_blacksmith_forge)" "dispatch = forgejo"

# --- repo create (verb) ------------------------------------------------------
blacksmith_repo_create "$OWNER" "$REPO" >/dev/null && ok "repo_create -> $OWNER/$REPO" \
  || no "blacksmith_repo_create failed"

blacksmith_provision_board && ok "board provisioned (8 status + taxonomy, exclusive labels)" \
  || no "blacksmith_provision_board failed"

# --- issue create / move / board (existing coverage) -------------------------
p=$(jq -r '.number'  <<<"$(blacksmith_create_issue 'smoke parent'  'umbrella')")
c1=$(jq -r '.number' <<<"$(blacksmith_create_issue 'smoke child 1' 'child')")
c2=$(jq -r '.number' <<<"$(blacksmith_create_issue 'smoke child 2' 'child')")
ok "created parent #$p, children #$c1 #$c2"

eq Backlog "$(blacksmith_issue_status "$c1")" "create seeds status Backlog"
blacksmith_move_issue "$c1" ready
eq Ready "$(blacksmith_issue_status "$c1")" "move -> Ready (exclusive label swap)"

blacksmith_issue_comment "$c1" "blacksmith smoke comment"; ok "comment posted"
eq "[]" "$(blacksmith_read_deps "$c1")" "read_deps -> [] (no blockers)"

blacksmith_link_parent "$p" "$c1"
blacksmith_link_parent "$p" "$c2"
kids=$(blacksmith_list_children "$p")
eq 2     "$(jq 'length'        <<<"$kids")" "list_children -> 2"
eq "$c1" "$(jq -r '.[0].number' <<<"$kids")" "list_children first = #$c1"

board=$(blacksmith_list_board)
[[ "$(jq '.total' <<<"$board")" -ge 3 ]] || no "list_board total < 3"
ok "list_board total=$(jq '.total' <<<"$board")"
eq Ready "$(jq -r --argjson n "$c1" '.items[] | select(.number==$n) | .status' <<<"$board")" "list_board status synthesized"

[[ "$(blacksmith_count_actionable)" -ge 1 ]] || no "count_actionable < 1"
ok "count_actionable=$(blacksmith_count_actionable)"

# --- issue view / remove-label / close (verbs; #101) -------------------------
view=$(blacksmith_issue_view "$c1")
eq "smoke child 1" "$(jq -r '.title' <<<"$view")" "issue_view title"
eq "open"          "$(jq -r '.state' <<<"$view")" "issue_view state open"
[[ "$(jq -r '.comments[0]' <<<"$view")" == "blacksmith smoke comment" ]] \
  || no "issue_view did not surface the comment"
ok "issue_view surfaces comment"
[[ "$(jq -r '.labels | index("status/ready")' <<<"$view")" != "null" ]] \
  || no "issue_view labels missing status/ready"
ok "issue_view labels include status/ready"

blacksmith_issue_remove_label "$c1" status/ready
view=$(blacksmith_issue_view "$c1")
eq "null" "$(jq -r '.labels | index("status/ready")' <<<"$view")" "issue_remove_label dropped status/ready"

blacksmith_issue_close "$c2"
eq "closed" "$(jq -r '.state' <<<"$(blacksmith_issue_view "$c2")")" "issue_close -> state closed"

# --- PR create / open-probe / list-merged (verbs; #101) ----------------------
# Seed a base branch with a commit, then a head branch one commit ahead.
seed_commit README.md        "seed base" "$BASE_BRANCH";                ok "seeded $BASE_BRANCH"
seed_commit smoke-change.txt "seed head" "$BASE_BRANCH" "$HEAD_BRANCH"; ok "seeded $HEAD_BRANCH (ahead of $BASE_BRANCH)"

! blacksmith_pr_open_exists "$HEAD_BRANCH" "$BASE_BRANCH" \
  && ok "pr_open_exists -> false before create" || no "pr_open_exists true before any PR"

pr=$(blacksmith_pr_create "$HEAD_BRANCH" "$BASE_BRANCH" "smoke PR" "opened by the live gate")
prn=$(jq -r '.number' <<<"$pr")
[[ -n "$prn" && "$prn" != null ]] || no "pr_create returned no number"
ok "pr_create -> PR #$prn"

blacksmith_pr_open_exists "$HEAD_BRANCH" "$BASE_BRANCH" \
  && ok "pr_open_exists -> true after create" || no "pr_open_exists false after create"

eq "[]" "$(blacksmith_pr_list_merged "$BASE_BRANCH")" "pr_list_merged -> [] before merge"

# Merge it (raw scaffolding) so list_merged has something to report. Forgejo
# computes mergeability asynchronously, so poll until the PR reports mergeable
# before asking to merge (each GET's network latency paces the loop — no sleep).
mergeable=false
for _ in $(seq 1 30); do
  if [[ "$(_blacksmith_forgejo_curl GET "/repos/${OWNER}/${REPO}/pulls/${prn}" 2>/dev/null | jq -r '.mergeable')" == true ]]; then
    mergeable=true; break
  fi
done
[[ "$mergeable" == true ]] || no "PR #$prn never became mergeable"
_blacksmith_forgejo_curl POST "/repos/${OWNER}/${REPO}/pulls/${prn}/merge" \
  "$(jq -nc '{Do:"merge"}')" >/dev/null && ok "PR #$prn merged" || no "could not merge PR #$prn"

merged=$(blacksmith_pr_list_merged "$BASE_BRANCH")
eq "$prn" "$(jq -r --arg h "$HEAD_BRANCH" 'map(select(.headBranch==$h))[0].number' <<<"$merged")" \
  "pr_list_merged lists merged PR #$prn"

! blacksmith_pr_open_exists "$HEAD_BRANCH" "$BASE_BRANCH" \
  && ok "pr_open_exists -> false after merge" || no "pr_open_exists still true after merge"

# --- archive (existing coverage) ---------------------------------------------
blacksmith_archive_item "$c1"
eq "" "$(blacksmith_issue_status "$c1")" "archive -> uncolumned"

KEEP_REPO=0
echo "forgejo-roundtrip: PASS"
