#!/usr/bin/env bash
# registry.sh migrate: one-time, idempotent relocation of the legacy in-plugin
# registry into <workspace>/.oskr/registry.json. Covers present / absent /
# already-migrated. OSKR_LEGACY_REGISTRY overrides the source so the test never
# touches the real $HOME/WillyDev/oskr/repos/projects.json.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"

WS=$(mktemp -d); LEGACY_DIR=$(mktemp -d)
trap 'rm -rf "$WS" "$LEGACY_DIR"' EXIT
mkdir -p "$WS/.oskr"
REG="$WS/.oskr/registry.json"
LEGACY="$LEGACY_DIR/projects.json"
run() { OSKR_WORKSPACE="$WS" OSKR_LEGACY_REGISTRY="$LEGACY" bash "$REPO_ROOT/bin/registry.sh" migrate; }

# Case A: source ABSENT -> no-op, no error, no target created.
run
[[ ! -f "$REG" ]] || { echo "FAIL: migrate created a registry from an absent source" >&2; exit 1; }

# Case B: source PRESENT -> migrate transforms legacy GitHub-only entries.
cat > "$LEGACY" <<'JSON'
{ "projects": [
  { "name": "oskr", "path": "/ws/projects/oskr", "github": "WillyDallas/oskr",
    "project_number": 5, "registered_at": "2026-01-01T00:00:00Z" }
] }
JSON
run
[[ -f "$REG" ]] || { echo "FAIL: migrate did not create the target" >&2; exit 1; }
assert_eq '1'           "$(jq '.projects | length' "$REG")"                    "migrated 1 entry" || exit 1
assert_eq 'github'      "$(jq -r '.projects[0].forge' "$REG")"                 "legacy entry tagged forge=github" || exit 1
assert_eq 'WillyDallas' "$(jq -r '.projects[0].github.owner' "$REG")"          "owner split from github string" || exit 1
assert_eq 'oskr'        "$(jq -r '.projects[0].github.repo' "$REG")"           "repo split from github string" || exit 1
assert_eq '5'           "$(jq -r '.projects[0].github.project_number' "$REG")" "project_number preserved" || exit 1
assert_eq '2026-01-01T00:00:00Z' "$(jq -r '.projects[0].registered_at' "$REG")" "registered_at preserved" || exit 1

# Case C: already migrated -> re-running is a byte-for-byte no-op.
before=$(cat "$REG")
run
assert_eq "$before" "$(cat "$REG")" "re-run is a byte-for-byte no-op" || exit 1

echo "test_registry_migrate: PASS"
