#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2016
# SC1091: harness-lib.sh is sourced and not followed without -x
# SC2016: GraphQL query variables ($project, $item) are intentionally literal
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

PROJECT_ID=$(harness_project_id)

gh api graphql -f query='
  mutation($project: ID!, $item: ID!) {
    archiveProjectV2Item(input: { projectId: $project, itemId: $item }) {
      item { id isArchived }
    }
  }
' -f project="$PROJECT_ID" -f item="$ITEM_ID"
