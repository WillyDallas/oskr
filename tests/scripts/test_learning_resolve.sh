#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"
source "$REPO_ROOT/bin/harness-lib.sh"    # blacksmith_workspace_dir + hjarne_* helpers
source "$REPO_ROOT/bin/learning-lib.sh"   # units under test

WS=$(cd "$(mktemp -d)" && pwd)            # canonicalized so /tmp symlinks don't break ==
OTHER=$(cd "$(mktemp -d)" && pwd)         # no .oskr/ anywhere above it
trap 'rm -rf "$WS" "$OTHER"' EXIT
mkdir -p "$WS/.oskr"
export OSKR_WORKSPACE="$WS"

# resolution inside a workspace: <workspace>/learning, from the resolver — never CWD
GOT=$(learning_resolve_root)
assert_eq "$WS/learning" "$GOT" "resolve_root == workspace/learning"

# topic-dir derivation + slugging (case folded, punctuation collapsed, edges trimmed)
GOT=$(learning_topic_dir "Rust Macros!")
assert_eq "$WS/learning/rust-macros" "$GOT" "topic dir is slugged under the learning root"

# resources page: canonical hjarne wiki page path (read-only derivation via hjarne_route)
GOT=$(learning_resources_page "Rust Macros!")
assert_eq "$WS/hjarne/wiki/learning-rust-macros-resources.md" "$GOT" \
  "resources page routes into the brain wiki"

# refusal outside a workspace: non-zero exit + INSTRUCTIVE stderr, nothing written.
# learning-lib sourced explicitly so this test does not depend on Task 3's tail-wire.
ERR=$(cd "$OTHER" && OSKR_WORKSPACE="" bash -c \
  "source '$REPO_ROOT/bin/harness-lib.sh' && source '$REPO_ROOT/bin/learning-lib.sh' && learning_resolve_root" 2>&1) \
  && { echo "FAIL: learning_resolve_root succeeded outside a workspace" >&2; exit 1; }
grep -qF "not inside an oskr workspace" <<<"$ERR" \
  || { echo "FAIL: refusal not loud/clear; got: $ERR" >&2; exit 1; }
grep -qF "oskr-setup" <<<"$ERR" \
  || { echo "FAIL: refusal not instructive (no oskr-setup remedy); got: $ERR" >&2; exit 1; }
[[ -z "$(ls -A "$OTHER")" ]] \
  || { echo "FAIL: refusal wrote into the CWD" >&2; exit 1; }

echo "test_learning_resolve: PASS"
