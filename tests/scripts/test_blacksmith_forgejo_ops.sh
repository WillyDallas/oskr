#!/usr/bin/env bash
# Forgejo core ops (#26 slice 7) — hermetic, via curl-shim. The same public verbs
# that hit GitHub elsewhere here dispatch to _blacksmith_forgejo_* on a forge=forgejo
# config: create (issue + status/backlog), move (exclusive status label), read status
# (label -> display name), find_item. Mirrors the verified live round-trip.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB="$REPO_ROOT/bin/harness-lib.sh"
FCFG="$REPO_ROOT/tests/scripts/fixtures/harness-config.forgejo.json"
FIX="$REPO_ROOT/tests/scripts/fixtures"
source "$SCRIPT_DIR/lib/assert.sh"

SHIM_DIR=$(mktemp -d); trap 'rm -rf "$SHIM_DIR"' EXIT
cp "$SCRIPT_DIR/lib/curl-shim.sh" "$SHIM_DIR/curl"; chmod +x "$SHIM_DIR/curl"
run() { PATH="$SHIM_DIR:$PATH" HARNESS_CONFIG="$FCFG" FORGEJO_TOKEN="test-token" \
        CURL_SHIM_CALL_LOG="$1" bash -c "source '$LIB'; ${2}"; }

# create_issue -> neutral { number, url }; default status/backlog + extra label posted by name.
L1="$SHIM_DIR/c.log"; : > "$L1"
out=$(CURL_SHIM_CREATE_FIXTURE="$FIX/forgejo-create-issue.json" run "$L1" "blacksmith_create_issue 'T' 'B' 'bug'")
assert_eq "2"     "$(jq -r '.number' <<<"$out")" "forgejo create -> number"        || exit 1
assert_eq "false" "$(jq 'has("item_id")' <<<"$out")" "neutral output (no item id)" || exit 1
grep -qF '/issues/2/labels' "$L1" || { echo "FAIL: initial labels not posted" >&2; exit 1; }
grep -qF 'status/backlog'   "$L1" || { echo "FAIL: default column not applied" >&2; exit 1; }
grep -qF 'bug'              "$L1" || { echo "FAIL: extra label not applied" >&2; exit 1; }

# move_issue -> POST the exclusive status/<slug> label (exclusivity evicts the old one server-side).
L2="$SHIM_DIR/m.log"; : > "$L2"
run "$L2" "blacksmith_move_issue 2 in_progress" >/dev/null
grep -qF '/issues/2/labels'   "$L2" || { echo "FAIL: move did not hit issue labels" >&2; exit 1; }
grep -qF 'status/in_progress' "$L2" || { echo "FAIL: move did not set status/in_progress" >&2; exit 1; }

# issue_status -> reads the status/* label off the issue, maps slug -> display name (== GitHub).
L3="$SHIM_DIR/s.log"; : > "$L3"
st=$(CURL_SHIM_ISSUE_FIXTURE="$FIX/forgejo-issue.json" run "$L3" "blacksmith_issue_status 2")
assert_eq "In Progress" "$st" "forgejo issue_status -> display name" || exit 1

# find_item -> echoes the issue number (the issue IS the board item on Forgejo).
L4="$SHIM_DIR/f.log"; : > "$L4"
fi=$(CURL_SHIM_ISSUE_FIXTURE="$FIX/forgejo-issue.json" run "$L4" "blacksmith_find_item 2")
assert_eq "2" "$fi" "forgejo find_item -> issue number" || exit 1

echo "test_blacksmith_forgejo_ops: PASS"
