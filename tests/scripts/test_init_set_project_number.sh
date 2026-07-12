#!/usr/bin/env bash
# init_config_set_project_number (#103): backfills the REAL board number into an
# emitted config after provisioning — the fix for the project_number:0 hole
# between adopt-detect and re-emit. Atomic + validated; garbage never lands.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"
LIB="$REPO_ROOT/bin/init-lib.sh"

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
CFG="$WORK/harness-config.json"
bash -c "source '$LIB'; init_emit_config github demo 'bash' main owner repo 0" > "$CFG"

setpn() { bash -c "source '$LIB'; init_config_set_project_number \"\$@\"" _ "$@"; }

setpn "$CFG" 42 || { echo "FAIL: backfill of a valid number failed" >&2; exit 1; }
assert_eq "42" "$(jq -r '.github.project_number' "$CFG")" "project_number backfilled" || exit 1
assert_eq "demo" "$(jq -r '.name' "$CFG")" "rest of the config untouched" || exit 1

# Non-numeric and missing-file inputs refuse loudly; the config is not corrupted.
assert_exit 1 setpn "$CFG" "not-a-number" || exit 1
assert_eq "42" "$(jq -r '.github.project_number' "$CFG")" "refused write left config intact" || exit 1
assert_exit 1 setpn "$WORK/nope.json" 7 || exit 1
[[ -z "$(ls "$WORK" | grep tmp || true)" ]] || { echo "FAIL: temp file leaked" >&2; exit 1; }

echo "test_init_set_project_number: PASS"
