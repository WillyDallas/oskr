#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2016
# SC1091: harness-lib.sh isn't followed by shellcheck without -x
# SC2016: GraphQL query variables ($owner, $repo, $number, $after, $actionable) are intentionally literal, not shell expansions
# Board dispatcher — invoked by scripts/dispatch-loop.sh for each dispatch cycle.
# Queries the GitHub Projects board for actionable issues and passes the board
# state to Claude, which picks the next issue and runs the matching workflow.
#
# Budget gating lives upstream in dispatch-loop.sh (via scripts/check-budget.sh).
# This script assumes the caller has already cleared the pace gate.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OSKR_HOME="${OSKR_HOME:-$(cd "$SCRIPT_DIR/.." && pwd)}"
PROJECT_DIR="${OSKR_PROJECT_DIR:-$PWD}"
LOG_DIR="$PROJECT_DIR/logs"
mkdir -p "$LOG_DIR"

# Sanity check (dispatch-loop already validates, but board-dispatcher may be invoked standalone)
if [[ ! -f "$PROJECT_DIR/harness-config.json" ]]; then
  echo "[dispatcher] ERROR: $PROJECT_DIR has no harness-config.json" >&2
  exit 1
fi
export HARNESS_CONFIG="$PROJECT_DIR/harness-config.json"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_DIR/dispatcher.log"
}

source "$SCRIPT_DIR/harness-lib.sh"

OWNER=$(harness_config_get '.github.owner') || { log "ERROR: missing .github.owner in harness-config.json"; exit 1; }
REPO=$(harness_config_get '.github.repo') || { log "ERROR: missing .github.repo in harness-config.json"; exit 1; }
PROJECT_NUMBER=$(harness_config_get '.github.project_number') || { log "ERROR: missing .github.project_number in harness-config.json"; exit 1; }

# Build the JSON array of actionable column display names from workflow.actionable_columns.
# _harness_display_name_for honors any aliases in workflow.column_names; dispatcher
# is the only consumer of that private helper.
ACTIONABLE_NAMES_JSON=$(
  while IFS= read -r slug; do
    _harness_display_name_for "$slug"
  done < <(harness_config_get_array '.workflow.actionable_columns') \
    | jq -R . | jq -s .
) || { log "ERROR: failed to resolve workflow.actionable_columns"; exit 1; }

# --- Query the board (paginated) ---
#
# Accumulate one JSON node per line in a temp file, then assemble into a single
# BOARD_STATE blob matching the shape Claude expects downstream.
NODES_FILE=$(mktemp -t board-dispatcher.XXXXXX.jsonl)
trap 'rm -f "$NODES_FILE"' EXIT

AFTER="null"
BOARD_TOTAL=0
while :; do
  PAGE=$(gh api graphql -f query='
    query($owner: String!, $repo: String!, $number: Int!, $after: String) {
      repository(owner: $owner, name: $repo) {
        projectV2(number: $number) {
          items(first: 100, after: $after) {
            totalCount
            pageInfo { hasNextPage endCursor }
            nodes {
              id
              status: fieldValueByName(name: "Status") {
                ... on ProjectV2ItemFieldSingleSelectValue { name }
              }
              priority: fieldValueByName(name: "Priority") {
                ... on ProjectV2ItemFieldSingleSelectValue { name }
              }
              category: fieldValueByName(name: "Category") {
                ... on ProjectV2ItemFieldSingleSelectValue { name }
              }
              content {
                ... on Issue {
                  number
                  title
                  createdAt
                  body
                  assignees(first: 5) { nodes { login } }
                  comments(last: 5) { nodes { body } }
                  labels(first: 10) { nodes { name } }
                  blocking(first: 1) { totalCount }
                  blockedBy(first: 1) { totalCount }
                }
              }
            }
          }
        }
      }
    }
  ' -F owner="$OWNER" -F repo="$REPO" -F number="$PROJECT_NUMBER" -F after="$AFTER" 2>/dev/null) || {
    log "ERROR: failed to query board (page after=$AFTER)"
    exit 1
  }

  printf '%s' "$PAGE" | jq -c '.data.repository.projectV2.items.nodes[]' >> "$NODES_FILE"
  BOARD_TOTAL=$(echo "$PAGE" | jq '.data.repository.projectV2.items.totalCount')

  HAS_NEXT=$(echo "$PAGE" | jq -r '.data.repository.projectV2.items.pageInfo.hasNextPage')
  if [[ "$HAS_NEXT" != "true" ]]; then break; fi
  AFTER=$(echo "$PAGE" | jq -r '.data.repository.projectV2.items.pageInfo.endCursor')
done

BOARD_STATE=$(jq -s '{data: {repository: {projectV2: {items: {totalCount: '"$BOARD_TOTAL"', nodes: .}}}}}' "$NODES_FILE")
BOARD_RETURNED=$(echo "$BOARD_STATE" | jq '.data.repository.projectV2.items.nodes | length')

if [[ "$BOARD_TOTAL" -ne "$BOARD_RETURNED" ]]; then
  log "ERROR: pagination assembled ${BOARD_RETURNED} items but totalCount=${BOARD_TOTAL}"
  exit 1
fi

# --- Rank candidates ---
# Filter to items in actionable columns (excluding loop-skip labeled), then sort by:
#   1. Priority: High < Medium < Low < null (clear all of a priority tier before dropping)
#   2. Status: Ready < Planning < Research (within tier, farthest-along first)
#   3. Blocking count: descending (unblock the most work first)
#   4. Age: oldest createdAt first (FIFO tiebreak, prevents starvation)
RANKED_CANDIDATES=$(echo "$BOARD_STATE" | jq --argjson actionable "$ACTIONABLE_NAMES_JSON" '
  [.data.repository.projectV2.items.nodes[]
    | select(.content != null)
    | select(.status.name as $n | $actionable | index($n))
    | select(((.content.labels.nodes // []) | map(.name) | index("loop-skip")) | not)
    | {
        rank: 0,
        number: .content.number,
        title: .content.title,
        status: .status.name,
        priority: (.priority.name // null),
        blocking: .content.blocking.totalCount,
        blockedBy: .content.blockedBy.totalCount,
        createdAt: .content.createdAt,
        _s: (if .status.name == "Ready" then 1 elif .status.name == "Planning" then 2 else 3 end),
        _p: (if .priority.name == "High" then 1 elif .priority.name == "Medium" then 2 elif .priority.name == "Low" then 3 else 4 end),
        _b: (- .content.blocking.totalCount)
      }
  ]
  | sort_by([._p, ._s, ._b, .createdAt])
  | to_entries
  | map(.value + {rank: (.key + 1)} | del(._s, ._p, ._b))
')

TOP_SUMMARY=$(echo "$RANKED_CANDIDATES" | jq -r '
  .[0:3]
  | map("\(.rank):#\(.number)(\(.status)/\(.priority // "none")/blocking=\(.blocking)/created=\(.createdAt[0:10]))")
  | join(" ")
')
TOTAL_COUNT=$(echo "$RANKED_CANDIDATES" | jq 'length')
if [[ "$TOTAL_COUNT" -eq 0 ]]; then
  log "[select] RANKED no candidates (actionable columns empty after loop-skip filter)"
else
  log "[select] RANKED total=${TOTAL_COUNT} top=${TOP_SUMMARY}"
fi

log "DISPATCH: queried board, passing to Claude (plugin-dir=$OSKR_HOME)"

# --- Dispatch to Claude ---
# Run in the consumer's project dir so CWD-based discovery (CLAUDE.md walk-up,
# git context, harness-config.json) targets the right project. Spawn with
# --plugin-dir so the inner session has access to /oskr:* skills and agents.
cd "$PROJECT_DIR"

CLAUDE_OUTPUT=$(claude -p "$(cat "$OSKR_HOME/prompts/board-dispatcher.md")

Current board state:
$BOARD_STATE

Ranked candidates (walk in ascending rank — pick the first eligible after applying comment-based filters from the prompt):
$RANKED_CANDIDATES
" \
  --plugin-dir "$OSKR_HOME" \
  --allowedTools "Read,Write,Edit,Glob,Grep,WebSearch,WebFetch,Bash(gh *),Bash(git *),Bash(find-item.sh*),Bash(move-issue.sh*),Bash(source *),Bash(bash *),Bash(chmod *),Agent,Skill" \
  --max-turns 200 \
  --max-budget-usd 25.00 \
  --output-format json 2>&1)

echo "$CLAUDE_OUTPUT" >> "$LOG_DIR/dispatcher-output.log"

# Parse the SELECTED_ISSUE: marker from Claude's reply (last match wins).
# Three outcomes:
#   - "SELECTED_ISSUE: <n>" → dispatch ran, selected issue n
#   - "SELECTED_ISSUE: none" → all candidates filtered by comment-based rules; signal upstream via exit 10
#   - (no marker) → Claude output shape changed or got truncated; log and let the loop continue
SELECTED_NUM=$(echo "$CLAUDE_OUTPUT" | grep -oE 'SELECTED_ISSUE: *[0-9]+' | tail -1 | grep -oE '[0-9]+$' || true)

if [[ -n "${SELECTED_NUM:-}" ]]; then
  CHOSE_INFO=$(echo "$RANKED_CANDIDATES" | jq -r --arg n "$SELECTED_NUM" '
    (map(select(.number == ($n | tonumber))) | .[0]) as $c
    | if $c == null then "(not in ranked list — unexpected)"
      else "rank=\($c.rank) status=\($c.status) priority=\($c.priority // "none") blocking=\($c.blocking) age=\($c.createdAt[0:10])"
      end
  ' 2>/dev/null)
  log "[select] CHOSE issue=#${SELECTED_NUM} ${CHOSE_INFO}"
  log "COMPLETE: dispatch cycle finished"
elif echo "$CLAUDE_OUTPUT" | grep -qE 'SELECTED_ISSUE: *none\b'; then
  log "[select] NO_ACTIONABLE: all candidates filtered by comment-based rules"
  log "COMPLETE: dispatch cycle finished"
  exit 10
else
  log "[select] CHOSE unknown (no SELECTED_ISSUE: marker in Claude output)"
  log "COMPLETE: dispatch cycle finished"
fi
