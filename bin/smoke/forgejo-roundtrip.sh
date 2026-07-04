#!/usr/bin/env bash
# Opt-in LIVE smoke for the Forgejo backend — the #26 acceptance gate. Drives a
# full board round-trip against a real Forgejo repo entirely through the public
# blacksmith verbs (so it exercises forge dispatch, not the impls directly).
#
# NOT part of the hermetic CI suite: it needs network, a PAT, and a throwaway repo
# whose board is provisioned by `blacksmith_provision_board` (run below). That verb is
# curl-shim-proven hermetically in #27; THIS live round-trip against a real Forgejo is
# its acceptance gate and is deferred to Area 5. Each run leaves a few test issues
# behind — delete the repo to reset.
#
# Run:
#   set -a; . ~/WillyDev/squirrlylabs/.env; set +a   # loads FORGEJO_TOKEN
#   bin/smoke/forgejo-roundtrip.sh
# Config via env (defaults shown):
#   FORGEJO_BASE_URL=https://git.squirrlylabs.xyz
#   FORGEJO_SMOKE_OWNER=squirrlylabs   FORGEJO_SMOKE_REPO=blacksmith-smoke
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../harness-lib.sh"

: "${FORGEJO_TOKEN:?set FORGEJO_TOKEN first (e.g. source your workspace .env)}"
BASE="${FORGEJO_BASE_URL:-https://git.squirrlylabs.xyz}"
OWNER="${FORGEJO_SMOKE_OWNER:-squirrlylabs}"
REPO="${FORGEJO_SMOKE_REPO:-blacksmith-smoke}"

CFG=$(mktemp); trap 'rm -f "$CFG"' EXIT
cat > "$CFG" <<JSON
{ "name": "$REPO", "forge": "forgejo",
  "forgejo": { "base_url": "$BASE", "owner": "$OWNER", "repo": "$REPO" },
  "workflow": { "kind": "gen-eval-9col", "column_names": {}, "actionable_columns": ["ready"] } }
JSON
export HARNESS_CONFIG="$CFG"

ok(){ echo "  ok  $1"; }
no(){ echo "  XX  $1" >&2; exit 1; }
eq(){ [[ "$1" == "$2" ]] || no "$3 (expected '$1', got '$2')"; ok "$3"; }

echo "blacksmith Forgejo live smoke -> $OWNER/$REPO @ $BASE"
eq forgejo "$(_blacksmith_forge)" "dispatch = forgejo"

blacksmith_provision_board && ok "board provisioned (8 status + taxonomy, exclusive labels)" \
  || no "blacksmith_provision_board failed"

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

blacksmith_archive_item "$c1"
eq "" "$(blacksmith_issue_status "$c1")" "archive -> uncolumned"

echo "forgejo-roundtrip: PASS"
