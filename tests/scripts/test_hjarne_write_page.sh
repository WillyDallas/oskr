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

PAGE="$BRAIN/wiki/board-dispatcher.md"
TODAY=$(date +%F)
CONTENT=$'# Board Dispatcher\n\nThe dispatcher polls the board and moves cards.'
STAMP_RE='^> Written [0-9]{4}-[0-9]{2}-[0-9]{2} .* v[0-9]+'   # frozen M2 regex (middot-tolerant)

# create → v1 + today on line 2, title preserved on line 1
hjarne_write_page "$PAGE" "$CONTENT"
[[ "$(sed -n 1p "$PAGE")" == '# Board Dispatcher' ]] || { echo "FAIL: title line clobbered" >&2; exit 1; }
L2=$(sed -n 2p "$PAGE")
grep -qE "$STAMP_RE" <<<"$L2" || { echo "FAIL: stamp shape wrong ($L2)" >&2; exit 1; }
grep -qF 'v1' <<<"$L2" || { echo "FAIL: create not v1 ($L2)" >&2; exit 1; }
grep -qF "$TODAY" <<<"$L2" || { echo "FAIL: create date not today ($L2)" >&2; exit 1; }

# backdate the stamp (stale page), then update → v2 + date refreshed to today
tmp=$(mktemp); sed -E 's/^> Written [0-9-]+ /> Written 2000-01-01 /' "$PAGE" > "$tmp" && mv "$tmp" "$PAGE"
grep -qF '2000-01-01' "$PAGE" || { echo "FAIL: backdate setup failed" >&2; exit 1; }

hjarne_write_page "$PAGE" "$CONTENT"
L2=$(sed -n 2p "$PAGE")
grep -qE "$STAMP_RE" <<<"$L2" || { echo "FAIL: update stamp shape wrong ($L2)" >&2; exit 1; }
grep -qF 'v2' <<<"$L2" || { echo "FAIL: update not v2 ($L2)" >&2; exit 1; }
grep -qF "$TODAY" <<<"$L2" || { echo "FAIL: update date not refreshed ($L2)" >&2; exit 1; }
! grep -qF '2000-01-01' "$PAGE" || { echo "FAIL: stale date not refreshed" >&2; exit 1; }

echo "test_hjarne_write_page: PASS"
