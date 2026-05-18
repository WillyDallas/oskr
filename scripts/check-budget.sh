#!/usr/bin/env bash
# shellcheck disable=SC2034
# SC2034: BUDGET_WAIT_SECONDS is consumed by the caller (dispatch-loop.sh)
# scripts/check-budget.sh
#
# Shared budget-check helper. Sourceable from dispatch-loop.sh, runnable standalone for debugging.
#
# Gate chain (first failure short-circuits):
#   1. fetch   — ccburn --json --once returns parseable JSON with numeric utilization
#   2. fresh   — .timestamp within 5 minutes; on stale/empty, refresh via `claude -p 'ready'` once
#   3. pace-s  — session.utilization <= session.budget_pace
#   4. pace-w  — weekly.utilization <= weekly.budget_pace
#
# Emits two log lines on every call:
#   [budget] GATES fetch=ok(age=8s) pace-s=ok(u=0.21,p=0.20) pace-w=FAIL(u=0.82,p=0.55)
#   [budget] DECISION SKIP reason=OFF_PACE_WEEKLY u=82% p=55%
#
# Exit codes / return codes:
#   0 = OK (dispatch allowed)
#   1 = SKIP (some gate failed — caller should poll IDLE_INTERVAL and retry)

set -euo pipefail

MAX_AGE_SECONDS=300
PACE_BUFFER="0.01"       # ends up 1% under pace after waiting
MIN_WAIT_SECONDS=60
MAX_WAIT_SECONDS=3600    # caps weekly's multi-hour recovery waits

usage() {
  cat <<'EOF'
Usage: check-budget.sh [--help]

Sourceable + standalone budget check using ccburn pace data.

When sourced, exposes:
  check_budget()  — prints [budget] GATES and [budget] DECISION log lines
                    and returns 0 (OK) or 1 (SKIP).

When executed directly, runs check_budget once and exits with its return code.

Gates:
  fetch   ccburn --json --once returns valid JSON
  fresh   .timestamp within 5 min; auto-refreshes via `claude -p 'ready'` on stale
  pace-s  session utilization <= session budget_pace
  pace-w  weekly  utilization <= weekly  budget_pace

Exit codes: 0 = OK, 1 = SKIP
EOF
}

# If caller didn't define a `log` function, fall back to stderr.
if ! declare -F log >/dev/null 2>&1; then
  log() { echo "$1" >&2; }
fi

iso_to_epoch() {
  local ts="$1" clean
  clean="${ts%%+*}"
  clean="${clean%%.*}"
  clean="${clean%Z}"
  date -u -j -f "%Y-%m-%dT%H:%M:%S" "$clean" +%s 2>/dev/null \
    || date -d "$ts" +%s 2>/dev/null \
    || echo ""
}

format_age() {
  local secs="$1"
  if (( secs < 60 )); then
    echo "${secs}s"
  elif (( secs < 3600 )); then
    echo "$((secs / 60))m"
  else
    echo "$((secs / 3600))h$((secs % 3600 / 60))m"
  fi
}

# Portable timeout wrapper — GNU `timeout` is not on default macOS PATH.
# Runs `$2...` with a `$1`-second wall-clock limit. Returns the command's
# exit code, or 124 if the limit expired (matches GNU `timeout` convention).
run_with_timeout() {
  local secs="$1"; shift
  "$@" &
  local pid=$!
  local elapsed=0
  while kill -0 "$pid" 2>/dev/null; do
    if (( elapsed >= secs )); then
      kill -TERM "$pid" 2>/dev/null || true
      sleep 1
      kill -KILL "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 124
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  wait "$pid" 2>/dev/null
}

# Validates a ccburn JSON blob.
# Prints age in seconds on stdout when the JSON is structurally valid (even if stale).
# Return codes:
#   0 = valid and fresh
#   1 = not a JSON object (malformed / empty)
#   2 = missing or non-numeric utilization / budget_pace
#   3 = missing or unparseable timestamp
#   4 = valid structure but stale (age > MAX_AGE_SECONDS)
is_valid_and_fresh() {
  local json="$1"
  [[ -n "$json" ]] || return 1
  echo "$json" | jq -e 'type == "object"' >/dev/null 2>&1 || return 1

  local s_util w_util s_pace w_pace
  s_util=$(echo "$json" | jq -r '.limits.session.utilization // "null"')
  w_util=$(echo "$json" | jq -r '.limits.weekly.utilization // "null"')
  s_pace=$(echo "$json" | jq -r '.limits.session.budget_pace // "null"')
  w_pace=$(echo "$json" | jq -r '.limits.weekly.budget_pace // "null"')

  [[ "$s_util" =~ ^[0-9]+(\.[0-9]+)?$ ]] || return 2
  [[ "$w_util" =~ ^[0-9]+(\.[0-9]+)?$ ]] || return 2
  [[ "$s_pace" =~ ^[0-9]+(\.[0-9]+)?$ ]] || return 2
  [[ "$w_pace" =~ ^[0-9]+(\.[0-9]+)?$ ]] || return 2

  local ts ts_epoch now age
  ts=$(echo "$json" | jq -r '.timestamp // "null"')
  [[ "$ts" != "null" && -n "$ts" ]] || return 3

  ts_epoch=$(iso_to_epoch "$ts")
  [[ -n "$ts_epoch" ]] || return 3

  now=$(date -u +%s)
  age=$((now - ts_epoch))
  echo "$age"
  (( age <= MAX_AGE_SECONDS )) || return 4
  return 0
}

# Fetches a valid + fresh budget JSON, with one refresh retry on stale/empty.
# On success, sets globals: BUDGET_JSON, BUDGET_AGE, BUDGET_REFRESH_SECS (0 if no refresh).
# Returns 0 on success, 1 if still invalid/stale after refresh.
fetch_budget() {
  BUDGET_JSON=""
  BUDGET_AGE=0
  BUDGET_REFRESH_SECS=0

  local json age rc

  json=$(ccburn --json --once 2>/dev/null || true)
  if age=$(is_valid_and_fresh "$json"); then
    BUDGET_JSON="$json"
    BUDGET_AGE="$age"
    return 0
  else
    rc=$?
  fi

  local reason
  case "$rc" in
    4) reason="STALE(age=$(format_age "$age"))" ;;
    2|3) reason="EMPTY" ;;
    *) reason="INVALID" ;;
  esac
  log "[budget] GATES fetch=$reason — refreshing via \`claude -p\`"

  local refresh_start refresh_end
  refresh_start=$(date +%s)
  run_with_timeout 30 claude -p 'ready' >/dev/null 2>&1 || true
  sleep 2
  refresh_end=$(date +%s)
  BUDGET_REFRESH_SECS=$((refresh_end - refresh_start))
  log "[budget] REFRESH completed in ${BUDGET_REFRESH_SECS}s"

  json=$(ccburn --json --once 2>/dev/null || true)
  if age=$(is_valid_and_fresh "$json"); then
    BUDGET_JSON="$json"
    BUDGET_AGE="$age"
    return 0
  fi

  return 1
}

# Computes seconds until pace recovers for one dimension.
# Args: $1 = utilization (0..1), $2 = budget_pace (0..1), $3 = window_hours
# Echoes: wait seconds (ceil((u - p + PACE_BUFFER) * window_secs)), clamped to [MIN,MAX].
# Caller should only invoke when u > p (pace is failing for this dimension).
compute_pace_wait() {
  local util="$1" pace="$2" window_hours="$3"
  local window_secs
  window_secs=$(echo "$window_hours * 3600" | bc -l)
  local secs
  secs=$(echo "($util - $pace + $PACE_BUFFER) * $window_secs" | bc -l)
  # Round up to whole seconds
  secs=$(printf '%.0f' "$(echo "$secs + 0.5" | bc -l)")
  (( secs < MIN_WAIT_SECONDS )) && secs="$MIN_WAIT_SECONDS"
  (( secs > MAX_WAIT_SECONDS )) && secs="$MAX_WAIT_SECONDS"
  echo "$secs"
}

# The main public entry point.
# Emits [budget] GATES and [budget] DECISION log lines.
# Globals set: BUDGET_WAIT_SECONDS — seconds the caller should sleep.
#   0 on OK (no wait needed — dispatch immediately)
#   0 on FETCH_FAIL (caller should fall back to its own IDLE_INTERVAL)
#   computed value on OFF_PACE_* (dynamic wait until pace recovers, bounded by MIN/MAX)
# Returns 0 = OK (dispatch allowed), 1 = SKIP.
check_budget() {
  BUDGET_WAIT_SECONDS=0

  if ! fetch_budget; then
    log "[budget] DECISION SKIP reason=FETCH_FAIL"
    return 1
  fi

  local s_util s_pace w_util w_pace s_win w_win
  s_util=$(echo "$BUDGET_JSON" | jq -r '.limits.session.utilization')
  s_pace=$(echo "$BUDGET_JSON" | jq -r '.limits.session.budget_pace')
  w_util=$(echo "$BUDGET_JSON" | jq -r '.limits.weekly.utilization')
  w_pace=$(echo "$BUDGET_JSON" | jq -r '.limits.weekly.budget_pace')
  s_win=$(echo "$BUDGET_JSON" | jq -r '.limits.session.window_hours')
  w_win=$(echo "$BUDGET_JSON" | jq -r '.limits.weekly.window_hours')

  local s_ok w_ok
  s_ok=$(echo "$s_util <= $s_pace" | bc -l)
  w_ok=$(echo "$w_util <= $w_pace" | bc -l)

  local s_state="ok" w_state="ok"
  [[ "$s_ok" == "0" ]] && s_state="FAIL"
  [[ "$w_ok" == "0" ]] && w_state="FAIL"

  log "[budget] GATES fetch=ok(age=$(format_age "$BUDGET_AGE")) pace-s=${s_state}(u=${s_util},p=${s_pace}) pace-w=${w_state}(u=${w_util},p=${w_pace})"

  # Both pace gates pass → dispatch
  if [[ "$s_state" == "ok" && "$w_state" == "ok" ]]; then
    log "[budget] DECISION OK"
    return 0
  fi

  # Compute wait for whichever gates failed; use the larger (both must recover)
  local s_wait=0 w_wait=0 wait_secs reason u_pct p_pct
  if [[ "$s_state" == "FAIL" ]]; then
    s_wait=$(compute_pace_wait "$s_util" "$s_pace" "$s_win")
  fi
  if [[ "$w_state" == "FAIL" ]]; then
    w_wait=$(compute_pace_wait "$w_util" "$w_pace" "$w_win")
  fi

  # Binding constraint = whichever needs the longer wait
  if (( s_wait >= w_wait )); then
    wait_secs="$s_wait"
    reason="OFF_PACE_SESSION"
    u_pct=$(printf '%.0f' "$(echo "$s_util * 100" | bc -l)")
    p_pct=$(printf '%.0f' "$(echo "$s_pace * 100" | bc -l)")
  else
    wait_secs="$w_wait"
    reason="OFF_PACE_WEEKLY"
    u_pct=$(printf '%.0f' "$(echo "$w_util * 100" | bc -l)")
    p_pct=$(printf '%.0f' "$(echo "$w_pace * 100" | bc -l)")
  fi

  local capped_note=""
  (( wait_secs >= MAX_WAIT_SECONDS )) && capped_note=" (capped at ${MAX_WAIT_SECONDS}s)"
  BUDGET_WAIT_SECONDS="$wait_secs"
  log "[budget] DECISION SKIP reason=${reason} u=${u_pct}% p=${p_pct}% wait=${wait_secs}s${capped_note}"
  return 1
}

main() {
  case "${1:-}" in
    --help|-h) usage; exit 0 ;;
  esac

  if ! command -v ccburn >/dev/null 2>&1; then
    echo "[budget] ERROR: ccburn not installed" >&2
    exit 1
  fi

  if check_budget; then
    exit 0
  else
    exit 1
  fi
}

if [[ "${BASH_SOURCE[0]:-}" = "$0" ]]; then
  main "$@"
fi
