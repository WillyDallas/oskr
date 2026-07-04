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

echo "test_hjarne_inbox: PASS"
