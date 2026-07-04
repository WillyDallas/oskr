#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"
source "$REPO_ROOT/bin/harness-lib.sh"   # blacksmith_workspace_dir / _blacksmith_die
source "$REPO_ROOT/bin/hjarne-lib.sh"    # units under test

WS=$(cd "$(mktemp -d)" && pwd)           # canonicalized so /tmp symlinks don't break ==
trap 'rm -rf "$WS"' EXIT
mkdir -p "$WS/.oskr"
bash "$REPO_ROOT/bin/hjarne-skeleton.sh" "$WS/hjarne"
export OSKR_WORKSPACE="$WS"
BRAIN="$WS/hjarne"

# M1: resolve_brain == workspace/hjarne == the skeleton stamp target.
GOT=$(hjarne_resolve_brain)
assert_eq "$WS/hjarne" "$GOT" "resolve_brain == workspace/hjarne"
test -d "$GOT/wiki" || { echo "FAIL: resolve_brain path is not the skeleton stamp target ($GOT)" >&2; exit 1; }

echo "test_hjarne_resolve_brain: PASS"
