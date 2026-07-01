#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"
SETUP="$REPO_ROOT/bin/oskr-setup.sh"

TMPROOT=$(mktemp -d); trap 'rm -rf "$TMPROOT"' EXIT

# ---- skeleton: dirs + empty registry, asserted against a clean fixture dir ----
WS="$TMPROOT/ws-skel"
"$SETUP" skeleton "$WS"
for d in .oskr projects hjarne learning; do
  test -d "$WS/$d" || { echo "FAIL: skeleton missing dir $d" >&2; exit 1; }
done
test -f "$WS/.oskr/registry.json" || { echo "FAIL: registry.json missing" >&2; exit 1; }
assert_eq "[]" "$(jq -c '.projects' "$WS/.oskr/registry.json")" "registry empty" || exit 1

# idempotent: a second skeleton run must not error or clobber an empty registry
"$SETUP" skeleton "$WS"
assert_eq "[]" "$(jq -c '.projects' "$WS/.oskr/registry.json")" "registry survives re-skeleton" || exit 1

echo "test_oskr_setup skeleton: PASS"
