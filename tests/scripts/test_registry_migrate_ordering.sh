#!/usr/bin/env bash
# registry.sh migrate-ordering guard (#102). The FIRST touch of the registry in
# a workspace — whether a read-only `list` or a `add` — must migrate a legacy
# registry BEFORE the empty {"projects":[]} first-create can permanently
# short-circuit migrate (target exists => migrate no-ops forever, orphaning the
# legacy entries). OSKR_LEGACY_REGISTRY keeps the source fixture off the real
# $HOME/WillyDev/oskr/repos/projects.json.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"

seed_legacy() {
  cat > "$1" <<'JSON'
{ "projects": [
  { "name": "legacyproj", "path": "/ws/projects/legacyproj",
    "github": "WillyDallas/legacyproj", "project_number": 7,
    "registered_at": "2026-01-01T00:00:00Z" }
] }
JSON
}

WS_A=$(mktemp -d);  LEG_A=$(mktemp -d)
WS_B=$(mktemp -d);  LEG_B=$(mktemp -d)
trap 'rm -rf "$WS_A" "$LEG_A" "$WS_B" "$LEG_B"' EXIT
mkdir -p "$WS_A/.oskr" "$WS_B/.oskr"
REG_A="$WS_A/.oskr/registry.json"; LEGACY_A="$LEG_A/projects.json"
REG_B="$WS_B/.oskr/registry.json"; LEGACY_B="$LEG_B/projects.json"

# --- Case A: list-before-add regression pin --------------------------------
# A read-only `list` as the FIRST touch must migrate, not orphan the legacy.
seed_legacy "$LEGACY_A"
[[ ! -f "$REG_A" ]] || { echo "FAIL: registry.json should not exist yet (A)" >&2; exit 1; }

OSKR_WORKSPACE="$WS_A" OSKR_LEGACY_REGISTRY="$LEGACY_A" \
  bash "$REPO_ROOT/bin/registry.sh" list >/dev/null

[[ -f "$REG_A" ]] || { echo "FAIL: list did not create a registry (A)" >&2; exit 1; }
n=$(jq '.projects | length' "$REG_A")
[[ "$n" -ge 1 ]] || { echo "FAIL: list-before-add orphaned the legacy registry (0 entries)" >&2; exit 1; }
assert_eq 'legacyproj' "$(jq -r '.projects[0].name' "$REG_A")"  "list-first migrated the legacy entry" || exit 1
assert_eq 'github'     "$(jq -r '.projects[0].forge' "$REG_A")" "migrated entry forge-tagged" || exit 1
assert_eq '7' "$(jq -r '.projects[0].github.project_number' "$REG_A")" "project_number preserved through list-first migrate" || exit 1

# --- Case B: add as the FIRST touch migrates THEN adds ---------------------
seed_legacy "$LEGACY_B"
OSKR_WORKSPACE="$WS_B" OSKR_LEGACY_REGISTRY="$LEGACY_B" \
  bash "$REPO_ROOT/bin/registry.sh" add --name newproj --path /ws/projects/newproj \
    --forge github --owner WillyDallas --repo newproj --project-number 9

assert_eq '2' "$(jq '.projects | length' "$REG_B")" "add-first => migrated legacy + new = 2 entries" || exit 1
grep -qF '"legacyproj"' "$REG_B" || { echo "FAIL: add-first dropped the migrated legacy entry" >&2; exit 1; }
grep -qF '"newproj"'    "$REG_B" || { echo "FAIL: add-first did not add the new entry" >&2; exit 1; }

echo "test_registry_migrate_ordering: PASS"
