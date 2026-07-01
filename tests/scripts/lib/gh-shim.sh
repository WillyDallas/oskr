#!/usr/bin/env bash
# Drop-in `gh` replacement for tests. Routes by argument content to a canned
# JSON fixture, optionally applies a `--jq`/`-q` filter the way real `gh` does,
# and logs each call (newlines flattened) to $GH_SHIM_CALL_LOG.
#
# Fixture routing (first match wins):
#   updateProjectV2ItemFieldValue              -> mutation success blob
#   projectItems + $GH_SHIM_FIND_ITEM_FIXTURE  -> that fixture
#   pageInfo     + $GH_SHIM_BOARD_FIXTURE      -> that fixture
#   (default)                                  -> $GH_SHIM_FIXTURE (discovery)
#
# If `--jq <expr>` (or `-q <expr>`) is present, the chosen JSON is piped through
# `jq -r <expr>`, mirroring real gh — so functions that rely on gh's own --jq
# (e.g. blacksmith_find_item) are testable. Functions that pipe to a separate `jq`
# (e.g. discovery) are unaffected since they pass no --jq.
: "${GH_SHIM_FIXTURE:?GH_SHIM_FIXTURE not set}"
: "${GH_SHIM_CALL_LOG:?GH_SHIM_CALL_LOG not set}"
printf 'gh %s\n' "${*//$'\n'/ }" >> "$GH_SHIM_CALL_LOG"

args="$*"

# Extract a --jq / -q filter expression, if any (the arg following the flag).
jq_expr=""
prev=""
for a in "$@"; do
  if [[ "$prev" == "--jq" || "$prev" == "-q" ]]; then
    jq_expr="$a"
    break
  fi
  prev="$a"
done

emit() {
  if [[ -n "$jq_expr" ]]; then
    jq -r "$jq_expr"
  else
    cat
  fi
}

if [[ "$args" == *updateProjectV2ItemFieldValue* ]]; then
  printf '%s' '{"data":{"updateProjectV2ItemFieldValue":{"projectV2Item":{"id":"PVTI_test"}}}}' | emit
  exit 0
fi
if [[ "$args" == *addProjectV2ItemById* ]]; then
  printf '%s' '{"data":{"addProjectV2ItemById":{"item":{"id":"PVTI_created"}}}}' | emit
  exit 0
fi
if [[ "$args" == */milestones* && "$args" == *"title="* ]]; then   # POST create milestone (opt-in)
  emit < "${GH_SHIM_CREATE_MILESTONE_FIXTURE:-/dev/null}"; exit 0
fi
if [[ "$args" == *"title="* && -n "${GH_SHIM_CREATE_ISSUE_FIXTURE:-}" ]]; then
  emit < "$GH_SHIM_CREATE_ISSUE_FIXTURE"; exit 0
fi
if [[ "$args" == *sub_issue_id=* ]]; then
  printf '%s' '{"id":1,"number":1}' | emit; exit 0
fi
if [[ "$args" == *sub_issues* && -n "${GH_SHIM_SUBISSUES_FIXTURE:-}" ]]; then
  emit < "$GH_SHIM_SUBISSUES_FIXTURE"; exit 0
fi
if [[ "$args" == *projectItems* && -n "${GH_SHIM_FIND_ITEM_FIXTURE:-}" ]]; then
  emit < "$GH_SHIM_FIND_ITEM_FIXTURE"; exit 0
fi
if [[ "$args" == *pageInfo* && -n "${GH_SHIM_BOARD_FIXTURE:-}" ]]; then
  emit < "$GH_SHIM_BOARD_FIXTURE"; exit 0
fi
if [[ "$args" == */milestones* ]]; then                # GET milestones (set_milestone title->number)
  emit < "${GH_SHIM_MILESTONES_FIXTURE:-/dev/null}"; exit 0
fi
if [[ "$args" == *"/issues?"* && -n "${GH_SHIM_ISSUES_FIXTURE:-}" ]]; then  # GET issues list (count_issues)
  emit < "$GH_SHIM_ISSUES_FIXTURE"; exit 0
fi
if [[ "$args" == *dependencies/blocked_by* && "$args" == *issue_id=* ]]; then  # POST blocked-by edge (add_dep); GET read_deps has no issue_id= and falls through
  printf '%s' '{}' | emit; exit 0
fi
if [[ "$args" == *"repo view"* ]]; then         # remote_exists probe: rc 0 = exists, non-zero = absent
  exit "${GH_SHIM_REPO_VIEW_RC:-0}"
fi
emit < "$GH_SHIM_FIXTURE"
