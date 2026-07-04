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

INBOX="$WS/inbox"   # inbox is a helper ARG (a fixture dir here; the skill supplies docs/brain-inbox/)
C1=$'# Board Dispatcher\n\nPolls the board.'

# M7: inbox_stage writes the hjarne:meta fence with provenance + subdir
F=$(hjarne_inbox_stage "$INBOX" '#70:board-dispatcher' "$C1" research)
test -f "$F" || { echo "FAIL: stage did not write a file" >&2; exit 1; }
grep -qF '<!-- hjarne:meta provenance=#70:board-dispatcher subdir=research -->' "$F" \
  || { echo "FAIL: meta fence missing/wrong ($(head -1 "$F"))" >&2; exit 1; }
grep -qF 'Polls the board.' "$F" || { echo "FAIL: staged content missing" >&2; exit 1; }

# M8: drain integrates each staged note (subdir honored) then removes its file
hjarne_inbox_drain "$INBOX"
test -f "$BRAIN/wiki/board-dispatcher.md" || { echo "FAIL: M8 drain did not integrate" >&2; exit 1; }
test -f "$(hjarne_raw_path '#70:board-dispatcher' research)" || { echo "FAIL: M8 drain ignored subdir" >&2; exit 1; }
! test -e "$F" || { echo "FAIL: M8 drain did not remove the staged file" >&2; exit 1; }

# M8: dup short-circuit STILL removes the file
F2=$(hjarne_inbox_stage "$INBOX" '#70:board-dispatcher' "$C1" research)
hjarne_inbox_drain "$INBOX"
! test -e "$F2" || { echo "FAIL: M8 dup drain did not remove the staged file" >&2; exit 1; }

# M8: 2nd drain on an empty inbox is a no-op (exit 0 under set -e)
hjarne_inbox_drain "$INBOX"

echo "test_hjarne_inbox: PASS"
