#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"

DEST_DIR=$(mktemp -d)
trap 'rm -rf "$DEST_DIR"' EXIT

# Test 1: render against sample fixture writes all 7 agents with substitution.
HARNESS_CONFIG="$REPO_ROOT/tests/scripts/fixtures/harness-config.sample.json" \
  bash -c "
    source '$REPO_ROOT/scripts/harness-lib.sh'
    count=\$(harness_render_agents '$DEST_DIR')
    [[ \"\$count\" == 7 ]] || { echo FAIL: expected 7 agents, got \"\$count\"; exit 1; }
  "

# Test 2: every rendered file is non-empty and contains the substituted project name.
for f in researcher planner plan-reviewer implementer reviewer research-reviewer playwright-tester; do
  [[ -s "$DEST_DIR/$f.md" ]] || { echo "FAIL: $f.md missing or empty"; exit 1; }
  grep -qF 'Oskr Test' "$DEST_DIR/$f.md" || { echo "FAIL: $f.md missing project name substitution"; exit 1; }
done

# Test 3: tech_stack substitution appears in agents that referenced it.
for f in researcher planner plan-reviewer implementer reviewer research-reviewer; do
  grep -qF 'bash + gh CLI' "$DEST_DIR/$f.md" || { echo "FAIL: $f.md missing tech stack substitution"; exit 1; }
done

# Test 4: no raw placeholders survive in any rendered output.
for f in "$DEST_DIR"/*.md; do
  if grep -qE '\{\{(PROJECT_NAME|TECH_STACK)\}\}' "$f"; then
    echo "FAIL: $(basename "$f") still contains raw placeholders"
    exit 1
  fi
done

# Test 5: missing dest_dir is a usage error.
HARNESS_CONFIG="$REPO_ROOT/tests/scripts/fixtures/harness-config.sample.json" \
  bash -c "
    source '$REPO_ROOT/scripts/harness-lib.sh'
    harness_render_agents '' 2>/dev/null
  " && { echo "FAIL: empty dest_dir should exit non-zero"; exit 1; } || true

# Test 6: missing source dir surfaces a clear error.
EMPTY_SRC=$(mktemp -d)
trap 'rm -rf "$DEST_DIR" "$EMPTY_SRC"' EXIT
ERR_OUT=$(
  HARNESS_CONFIG="$REPO_ROOT/tests/scripts/fixtures/harness-config.sample.json" \
  HARNESS_AGENTS_SOURCE="$EMPTY_SRC" \
    bash -c "
      source '$REPO_ROOT/scripts/harness-lib.sh'
      harness_render_agents '$DEST_DIR'
    " 2>&1 || true
)
grep -qF 'no agent templates found' <<<"$ERR_OUT" || {
  echo "FAIL: empty source dir error message missing"
  echo "--- actual ---"
  echo "$ERR_OUT"
  exit 1
}

echo "test_harness_render_agents: PASS"
