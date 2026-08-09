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

# Simulated failures for the loud-write paths (#118): when the matching _ERR var
# is set, print it to stderr and exit 1 the way real gh does. Unset = success as
# before, so existing tests are unaffected.
if [[ "$args" == "label create"*   && -n "${GH_SHIM_LABEL_CREATE_ERR:-}"  ]]; then printf '%s\n' "$GH_SHIM_LABEL_CREATE_ERR"  >&2; exit 1; fi
if [[ "$args" == "issue edit"*     && -n "${GH_SHIM_ISSUE_EDIT_ERR:-}"    ]]; then printf '%s\n' "$GH_SHIM_ISSUE_EDIT_ERR"    >&2; exit 1; fi
if [[ "$args" == "issue comment"*  && -n "${GH_SHIM_ISSUE_COMMENT_ERR:-}" ]]; then printf '%s\n' "$GH_SHIM_ISSUE_COMMENT_ERR" >&2; exit 1; fi
if [[ "$args" == "api -X DELETE"*  && -n "${GH_SHIM_API_DELETE_ERR:-}"    ]]; then printf '%s\n' "$GH_SHIM_API_DELETE_ERR"    >&2; exit 1; fi

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
if [[ "$args" == *createProjectV2Field* ]]; then       # taxonomy/Phase field create (provision_board)
  printf '%s' '{"data":{"createProjectV2Field":{"projectV2Field":{"id":"F_new","name":"created"}}}}' | emit
  exit 0
fi
if [[ "$args" == *createProjectV2* && -n "${GH_SHIM_CREATE_PROJECT_FIXTURE:-}" ]]; then  # createProjectV2 (provision_board); Field route above matches first
  emit < "$GH_SHIM_CREATE_PROJECT_FIXTURE"; exit 0
fi
if [[ "$args" == *linkProjectV2ToRepository* ]]; then  # project->repo link (provision_board)
  printf '%s' '{"data":{"linkProjectV2ToRepository":{"repository":{"id":"R_linked"}}}}' | emit
  exit 0
fi
if [[ "$args" == *updateProjectV2Field* ]]; then       # Status augment (provision_status_columns)
  printf '%s' '{"data":{"updateProjectV2Field":{"projectV2Field":{"id":"F_status","name":"Status"}}}}' | emit
  exit 0
fi
if [[ "$args" == *"owner { id }"* && -n "${GH_SHIM_REPO_IDS_FIXTURE:-}" ]]; then  # repo+owner node ids (provision_board)
  emit < "$GH_SHIM_REPO_IDS_FIXTURE"; exit 0
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
if [[ "$args" == *"repo create"* ]]; then       # repo_create: prints the new repo URL
  [[ "${GH_SHIM_REPO_CREATE_RC:-0}" -eq 0 ]] && printf '%s\n' "${GH_SHIM_REPO_CREATE_URL:-https://github.com/test/repo}"
  exit "${GH_SHIM_REPO_CREATE_RC:-0}"
fi
if [[ "$args" == *"/pulls"* && -n "${GH_SHIM_PULLS_FIXTURE:-}" ]]; then   # PR create/list (pr_* verbs)
  emit < "$GH_SHIM_PULLS_FIXTURE"; exit 0
fi
if [[ "$args" == *"/comments"* && -n "${GH_SHIM_COMMENTS_FIXTURE:-}" ]]; then  # GET issue comments (issue_view)
  emit < "$GH_SHIM_COMMENTS_FIXTURE"; exit 0
fi
if [[ "$args" == *"/issues/"* && -n "${GH_SHIM_ISSUE_FIXTURE:-}" ]]; then   # GET/PATCH single issue (opt-in)
  emit < "$GH_SHIM_ISSUE_FIXTURE"; exit 0
fi
emit < "$GH_SHIM_FIXTURE"
