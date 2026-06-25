#!/usr/bin/env bash
# Look up the project item ID for a given issue number.
# Usage: ./scripts/find-item.sh <issue-number>
#
# Outputs the project item ID (PVTI_...) to stdout on success.
# Exits 1 if the issue is not on the project board, 2 on usage error.
#
# Walks issue -> projectItems (a short list per issue), so no pagination
# of the project's full item list is required. Owner/repo/project_number
# come from harness-config.json.

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <issue-number>" >&2
  exit 2
fi

ISSUE_NUMBER="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/harness-lib.sh"

ITEM_ID=$(harness_find_item "$ISSUE_NUMBER")

if [[ -z "$ITEM_ID" ]]; then
  PROJECT_NUMBER=$(harness_config_get '.github.project_number')
  echo "find-item: issue #$ISSUE_NUMBER is not on project #$PROJECT_NUMBER" >&2
  exit 1
fi

echo "$ITEM_ID"
