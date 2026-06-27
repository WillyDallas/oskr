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

# Backend identity (owner/repo/project_number) is read inside harness-lib's
# backend functions, which fail loudly if config is missing.

# Base branch from harness-config; default main. Used by the post-run completion check.
BASE_BRANCH=$(blacksmith_config_get '.base_branch' 2>/dev/null || echo "main")
[[ -n "$BASE_BRANCH" && "$BASE_BRANCH" != "null" ]] || BASE_BRANCH="main"
# In Progress display name (honors workflow.column_names aliases) — used by the
# candidate filter (dropped-work recovery) and the completion check.
INPROGRESS_NAME=$(_blacksmith_display_name_for in_progress)

# Build the JSON array of actionable column display names from workflow.actionable_columns.
# _blacksmith_display_name_for honors any aliases in workflow.column_names; dispatcher
# is the only consumer of that private helper.
ACTIONABLE_NAMES_JSON=$(
  while IFS= read -r slug; do
    _blacksmith_display_name_for "$slug"
  done < <(blacksmith_config_get_array '.workflow.actionable_columns') \
    | jq -R . | jq -s .
) || { log "ERROR: failed to resolve workflow.actionable_columns"; exit 1; }

# --- Query the board ---
# blacksmith_list_board paginates and assembles the GitHub-native board blob.
BOARD_STATE=$(blacksmith_list_board) || { log "ERROR: failed to query board"; exit 1; }
BOARD_TOTAL=$(echo "$BOARD_STATE" | jq '.data.repository.projectV2.items.totalCount')
BOARD_RETURNED=$(echo "$BOARD_STATE" | jq '.data.repository.projectV2.items.nodes | length')

if [[ "$BOARD_TOTAL" -ne "$BOARD_RETURNED" ]]; then
  log "ERROR: pagination assembled ${BOARD_RETURNED} items but totalCount=${BOARD_TOTAL}"
  exit 1
fi

# --- Rank candidates ---
# Filter to items in actionable columns, plus In Progress issues labeled
# dispatch-incomplete (a prior dispatch died mid-implementation — resume them
# first, they are the cheapest completions). loop-skip labeled issues are
# excluded everywhere. Sort by:
#   1. Priority: High < Medium < Low < null (clear all of a priority tier before dropping)
#   2. Status: In Progress (recovery) < actionable columns (farthest-along first)
#   3. Blocking count: descending (unblock the most work first)
#   4. Age: oldest createdAt first (FIFO tiebreak, prevents starvation)
RANKED_CANDIDATES=$(echo "$BOARD_STATE" | jq --argjson actionable "$ACTIONABLE_NAMES_JSON" --arg inprogress "$INPROGRESS_NAME" '
  [.data.repository.projectV2.items.nodes[]
    | select(.content != null)
    | select(
        (.status.name as $n | $actionable | index($n))
        or (.status.name == $inprogress
            and (((.content.labels.nodes // []) | map(.name) | index("dispatch-incomplete")) != null))
      )
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
        _s: (if .status.name == $inprogress then 0 elif .status.name == "Ready" then 1 elif .status.name == "Planning" then 2 else 3 end),
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

# Snapshot feature branches so the post-run completion check can spot branches
# created during this dispatch even when the SELECTED_ISSUE marker is missing
# (the marker prints at the END of a healthy run — it is absent in exactly the
# failure modes the check exists to catch).
BRANCHES_BEFORE=$(git -C "$PROJECT_DIR" branch --list 'feature/*' --format='%(refname:short)' | sort)

# --- Post-run completion check ---
# Serial dispatching means an issue left In Progress with no open PR after the
# run ends is dropped work (session limit hit, process killed, or the agent
# ended its turn waiting on background work — fatal in headless mode). Label it
# dispatch-incomplete and leave a resume breadcrumb; the candidate filter picks
# labeled issues up next cycle and execute-plan resumes from the branch.
# Every external call is guarded — this check must never fail the dispatch.
verify_dispatch_completion() {
  local branches_after new_branches issue_branches b n
  branches_after=$(git -C "$PROJECT_DIR" branch --list 'feature/*' --format='%(refname:short)' | sort)
  new_branches=$(comm -13 <(printf '%s\n' "$BRANCHES_BEFORE") <(printf '%s\n' "$branches_after") 2>/dev/null || true)

  # (issue, branch) pairs: every branch created this run, plus the selected
  # issue's pre-existing branch (resume runs create no new branch).
  issue_branches=""
  while IFS= read -r b; do
    [[ -z "$b" ]] && continue
    n=$(echo "$b" | sed -nE 's|^feature/([0-9]+)-.*|\1|p')
    [[ -n "$n" ]] && issue_branches+="$n $b"$'\n'
  done <<< "$new_branches"
  if [[ -n "${SELECTED_NUM:-}" ]] && ! grep -q "^${SELECTED_NUM} " <<< "$issue_branches"; then
    b=$(echo "$branches_after" | grep -m1 "^feature/${SELECTED_NUM}-" || true)
    [[ -n "$b" ]] && issue_branches+="${SELECTED_NUM} $b"$'\n'
  fi
  [[ -z "$issue_branches" ]] && return 0

  local session_id status open_prs commits comment_body
  session_id=$(printf '%s' "$CLAUDE_OUTPUT" \
    | jq -r 'if type=="array" then (.[] | select(.type=="result")) else . end | .session_id // empty' 2>/dev/null \
    | tail -n 1)

  while read -r n b; do
    [[ -z "$n" ]] && continue
    status=$(blacksmith_issue_status "$n")
    [[ "$status" != "$INPROGRESS_NAME" ]] && continue
    open_prs=$(blacksmith_pr_open_count "$b")
    [[ "$open_prs" != "0" ]] && continue

    commits=$(git -C "$PROJECT_DIR" rev-list --count "$BASE_BRANCH..$b" 2>/dev/null || echo "?")
    blacksmith_ensure_label dispatch-incomplete \
      "A dispatch died mid-implementation; resume from the branch named in the issue comment" \
      D93F0B
    blacksmith_issue_add_label "$n" dispatch-incomplete
    comment_body="## Dispatch Incomplete

A dispatch run ended without opening a PR. Partial state:

- **Branch**: \`$b\` (local-only, ${commits} commit(s) ahead of \`$BASE_BRANCH\`)
- **Session**: \`${session_id:-unknown}\` (context recoverable via \`claude -p --resume <session-id>\`)
- **Detected**: $(date '+%Y-%m-%d %H:%M:%S')

The next dispatch cycle will pick this issue up via the \`dispatch-incomplete\` label and resume from the branch (execute-plan resume mode). Remove the label to take over manually."
    blacksmith_issue_comment "$n" "$comment_body"
    log "INCOMPLETE: issue #$n left In Progress with no PR — labeled dispatch-incomplete (branch=$b session=${session_id:-unknown})"
  done <<< "$issue_branches"
  return 0
}

CLAUDE_OUTPUT=$(claude -p "$(cat "$OSKR_HOME/prompts/board-dispatcher.md")

Current board state:
$BOARD_STATE

Ranked candidates (walk in ascending rank — pick the first eligible after applying comment-based filters from the prompt):
$RANKED_CANDIDATES
" \
  --plugin-dir "$OSKR_HOME" \
  --allowedTools "Read,Write,Edit,Glob,Grep,WebSearch,WebFetch,Bash(gh *),Bash(git *),Bash(find-item.sh*),Bash(move-issue.sh*),Bash(sync-development.sh*),Bash(sync-worktree.sh*),Bash(source *),Bash(bash *),Bash(chmod *),Agent,Skill,SendMessage" \
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

# Detect dropped work (issue left In Progress with no PR) before logging the
# outcome — runs on every path, since the SELECTED_ISSUE marker is exactly what
# goes missing when a dispatch dies mid-run.
verify_dispatch_completion

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
