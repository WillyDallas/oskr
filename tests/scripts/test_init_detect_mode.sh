#!/usr/bin/env bash
# init_detect_mode (init v2, #27 / #57): pure mapping of
# {is-git?, has-origin?, remote-exists?, config-present?} -> the onboarding mode.
# Network-free, disk-free — straight subshell over the function. No shims.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"
LIB="$REPO_ROOT/bin/init-lib.sh"

detect() { bash -c "source '$LIB'; init_detect_mode \"\$@\"" _ "$@"; }

# config present always wins -> already-init (the re-init guard), whatever the rest.
assert_eq "already-init" "$(detect yes yes yes yes)" "config present -> already-init"        || exit 1
assert_eq "already-init" "$(detect no  no  no  yes)" "config present (bare) -> already-init"  || exit 1
# local git repo wired to an origin remote -> adopt.
assert_eq "adopt"        "$(detect yes yes no  no)"  "git + origin -> adopt"                  || exit 1
# repo exists on the forge but absent locally -> clone.
assert_eq "clone"        "$(detect no  no  yes no)"  "remote exists, absent locally -> clone" || exit 1
# nothing anywhere -> create-new.
assert_eq "create-new"   "$(detect no  no  no  no)"  "nothing -> create-new"                  || exit 1
# defaults: no args -> create-new (every input defaults to no).
assert_eq "create-new"   "$(bash -c "source '$LIB'; init_detect_mode")" "no args -> create-new" || exit 1

echo "test_init_detect_mode: PASS"
