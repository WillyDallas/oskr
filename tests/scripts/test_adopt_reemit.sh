#!/usr/bin/env bash
# adopt-reemit.sh: re-emit a reconciled adopt plan into oskr board structure —
# 1 Epoch milestone, each phase an Area umbrella (type/umbrella + area/<slug>),
# each task a slim ## Parent/## What/## AC issue (delivery/manual) linked beneath.
# Proven hermetically via gh-shim replay (Task 4 = Epoch+umbrellas; Task 5 = tasks).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FIX="$REPO_ROOT/tests/scripts/fixtures"
source "$SCRIPT_DIR/lib/assert.sh"

SHIM_DIR=$(mktemp -d); CACHE_DIR=$(mktemp -d); trap 'rm -rf "$SHIM_DIR" "$CACHE_DIR"' EXIT
cp "$SCRIPT_DIR/lib/gh-shim.sh" "$SHIM_DIR/gh"; chmod +x "$SHIM_DIR/gh"
LOG="$SHIM_DIR/gh.log"; : > "$LOG"

PATH="$SHIM_DIR:$PATH" \
  HARNESS_CONFIG="$FIX/harness-config.sample.json" \
  GH_SHIM_CALL_LOG="$LOG" \
  GH_SHIM_FIXTURE="$FIX/gh-project-discovery.json" \
  GH_SHIM_CREATE_ISSUE_FIXTURE="$FIX/gh-create-issue.json" \
  GH_SHIM_MILESTONES_FIXTURE="$FIX/gh-milestones-adopt.json" \
  GH_SHIM_ISSUE_FIXTURE="$FIX/gh-issue-single.json" \
  XDG_CACHE_HOME="$CACHE_DIR" \
  "$REPO_ROOT/bin/adopt-reemit.sh" "$FIX/reconciled-plan.json"

# Epoch milestone resolved (found-path against gh-milestones-adopt.json -> number 1)
grep -qF 'milestones?state=all' "$LOG"          || { echo "FAIL: epoch milestone not resolved" >&2; exit 1; }
# Two Area umbrellas, each with type/umbrella + its area/<slug>
grep -qF 'title=[Area] Patient intake' "$LOG"   || { echo "FAIL: intake umbrella not created" >&2; exit 1; }
grep -qF 'title=[Area] Billing'        "$LOG"   || { echo "FAIL: billing umbrella not created" >&2; exit 1; }
grep -qF 'labels[]=type/umbrella'      "$LOG"   || { echo "FAIL: umbrella label missing" >&2; exit 1; }
grep -qF 'labels[]=area/intake'        "$LOG"   || { echo "FAIL: area/intake label missing" >&2; exit 1; }
grep -qF 'labels[]=area/billing'       "$LOG"   || { echo "FAIL: area/billing label missing" >&2; exit 1; }
# Umbrella milestone set to the Epoch (number 1)
grep -qE 'issues/42 .*milestone=1'     "$LOG"   || { echo "FAIL: umbrella milestone not set" >&2; exit 1; }
# Labels ensured before attachment
grep -qF 'label create type/umbrella'  "$LOG"   || { echo "FAIL: type/umbrella not ensured" >&2; exit 1; }
grep -qF 'label create area/intake'    "$LOG"   || { echo "FAIL: area/intake not ensured" >&2; exit 1; }

# Absent plan file fails clearly
if "$REPO_ROOT/bin/adopt-reemit.sh" /no/such/plan.json 2>/dev/null; then
  echo "FAIL: missing plan file must exit non-zero" >&2; exit 1
fi

# ---- Task arm: slim issues, linked beneath umbrellas, delivery/manual, no move ----
grep -qF 'title=Registration form' "$LOG" || { echo "FAIL: task 'Registration form' not created" >&2; exit 1; }
grep -qF 'title=Triage rules'       "$LOG" || { echo "FAIL: task 'Triage rules' not created" >&2; exit 1; }
grep -qF 'title=Invoice model'      "$LOG" || { echo "FAIL: task 'Invoice model' not created" >&2; exit 1; }
grep -qF 'labels[]=delivery/manual' "$LOG" || { echo "FAIL: task missing delivery/manual" >&2; exit 1; }
grep -qF 'label create delivery/manual' "$LOG" || { echo "FAIL: delivery/manual not ensured" >&2; exit 1; }
# Slim body contract
grep -qF '## Parent' "$LOG" || { echo "FAIL: task body missing ## Parent" >&2; exit 1; }
grep -qF '## What'   "$LOG" || { echo "FAIL: task body missing ## What" >&2; exit 1; }
grep -qF '## AC'     "$LOG" || { echo "FAIL: task body missing ## AC" >&2; exit 1; }
if grep -qF 'touches:' "$LOG"; then echo "FAIL: re-emitted task carries forbidden touches:" >&2; exit 1; fi
# Linked beneath the umbrella (native sub-issue; child DB id 9001 from gh-issue-single.json)
grep -qF 'sub_issues'       "$LOG" || { echo "FAIL: tasks not linked under umbrellas" >&2; exit 1; }
grep -qF 'sub_issue_id=9001' "$LOG" || { echo "FAIL: link did not use child DB id" >&2; exit 1; }
# Dispatch off: NO Status move into an actionable column
if grep -qF 'updateProjectV2ItemFieldValue' "$LOG"; then echo "FAIL: re-emit moved an issue (dispatch must be off)" >&2; exit 1; fi

echo "test_adopt_reemit (umbrellas): PASS"
