#!/usr/bin/env bash
# blacksmith_create_issue (GitHub, #26 slice 3): REST create + add the new issue
# to the configured Project v2 board via GraphQL. Echoes the neutral { number, url }
# (no GitHub-only item id). Verifies the create payload and the board-add side effect.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/lib/assert.sh"

SHIM_DIR=$(mktemp -d); CACHE_DIR=$(mktemp -d)
trap 'rm -rf "$SHIM_DIR" "$CACHE_DIR"' EXIT
LOG="$SHIM_DIR/gh-calls.log"; : > "$LOG"
cp "$SCRIPT_DIR/lib/gh-shim.sh" "$SHIM_DIR/gh"; chmod +x "$SHIM_DIR/gh"

out=$(PATH="$SHIM_DIR:$PATH" \
  HARNESS_CONFIG="$REPO_ROOT/tests/scripts/fixtures/harness-config.sample.json" \
  GH_SHIM_CALL_LOG="$LOG" \
  GH_SHIM_FIXTURE="$REPO_ROOT/tests/scripts/fixtures/gh-project-discovery.json" \
  GH_SHIM_CREATE_ISSUE_FIXTURE="$REPO_ROOT/tests/scripts/fixtures/gh-create-issue.json" \
  XDG_CACHE_HOME="$CACHE_DIR" \
  bash -c "source '$REPO_ROOT/bin/harness-lib.sh'; blacksmith_create_issue 'My title' 'Body text' 'bug,backend'")

# Neutral output: { number, url } only (no GitHub-only item id).
assert_eq '42' "$(jq -r '.number' <<<"$out")"                              "create returns the issue number" || exit 1
assert_eq 'https://github.com/WillyDallas/oskr/issues/42' "$(jq -r '.url' <<<"$out")" "create returns the url" || exit 1
assert_eq 'false' "$(jq 'has("item_id")' <<<"$out")"                       "neutral output omits GitHub item id" || exit 1

# The create payload carried title + body + both labels.
grep -qF 'title=My title' "$LOG"   || { echo "FAIL: title not sent" >&2; exit 1; }
grep -qF 'body=Body text' "$LOG"   || { echo "FAIL: body not sent" >&2; exit 1; }
grep -qF 'labels[]=bug' "$LOG"     || { echo "FAIL: label 'bug' not sent" >&2; exit 1; }
grep -qF 'labels[]=backend' "$LOG" || { echo "FAIL: label 'backend' not sent" >&2; exit 1; }

# Board-add side effect happened (issue put on the configured Project v2).
grep -qF 'addProjectV2ItemById' "$LOG" || { echo "FAIL: issue not added to the board" >&2; exit 1; }

# Regression (review high): the no-labels path must not crash under `set -u` on
# bash 3.2 (empty-array expansion). Run with the same options as bin/ consumers.
LOG2="$SHIM_DIR/create-nolabels.log"; : > "$LOG2"
out2=$(PATH="$SHIM_DIR:$PATH" \
  HARNESS_CONFIG="$REPO_ROOT/tests/scripts/fixtures/harness-config.sample.json" \
  GH_SHIM_CALL_LOG="$LOG2" \
  GH_SHIM_FIXTURE="$REPO_ROOT/tests/scripts/fixtures/gh-project-discovery.json" \
  GH_SHIM_CREATE_ISSUE_FIXTURE="$REPO_ROOT/tests/scripts/fixtures/gh-create-issue.json" \
  XDG_CACHE_HOME="$CACHE_DIR" \
  bash -c "set -euo pipefail; source '$REPO_ROOT/bin/harness-lib.sh'; blacksmith_create_issue 'No labels'")
assert_eq '42' "$(jq -r '.number' <<<"$out2")" "create_issue works with no labels under set -u" || exit 1

echo "test_blacksmith_create_issue: PASS"
