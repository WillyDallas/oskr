#!/usr/bin/env bash
# harness-lib.sh tail-sources learning-lib.sh AFTER hjarne-lib.sh, exit-status-neutral.
# NOTE on order: both libs are function-only, so bash resolves hjarne_write_page at
# CALL time regardless of source order — the order check below is a convention
# check. The functional leg proves the WIRING: a bare `source harness-lib.sh` is
# enough to drive learning_resource_mark end to end.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"
LIB="$REPO_ROOT/bin/harness-lib.sh"

# present: bare source exposes the learning verbs
bash -c "set -e; source '$LIB'; declare -F learning_resolve_root >/dev/null; declare -F learning_resource_mark >/dev/null" \
  || { echo "FAIL: learning verbs not exposed via harness-lib.sh tail-wire" >&2; exit 1; }

# order: learning tail-source line sits after the hjarne one
H=$(grep -nF 'hjarne-lib.sh"' "$LIB" | head -1 | cut -d: -f1)
L=$(grep -nF 'learning-lib.sh"' "$LIB" | head -1 | cut -d: -f1)
[[ -n "$H" && -n "$L" && "$L" -gt "$H" ]] \
  || { echo "FAIL: learning-lib.sh not tail-sourced after hjarne-lib.sh (hjarne=$H learning=$L)" >&2; exit 1; }

# absent: harness-lib + hjarne-lib WITHOUT sibling learning-lib.sh still source cleanly
TMP=$(mktemp -d)
WS=$(cd "$(mktemp -d)" && pwd)
trap 'rm -rf "$TMP" "$WS"' EXIT
cp "$LIB" "$TMP/harness-lib.sh"
cp "$REPO_ROOT/bin/hjarne-lib.sh" "$TMP/hjarne-lib.sh"
OUT=$(bash -c "set -e; source '$TMP/harness-lib.sh'; echo ok")
[[ "$OUT" == "ok" ]] \
  || { echo "FAIL: harness-lib.sh did not source cleanly without sibling learning-lib.sh ('$OUT')" >&2; exit 1; }

# functional: end-to-end mark through a BARE `source harness-lib.sh`
mkdir -p "$WS/.oskr"
export OSKR_WORKSPACE="$WS"
bash -c '
  set -euo pipefail
  source "$1"
  SEED="# Wire Topic Resources

- [Doc](https://example.com) <!-- learning:resource id=doc status=queued -->
  How to use: skim before the first lesson."
  hjarne_write_page "$(learning_resources_page "Wire Topic")" "$SEED"
  learning_resource_mark "Wire Topic" doc ingested
' _ "$LIB"
GOT=$(bash -c 'source "$1"; learning_resource_status "Wire Topic" doc' _ "$LIB")
assert_eq ingested "$GOT" "mark round-trips through bare harness-lib sourcing"
grep -qF 'v2' "$WS/hjarne/wiki/learning-wire-topic-resources.md" \
  || { echo "FAIL: wire mark did not version-stamp via hjarne_write_page" >&2; exit 1; }

echo "test_learning_lib_wire: PASS"
