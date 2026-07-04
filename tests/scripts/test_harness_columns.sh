#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

SHIM_DIR=$(mktemp -d); CACHE_DIR=$(mktemp -d)
trap 'rm -rf "$SHIM_DIR" "$CACHE_DIR"' EXIT
GH_SHIM_CALL_LOG="$SHIM_DIR/gh-calls.log"
: > "$GH_SHIM_CALL_LOG"
cp "$SCRIPT_DIR/lib/gh-shim.sh" "$SHIM_DIR/gh"
chmod +x "$SHIM_DIR/gh"

# Pure vocabulary (8-column scheme; #27 T5) — no shim needed.
bash -c "
  source '$REPO_ROOT/bin/harness-lib.sh'
  [[ \$(_blacksmith_default_name_for_slug backlog)       == 'Backlog' ]]       || exit 1
  [[ \$(_blacksmith_default_name_for_slug scoping)       == 'Scoping' ]]       || exit 1
  [[ \$(_blacksmith_default_name_for_slug plan_approval) == 'Plan Approval' ]] || exit 1
  [[ \$(_blacksmith_default_name_for_slug in_review)     == 'In Review' ]]     || exit 1
  _blacksmith_default_name_for_slug research    && exit 1
  _blacksmith_default_name_for_slug needs_input && exit 1
  _blacksmith_default_name_for_slug approval    && exit 1
  exit 0
"

# Default-names case (8-column board discovery)
PATH="$SHIM_DIR:$PATH" \
  HARNESS_CONFIG="$REPO_ROOT/tests/scripts/fixtures/harness-config.sample.json" \
  GH_SHIM_CALL_LOG="$GH_SHIM_CALL_LOG" \
  GH_SHIM_FIXTURE="$REPO_ROOT/tests/scripts/fixtures/gh-project-discovery.json" \
  XDG_CACHE_HOME="$CACHE_DIR" \
  bash -c "
    source '$REPO_ROOT/bin/harness-lib.sh'
    [[ \$(_blacksmith_github_column_option_id 'Planning')      == 'opt-planning' ]]      || exit 1
    [[ \$(_blacksmith_github_column_option_id 'planning')      == 'opt-planning' ]]      || exit 1
    [[ \$(_blacksmith_github_column_option_id 'Scoping')       == 'opt-scoping' ]]       || exit 1
    [[ \$(_blacksmith_github_column_option_id 'scoping')       == 'opt-scoping' ]]       || exit 1
    [[ \$(_blacksmith_github_column_option_id 'Plan Approval') == 'opt-plan-approval' ]] || exit 1
    [[ \$(_blacksmith_github_column_option_id 'plan_approval') == 'opt-plan-approval' ]] || exit 1
    [[ \$(_blacksmith_github_column_name_for 'opt-planning')   == 'Planning' ]]          || exit 1
  "

# Unknown column → non-zero + helpful stderr
UNKNOWN_OUT=$(PATH="$SHIM_DIR:$PATH" \
  HARNESS_CONFIG="$REPO_ROOT/tests/scripts/fixtures/harness-config.sample.json" \
  GH_SHIM_CALL_LOG="$GH_SHIM_CALL_LOG" \
  GH_SHIM_FIXTURE="$REPO_ROOT/tests/scripts/fixtures/gh-project-discovery.json" \
  XDG_CACHE_HOME="$CACHE_DIR" \
  bash -c "source '$REPO_ROOT/bin/harness-lib.sh' && _blacksmith_github_column_option_id 'Nonsense'" 2>&1 || true)
printf '%s' "$UNKNOWN_OUT" | grep -qF "unknown column" || { echo FAIL: unknown column did not surface; exit 1; }

# Aliased case
CACHE_DIR2=$(mktemp -d); trap 'rm -rf "$SHIM_DIR" "$CACHE_DIR" "$CACHE_DIR2"' EXIT
PATH="$SHIM_DIR:$PATH" \
  HARNESS_CONFIG="$REPO_ROOT/tests/scripts/fixtures/harness-config.with-aliases.json" \
  GH_SHIM_CALL_LOG="$GH_SHIM_CALL_LOG" \
  GH_SHIM_FIXTURE="$REPO_ROOT/tests/scripts/fixtures/gh-project-discovery-aliased.json" \
  XDG_CACHE_HOME="$CACHE_DIR2" \
  bash -c "
    source '$REPO_ROOT/bin/harness-lib.sh'
    [[ \$(_blacksmith_github_column_option_id 'needs_input') == 'opt-needs-input' ]] || { echo FAIL: alias lookup; exit 1; }
    [[ \$(_blacksmith_github_column_option_id 'Needs Developer Input') == 'opt-needs-input' ]] || { echo FAIL: alias literal lookup; exit 1; }
  "

echo "test_blacksmith_columns: PASS"
