#!/usr/bin/env bash
# Smoke test: round-trip move on the real oskr Project v2 board.
# Usage: scripts/smoke/round-trip-move.sh <ITEM_ID>
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/harness-lib.sh"

ITEM_ID="${1:?usage: round-trip-move.sh <ITEM_ID>}"

current=$(blacksmith_item_status "$ITEM_ID")

echo "round-trip: current column = $current"

echo "round-trip: moving to Backlog"
blacksmith_move_issue "$ITEM_ID" "Backlog" >/dev/null

after=$(blacksmith_item_status "$ITEM_ID")

if [[ "$after" != "Backlog" ]]; then
  echo "round-trip: FAIL — expected Backlog, got $after"
  exit 1
fi

echo "round-trip: moving back to $current"
blacksmith_move_issue "$ITEM_ID" "$current" >/dev/null

echo "round-trip: PASS"
