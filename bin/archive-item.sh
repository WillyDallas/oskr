#!/usr/bin/env bash
# shellcheck disable=SC1091
# SC1091: harness-lib.sh is sourced and not followed without -x
# Archives a GitHub Project item — the card disappears from the board view;
# the underlying issue is untouched (state, comments, labels all preserved).
# Reversible: restore from the project's archived-items view, or via the
# unarchiveProjectV2Item mutation with the same item ID.
#
# Usage: archive-item.sh <ITEM_ID>
#
# Example:
#   ITEM_ID=$(find-item.sh 123)
#   archive-item.sh "$ITEM_ID"

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/harness-lib.sh"

ITEM_ID="${1:?usage: archive-item.sh <ITEM_ID>}"

blacksmith_archive_item "$ITEM_ID"
