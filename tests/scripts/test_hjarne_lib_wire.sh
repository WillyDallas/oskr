#!/usr/bin/env bash
# §6C: harness-lib.sh tail-sources hjarne-lib.sh, exit-status-neutral.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB="$REPO_ROOT/bin/harness-lib.sh"

# present: sourcing harness-lib.sh tail-loads hjarne-lib.sh → hjarne_resolve_brain defined
bash -c "set -e; source '$LIB'; declare -F hjarne_resolve_brain >/dev/null" \
  || { echo "FAIL: hjarne_resolve_brain not exposed via harness-lib.sh tail-wire" >&2; exit 1; }

# absent: harness-lib.sh ALONE (no sibling hjarne-lib.sh) still sources cleanly, exit 0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cp "$LIB" "$TMP/harness-lib.sh"
OUT=$(bash -c "set -e; source '$TMP/harness-lib.sh'; echo ok")
[[ "$OUT" == "ok" ]] \
  || { echo "FAIL: harness-lib.sh did not source cleanly without sibling hjarne-lib.sh ('$OUT')" >&2; exit 1; }

echo "test_hjarne_lib_wire: PASS"
