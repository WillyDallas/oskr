#!/usr/bin/env bash
# #38 — blacksmith_config_path resolves from anywhere inside a project, not just
# its root. A `cd` into a subdir must not un-project you.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"
LIB="$REPO_ROOT/bin/harness-lib.sh"

# -P: macOS /var -> /private/var, and git reports the physical path.
ROOT=$(cd "$(mktemp -d)" && pwd -P)
OUTSIDE=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$ROOT" "$OUTSIDE"' EXIT
WS="$ROOT/ws"
mkdir -p "$WS/.oskr" "$WS/projects/proj/docs/deep" "$WS/projects/dotclaude/.claude/sub"
CFG='{ "github": { "owner": "WillyDallas", "repo": "proj", "project_number": 1 } }'
echo "$CFG" > "$WS/projects/proj/harness-config.json"
echo "$CFG" > "$WS/projects/dotclaude/.claude/harness-config.json"

resolve() { # resolve <cwd> -> stdout
  (cd "$1" && OSKR_WORKSPACE="" HARNESS_CONFIG="" \
    bash -c "source '$LIB' && blacksmith_config_path")
}
resolve_err() { # resolve_err <cwd> -> stderr, never fails
  (cd "$1" && OSKR_WORKSPACE="" HARNESS_CONFIG="" \
    bash -c "source '$LIB' && blacksmith_config_path") 2>&1 || true
}

# Test 1: project root still resolves (regression).
assert_eq "$WS/projects/proj/harness-config.json" "$(resolve "$WS/projects/proj")" \
  "project root resolves"

# Test 2: nested subdir walks up to the project config — the #38 fix.
assert_eq "$WS/projects/proj/harness-config.json" "$(resolve "$WS/projects/proj/docs/deep")" \
  "nested subdir walks up"

# Test 3: the .claude/ variant is found from a subdir too.
assert_eq "$WS/projects/dotclaude/.claude/harness-config.json" \
  "$(resolve "$WS/projects/dotclaude/.claude/sub")" ".claude/ variant walks up"

# Test 4: no project anywhere up the chain -> the same actionable failure.
ERR=$(resolve_err "$WS/projects")
grep -qF "not in an oskr project" <<<"$ERR" \
  || { echo "FAIL: workspace root should not resolve a project; got: $ERR" >&2; exit 1; }

# Test 5: a config ABOVE the workspace root cannot capture the workspace.
echo "$CFG" > "$ROOT/harness-config.json"
ERR=$(resolve_err "$WS/projects")
grep -qF "not in an oskr project" <<<"$ERR" \
  || { echo "FAIL: walk escaped the workspace root; got: $ERR" >&2; exit 1; }
rm -f "$ROOT/harness-config.json"

# Test 6: a linked worktree whose branch lacks the config falls back to the main
# worktree — Orca parks worktrees outside the repo.
REPO="$WS/projects/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email t@example.com
git -C "$REPO" config user.name tester
echo hi > "$REPO/README.md"
git -C "$REPO" add README.md
git -C "$REPO" -c commit.gpgsign=false commit -qm init
echo "$CFG" > "$REPO/harness-config.json"   # untracked: absent from the linked checkout
git -C "$REPO" branch -q feat
git -C "$REPO" worktree add -q "$OUTSIDE/wt" feat
assert_eq "$REPO/harness-config.json" "$(resolve "$OUTSIDE/wt")" \
  "linked worktree falls back to main worktree"

# Test 7: HARNESS_CONFIG still wins over the walk.
SAMPLE="$REPO_ROOT/tests/scripts/fixtures/harness-config.sample.json"
OUT=$(cd "$WS/projects/proj/docs/deep" && HARNESS_CONFIG="$SAMPLE" \
  bash -c "source '$LIB' && blacksmith_config_path")
assert_eq "$SAMPLE" "$OUT" "HARNESS_CONFIG overrides the walk"

echo "test_config_path_walk: PASS"
