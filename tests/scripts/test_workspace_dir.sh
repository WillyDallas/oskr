#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"
LIB="$REPO_ROOT/bin/harness-lib.sh"

# Fixture workspace tree: <WS>/.oskr/ + a nested project subdir.
# `cd ... && pwd` canonicalizes so string-equality holds despite /tmp symlinks.
WS=$(cd "$(mktemp -d)" && pwd)
OTHER=$(cd "$(mktemp -d)" && pwd)
trap 'rm -rf "$WS" "$OTHER"' EXIT
mkdir -p "$WS/.oskr" "$WS/projects/proj/src/deep"

# Test 1: from a nested subdir, resolver returns the workspace root.
OUT=$(cd "$WS/projects/proj/src/deep" && OSKR_WORKSPACE="" \
  bash -c "source '$LIB' && blacksmith_workspace_dir")
assert_eq "$WS" "$OUT" "nested subdir resolves to workspace root"

# Test 2: OSKR_WORKSPACE overrides the walk (CWD is outside the tree).
OUT=$(cd "$OTHER" && OSKR_WORKSPACE="$WS" \
  bash -c "source '$LIB' && blacksmith_workspace_dir")
assert_eq "$WS" "$OUT" "OSKR_WORKSPACE overrides the walk"

# Test 3: no .oskr/ ancestor and OSKR_WORKSPACE empty -> clear, actionable error.
ERR=$(cd "$OTHER" && OSKR_WORKSPACE="" \
  bash -c "source '$LIB' && blacksmith_workspace_dir" 2>&1 || true)
grep -qF "not inside an oskr workspace" <<<"$ERR" \
  || { echo "FAIL: missing clear no-workspace error; got: $ERR" >&2; exit 1; }

# Test 4: OSKR_WORKSPACE set but no .oskr/ inside -> clear misconfig error.
ERR=$(OSKR_WORKSPACE="$OTHER" \
  bash -c "source '$LIB' && blacksmith_workspace_dir" 2>&1 || true)
grep -qF "OSKR_WORKSPACE set but" <<<"$ERR" \
  || { echo "FAIL: misconfigured OSKR_WORKSPACE not flagged; got: $ERR" >&2; exit 1; }

echo "test_workspace_dir: PASS"
