#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DISPATCHER="$REPO_ROOT/scripts/board-dispatcher.sh"
HARNESS_LIB="$REPO_ROOT/scripts/harness-lib.sh"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"

[[ -f "$DISPATCHER" ]] || { echo "FAIL: $DISPATCHER missing"; exit 1; }
[[ -x "$DISPATCHER" ]] || { echo "FAIL: $DISPATCHER not executable"; exit 1; }

assert_exit 0 bash -n "$DISPATCHER" || exit 1

if command -v shellcheck >/dev/null 2>&1; then
  assert_exit 0 shellcheck "$DISPATCHER" || exit 1
else
  echo "SKIP: shellcheck not installed"
fi

! grep -qF 'board-constants.sh' "$DISPATCHER" \
  || { echo "FAIL: board-constants.sh reference present"; exit 1; }

! grep -qF 'Wonderloom' "$DISPATCHER" \
  || { echo "FAIL: hardcoded Wonderloom reference present"; exit 1; }

grep -qF 'harness-lib.sh' "$DISPATCHER" \
  || { echo "FAIL: harness-lib.sh not sourced"; exit 1; }

grep -qF 'actionable_columns' "$DISPATCHER" \
  || { echo "FAIL: actionable_columns not referenced"; exit 1; }

! grep -qF 'Board constants for move-issue.sh' "$DISPATCHER" \
  || { echo "FAIL: UUID-leak footer block still present"; exit 1; }

! grep -qF 'harness_column_name_for_slug' "$HARNESS_LIB" \
  || { echo "FAIL: harness_column_name_for_slug must not be a public function"; exit 1; }

echo "test_board_dispatcher_syntax: PASS"
