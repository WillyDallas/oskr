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

# M3: deterministic — same provenance → same path.
P1=$(hjarne_raw_path '#70:board-dispatcher')
P2=$(hjarne_raw_path '#70:board-dispatcher')
assert_eq "$P1" "$P2" "same provenance → same raw path"

# M3: injective — distinct provenance → distinct paths.
P3=$(hjarne_raw_path '#70:find-item')
[[ "$P1" != "$P3" ]] || { echo "FAIL: distinct provenance collided ($P1)" >&2; exit 1; }

# M3: hash disambiguates a slug collision (#70:board-dispatcher vs #70/board-dispatcher).
P4=$(hjarne_raw_path '#70/board-dispatcher')
[[ "$P1" != "$P4" ]] || { echo "FAIL: hash failed to disambiguate slug collision" >&2; exit 1; }

# shape: <brain>/raw/<slug>-<hash>.md ; subdir routes under raw/<subdir>/
case "$P1" in "$BRAIN/raw/"*-*.md) : ;; *) echo "FAIL: raw_path shape ($P1)" >&2; exit 1 ;; esac
P5=$(hjarne_raw_path '#70:deep-dive' research)
case "$P5" in "$BRAIN/raw/research/"*-*.md) : ;; *) echo "FAIL: subdir shape ($P5)" >&2; exit 1 ;; esac

echo "test_hjarne_raw_path: PASS"
