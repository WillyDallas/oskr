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

OWNER=$(harness_config_get '.github.owner')
REPO=$(harness_config_get '.github.repo')
PROJECT_NUMBER=$(harness_config_get '.github.project_number')

# shellcheck disable=SC2016
ITEM_ID=$(gh api graphql -f query='
  query($owner: String!, $repo: String!, $number: Int!) {
    repository(owner: $owner, name: $repo) {
      issue(number: $number) {
        projectItems(first: 10) {
          nodes {
            id
            project { number }
          }
        }
      }
    }
  }
' -F owner="$OWNER" -F repo="$REPO" -F number="$ISSUE_NUMBER" \
  --jq ".data.repository.issue.projectItems.nodes[] | select(.project.number == $PROJECT_NUMBER) | .id")

if [[ -z "$ITEM_ID" ]]; then
  echo "find-item: issue #$ISSUE_NUMBER is not on project #$PROJECT_NUMBER" >&2
  exit 1
fi

echo "$ITEM_ID"
