#!/usr/bin/env bash
# shellcheck disable=SC1091
# SC1091: sourced files (check-budget.sh, harness-lib.sh) aren't followed without -x
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
# Plugin-mode invocation:
#   The script and lib live in oskr's bin/ (OSKR_HOME), but PROJECT_DIR is
#   the consumer's repo (CWD by default, override via OSKR_PROJECT_DIR).
#
# Usage (from inside a consumer repo with harness-config.json):
#   dispatch-loop.sh                      # Run with defaults
#   dispatch-loop.sh --idle-interval 600  # Poll every 10min when idle or over pace
#   dispatch-loop.sh --max-dispatches 5   # Stop after 5 dispatches
#
# Stop with Ctrl+C or kill the process.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OSKR_HOME="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_DIR="${OSKR_PROJECT_DIR:-$PWD}"
LOG_DIR="$PROJECT_DIR/logs"
mkdir -p "$LOG_DIR"

# Sanity: PROJECT_DIR must contain harness-config.json (otherwise we're not in a consumer)
if [[ ! -f "$PROJECT_DIR/harness-config.json" ]]; then
  echo "[loop] ERROR: $PROJECT_DIR has no harness-config.json — not an oskr-managed project" >&2
  echo "[loop] cd into the consumer's repo and re-run, or set OSKR_PROJECT_DIR to its path." >&2
  exit 1
fi

# harness-lib reads config from CWD or HARNESS_CONFIG env — point it at the consumer
export HARNESS_CONFIG="$PROJECT_DIR/harness-config.json"

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

# Base branch from harness-config; default to main
BASE_BRANCH=$(harness_config_get '.base_branch' 2>/dev/null || echo "main")
[[ -n "$BASE_BRANCH" && "$BASE_BRANCH" != "null" ]] || BASE_BRANCH="main"

has_actionable_work() {
  local count
  count=$(harness_count_actionable)
  [[ "$count" -gt 0 ]]
}

# Ensure the consumer repo is on its configured base branch. Called before each
# dispatch (so the agent starts clean) and after (so any feature-branch checkout
# an agent left behind is restored). Refuses to clobber uncommitted tracked
# changes — returns non-zero and the caller skips the cycle.
ensure_on_base_branch() {
  local context="$1"
  local current
  current=$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null)
  if [[ "$current" == "$BASE_BRANCH" ]]; then
    return 0
  fi
  log "[branch-check] $context: on '$current', switching to $BASE_BRANCH"
  if ! git -C "$PROJECT_DIR" diff --quiet || ! git -C "$PROJECT_DIR" diff --cached --quiet; then
    log "[branch-check] $context: REFUSED — uncommitted tracked changes on '$current'; manual cleanup required"
    return 1
  fi
  if ! git -C "$PROJECT_DIR" checkout "$BASE_BRANCH" >> "$LOG_DIR/dispatcher.log" 2>&1; then
    log "[branch-check] $context: checkout $BASE_BRANCH FAILED"
    return 1
  fi
  log "[branch-check] $context: switched to $BASE_BRANCH"
  return 0
}

log "================================================================"
log "SESSION START: dispatch loop (project=$PROJECT_DIR, base=$BASE_BRANCH, idle_interval=${IDLE_INTERVAL}s, max=${MAX_DISPATCHES:-unlimited}) pid=$$"
log "================================================================"

# Export so board-dispatcher.sh can find the prompt file + spawn claude with the plugin
export OSKR_HOME
export OSKR_PROJECT_DIR="$PROJECT_DIR"

while true; do
  if check_budget; then
    if has_actionable_work; then
      if ! ensure_on_base_branch "pre-dispatch"; then
        log "SKIPPED: branch-check failed, polling in ${IDLE_INTERVAL}s"
        sleep "$IDLE_INTERVAL"
        continue
      fi
      log "DISPATCHING: running board-dispatcher.sh"
      DISPATCH_RC=0
      "$SCRIPT_DIR/board-dispatcher.sh" || DISPATCH_RC=$?

      ensure_on_base_branch "post-dispatch" || log "[branch-check] post-dispatch: could not restore $BASE_BRANCH — next cycle will re-check"

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
