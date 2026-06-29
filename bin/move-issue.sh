#!/usr/bin/env bash
# Moves a GitHub Project item to a new status column.
# Usage: ./scripts/move-issue.sh <ITEM_ID> <COLUMN_NAME>
# Example: ./scripts/move-issue.sh "PVTI_abc123" "Planning"
#
# Optional env (token-report integration):
#   HARNESS_ISSUE_NUMBER  — issue number being moved
#   HARNESS_TRIGGER_SLUG  — overrides slug derivation
#   HARNESS_TOKEN_REPORT  — "off" to skip the reporter entirely

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/harness-lib.sh"

ITEM_ID="${1:?usage: move-issue.sh <ITEM_ID> <COLUMN_NAME>}"
COLUMN="${2:?usage: move-issue.sh <ITEM_ID> <COLUMN_NAME>}"

TOKEN_REPORT_SCRIPT="$SCRIPT_DIR/token-report.sh"
if [[ "${HARNESS_TOKEN_REPORT:-on}" != "off" && -x "$TOKEN_REPORT_SCRIPT" ]]; then
  ISSUE_NUM="${HARNESS_ISSUE_NUMBER:-}"
  TRIGGER_SLUG="${HARNESS_TRIGGER_SLUG:-}"

  if [[ -z "$ISSUE_NUM" ]]; then
    ISSUE_NUM=$(blacksmith_item_issue_number "$ITEM_ID" 2>/dev/null || true)
  fi

  if [[ -z "$TRIGGER_SLUG" ]]; then
    slug=$(printf '%s' "$COLUMN" | tr '[:upper:]' '[:lower:]' | tr ' ' '_')
    case "$slug" in
      needs_input|approval|in_review) TRIGGER_SLUG="$slug" ;;
      *) TRIGGER_SLUG="" ;;
    esac
  fi

  if [[ -n "$ISSUE_NUM" && -n "$TRIGGER_SLUG" ]]; then
    "$TOKEN_REPORT_SCRIPT" --issue "$ISSUE_NUM" --trigger "$TRIGGER_SLUG" || true
  fi
fi

blacksmith_move_issue "$ITEM_ID" "$COLUMN"
