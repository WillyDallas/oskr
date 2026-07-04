#!/usr/bin/env bash
# registry.sh add/list: workspace-rooted .oskr/registry.json. Covers first-create,
# idempotent add (no dup by name), list, and forge + per-backend coords (mixed
# backend). Pure subshell-fixture style — no forge shim (registry.sh makes no
# forge calls). OSKR_WORKSPACE pins resolution to a temp workspace.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"

WS=$(mktemp -d)
trap 'rm -rf "$WS"' EXIT
mkdir -p "$WS/.oskr"
REG="$WS/.oskr/registry.json"
run() { OSKR_WORKSPACE="$WS" bash "$REPO_ROOT/bin/registry.sh" "$@"; }

# --- T1 contract guard (frozen dependency) ---------------------------------
# This registry tier is BLOCKED-BY T1's workspace resolver. Assert T1's frozen
# contract up front so a divergent landing fails HERE (one obvious spot) instead
# of mechanically across every registry AC:
#   blacksmith_workspace_dir -> echoes the WORKSPACE ROOT (the dir CONTAINING
#   .oskr/, not .oskr/ itself) on stdout, exit 0; honors $OSKR_WORKSPACE as an
#   override; dies non-zero when neither resolves.
ws_resolved=$(OSKR_WORKSPACE="$WS" bash -c "source '$REPO_ROOT/bin/harness-lib.sh' && blacksmith_workspace_dir") \
  || { echo "FAIL: blacksmith_workspace_dir undefined or errored — T1 contract not met; STOP and reconcile with T1" >&2; exit 1; }
assert_eq "$WS" "$ws_resolved" "blacksmith_workspace_dir echoes the workspace root and honors OSKR_WORKSPACE" || exit 1

# First-create: registry.json absent -> add creates it with exactly one entry.
[[ ! -f "$REG" ]] || { echo "FAIL: registry.json should not exist yet" >&2; exit 1; }
run add --name oskr --path /ws/projects/oskr --forge github \
    --owner WillyDallas --repo oskr --project-number 5
[[ -f "$REG" ]] || { echo "FAIL: add did not create registry.json" >&2; exit 1; }
assert_eq '1' "$(jq '.projects | length' "$REG")" "first add => 1 entry" || exit 1

# Entry carries forge + per-backend coords.
assert_eq 'github'      "$(jq -r '.projects[0].forge' "$REG")"                "forge recorded" || exit 1
assert_eq 'WillyDallas' "$(jq -r '.projects[0].github.owner' "$REG")"         "github.owner" || exit 1
assert_eq 'oskr'        "$(jq -r '.projects[0].github.repo' "$REG")"          "github.repo" || exit 1
assert_eq '5'           "$(jq -r '.projects[0].github.project_number' "$REG")" "github.project_number" || exit 1

# Idempotent add: re-adding the same name is a no-op (still one entry).
run add --name oskr --path /ws/projects/oskr --forge github \
    --owner WillyDallas --repo oskr --project-number 5
assert_eq '1' "$(jq '.projects | length' "$REG")" "re-add same name => still 1 entry" || exit 1

# Mixed backend: a forgejo project records forgejo coords alongside the github one.
run add --name sluice --path /ws/projects/sluice --forge forgejo \
    --base-url https://sluice.example --owner ops --repo sluice
assert_eq '2'       "$(jq '.projects | length' "$REG")"      "second project => 2 entries" || exit 1
assert_eq 'forgejo' "$(jq -r '.projects[1].forge' "$REG")"   "forgejo forge" || exit 1
assert_eq 'https://sluice.example' "$(jq -r '.projects[1].forgejo.base_url' "$REG")" "forgejo.base_url" || exit 1
assert_eq 'ops'     "$(jq -r '.projects[1].forgejo.owner' "$REG")" "forgejo.owner" || exit 1

# list echoes the projects array (2 entries, both names present).
out=$(run list)
assert_eq '2' "$(jq 'length' <<<"$out")" "list => 2 entries" || exit 1
grep -qF '"oskr"'   <<<"$out" || { echo "FAIL: list missing oskr" >&2; exit 1; }
grep -qF '"sluice"' <<<"$out" || { echo "FAIL: list missing sluice" >&2; exit 1; }

echo "test_registry_add: PASS"
