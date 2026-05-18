#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2016
# SC1091: sourced files (check-budget.sh, harness-lib.sh) aren't followed without -x
# SC2016: GraphQL query variables ($owner, $repo, $number) are intentionally literal, not shell expansions
# Long-running dispatch loop with ccburn pace-aware skipping.
#
# Processes actionable issues continuously. Before each dispatch, calls the
# shared check-budget.sh helper: it gates on session+weekly pace (no caps),
# auto-refreshing stale ccburn data via `claude -p`. When pace is exceeded
# or data can't be fetched, the loop skips and polls again after IDLE_INTERVAL.
#
# Actionable columns are read from harness-config.json (.workflow.actionable_columns)
# and resolved to display names via _harness_display_name_for. The list of
# columns considered "actionable" is therefore project-configurable.
#
# Usage:
#   ./scripts/dispatch-loop.sh                      # Run with defaults
#   ./scripts/dispatch-loop.sh --idle-interval 600  # Poll every 10min when idle or over pace
#   ./scripts/dispatch-loop.sh --max-dispatches 5   # Stop after 5 dispatches
#
# Stop with Ctrl+C or kill the process.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$PROJECT_DIR/logs"
mkdir -p "$LOG_DIR"

IDLE_INTERVAL=${IDLE_INTERVAL:-600}
MAX_DISPATCHES=${MAX_DISPATCHES:-0}

while [[ $# -gt 0 ]]; do
  case $1 in
    --idle-interval) IDLE_INTERVAL="$2"; shift 2 ;;
    --max-dispatches) MAX_DISPATCHES="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

dispatch_count=0

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') [loop] $1" >> "$LOG_DIR/dispatcher.log"
}

source "$SCRIPT_DIR/harness-lib.sh"
source "$SCRIPT_DIR/check-budget.sh"

has_actionable_work() {
  local owner repo number actionable_json count
  owner=$(harness_config_get '.github.owner') || return 1
  repo=$(harness_config_get '.github.repo') || return 1
  number=$(harness_config_get '.github.project_number') || return 1
  actionable_json=$(
    while IFS= read -r slug; do
      _harness_display_name_for "$slug"
    done < <(harness_config_get_array '.workflow.actionable_columns') \
      | jq -R . | jq -sc .
  )
  count=$(gh api graphql -f query='
    query($owner: String!, $repo: String!, $number: Int!) {
      repository(owner: $owner, name: $repo) {
        projectV2(number: $number) {
          items(first: 100) {
            nodes {
              status: fieldValueByName(name: "Status") {
                ... on ProjectV2ItemFieldSingleSelectValue { name }
              }
              content {
                ... on Issue {
                  labels(first: 10) { nodes { name } }
                }
              }
            }
          }
        }
      }
    }
  ' -F owner="$owner" -F repo="$repo" -F number="$number" 2>/dev/null \
    | jq --argjson actionable "$actionable_json" '
        [.data.repository.projectV2.items.nodes[]
          | select(.status.name as $n | $actionable | index($n))
          | select(((.content.labels.nodes // []) | map(.name) | index("loop-skip")) | not)
        ] | length
      ' 2>/dev/null || echo "0")
  [[ "$count" -gt 0 ]]
}

# Ensure the repo is on the development branch. Called before each dispatch (so
# the agent starts clean) and after (so any feature-branch checkout an agent
# left behind is restored). Refuses to clobber uncommitted tracked changes —
# returns non-zero and the caller skips the cycle.
ensure_on_development() {
  local context="$1"
  local current
  current=$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null)
  if [[ "$current" == "development" ]]; then
    return 0
  fi
  log "[branch-check] $context: on '$current', switching to development"
  if ! git -C "$PROJECT_DIR" diff --quiet || ! git -C "$PROJECT_DIR" diff --cached --quiet; then
    log "[branch-check] $context: REFUSED — uncommitted tracked changes on '$current'; manual cleanup required"
    return 1
  fi
  if ! git -C "$PROJECT_DIR" checkout development >> "$LOG_DIR/dispatcher.log" 2>&1; then
    log "[branch-check] $context: checkout development FAILED"
    return 1
  fi
  log "[branch-check] $context: switched to development"
  return 0
}

log "================================================================"
log "SESSION START: dispatch loop (idle_interval=${IDLE_INTERVAL}s, max=${MAX_DISPATCHES:-unlimited}) pid=$$"
log "================================================================"

while true; do
  if check_budget; then
    if has_actionable_work; then
      if ! ensure_on_development "pre-dispatch"; then
        log "SKIPPED: branch-check failed, polling in ${IDLE_INTERVAL}s"
        sleep "$IDLE_INTERVAL"
        continue
      fi
      log "DISPATCHING: running board-dispatcher.sh"
      DISPATCH_RC=0
      "$SCRIPT_DIR/board-dispatcher.sh" || DISPATCH_RC=$?

      ensure_on_development "post-dispatch" || log "[branch-check] post-dispatch: could not restore development — next cycle will re-check"

      if [[ "$DISPATCH_RC" -eq 10 ]]; then
        log "IDLE: dispatcher found nothing actionable (all candidates skip-marked), polling in ${IDLE_INTERVAL}s"
        sleep "$IDLE_INTERVAL"
        continue
      elif [[ "$DISPATCH_RC" -ne 0 ]]; then
        log "DISPATCH EXITED: code $DISPATCH_RC"
      fi

      dispatch_count=$((dispatch_count + 1))
      log "COMPLETED: dispatch #$dispatch_count"

      if [[ "$MAX_DISPATCHES" -gt 0 && "$dispatch_count" -ge "$MAX_DISPATCHES" ]]; then
        log "STOPPED: reached max dispatches ($MAX_DISPATCHES)"
        exit 0
      fi
    else
      log "IDLE: no actionable issues on board, polling in ${IDLE_INTERVAL}s"
      sleep "$IDLE_INTERVAL"
    fi
  else
    if [[ "${BUDGET_WAIT_SECONDS:-0}" -gt 0 ]]; then
      log "SKIPPED: pace gate — waiting ${BUDGET_WAIT_SECONDS}s for pace to recover"
      sleep "$BUDGET_WAIT_SECONDS"
    else
      log "SKIPPED: fetch failed, polling in ${IDLE_INTERVAL}s"
      sleep "$IDLE_INTERVAL"
    fi
  fi
done
