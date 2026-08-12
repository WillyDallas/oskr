#!/usr/bin/env bash
# Drop-in `curl` replacement for tests of the Forgejo backend. Routes by URL
# content to a canned JSON fixture and logs each call to $CURL_SHIM_CALL_LOG.
# Auth header and flags (-fsS etc.) are accepted and ignored; the shim only
# inspects the URL. Mirrors lib/gh-shim.sh for the gitea-family REST transport.
#
# Fixture routing (first match wins):
#   .../dependencies   + $CURL_SHIM_DEPS_FIXTURE   -> that fixture
#   .../repos/{o}/{r}  + $CURL_SHIM_REPO_FIXTURE   -> that fixture (repo object; deps-unit read)
: "${CURL_SHIM_CALL_LOG:?CURL_SHIM_CALL_LOG not set}"
printf 'curl %s\n' "$*" >> "$CURL_SHIM_CALL_LOG"

args="$*"

# Status-discriminating writes (_blacksmith_forgejo_write) pass -w '%{http_code}';
# real curl (no -f) prints the body, then the status as the last line, rc 0. Emit
# the same shape here so tests can simulate HTTP failures per route (most-specific
# first, matching the fixture routing below) or globally via CURL_SHIM_STATUS.
if [[ "$args" == *"%{http_code}"* ]]; then
  code="${CURL_SHIM_STATUS:-200}"
  if   [[ "$args" == */issues/*/labels*   && -n "${CURL_SHIM_ISSUE_LABELS_STATUS:-}" ]]; then code="$CURL_SHIM_ISSUE_LABELS_STATUS"
  elif [[ "$args" == */issues/*/comments* && -n "${CURL_SHIM_COMMENTS_STATUS:-}"     ]]; then code="$CURL_SHIM_COMMENTS_STATUS"
  elif [[ "$args" == */repos/*/labels*    && -n "${CURL_SHIM_REPO_LABELS_STATUS:-}"  ]]; then code="$CURL_SHIM_REPO_LABELS_STATUS"
  elif [[ "$args" == */issues/[0-9]*      && -n "${CURL_SHIM_ISSUE_PATCH_STATUS:-}"  ]]; then code="$CURL_SHIM_ISSUE_PATCH_STATUS"
  fi
  printf '{"message":"curl-shim simulated response"}\n%s' "$code"
  exit 0
fi

# Routes, most-specific first (Forgejo REST endpoints under /api/v1).
if [[ "$args" == *"/dependencies"* ]]; then
  [[ -n "${CURL_SHIM_DEPS_FIXTURE:-}" ]] && { cat "$CURL_SHIM_DEPS_FIXTURE"; exit 0; }
  echo '[]'; exit 0
fi
if [[ "$args" == *"/milestones"* ]]; then               # GET milestones (set_milestone title->id)
  [[ -n "${CURL_SHIM_MILESTONES_FIXTURE:-}" ]] && { cat "$CURL_SHIM_MILESTONES_FIXTURE"; exit 0; }
  echo '[]'; exit 0
fi
if [[ "$args" == *"/pulls"* ]]; then                    # PR create / list (pr_* verbs)
  [[ -n "${CURL_SHIM_PULLS_FIXTURE:-}" ]] && { cat "$CURL_SHIM_PULLS_FIXTURE"; exit 0; }
  echo '[]'; exit 0
fi
if [[ "$args" == */issues/*/labels* ]]; then            # add issue labels (move / create / add_label)
  [[ -n "${CURL_SHIM_ISSUE_LABELS_FIXTURE:-}" ]] && { cat "$CURL_SHIM_ISSUE_LABELS_FIXTURE"; exit 0; }
  echo '[{"name":"status/backlog"}]'; exit 0
fi
if [[ "$args" == */issues/*/comments* ]]; then          # comments: GET (issue_view) / POST (comment)
  [[ -n "${CURL_SHIM_COMMENTS_FIXTURE:-}" ]] && { cat "$CURL_SHIM_COMMENTS_FIXTURE"; exit 0; }
  echo '{"id":1}'; exit 0
fi
if [[ "$args" == */repos/*/labels* ]]; then             # repo labels: GET list (board_schema_ok) / POST create (ensure_label)
  [[ -n "${CURL_SHIM_REPO_LABELS_FIXTURE:-}" ]] && { cat "$CURL_SHIM_REPO_LABELS_FIXTURE"; exit 0; }
  echo '{"id":1}'; exit 0
fi
if [[ "$args" == *"/issues?"* ]]; then                  # GET issues list (list_board / count_actionable)
  [[ -n "${CURL_SHIM_LIST_FIXTURE:-}" ]] && { cat "$CURL_SHIM_LIST_FIXTURE"; exit 0; }
  echo '[]'; exit 0
fi
if [[ "$args" == */issues/[0-9]* ]]; then               # GET single issue (issue_status / find_item)
  [[ -n "${CURL_SHIM_ISSUE_FIXTURE:-}" ]] && { cat "$CURL_SHIM_ISSUE_FIXTURE"; exit 0; }
  echo '{}'; exit 0
fi
if [[ "$args" == *"/issues"* ]]; then                   # POST create issue
  [[ -n "${CURL_SHIM_CREATE_FIXTURE:-}" ]] && { cat "$CURL_SHIM_CREATE_FIXTURE"; exit 0; }
  echo '{}'; exit 0
fi
if [[ "$args" == *"/orgs/"*"/repos"* || "$args" == *"/user/repos"* ]]; then  # repo_create
  [[ -n "${CURL_SHIM_REPO_CREATE_FIXTURE:-}" ]] && { cat "$CURL_SHIM_REPO_CREATE_FIXTURE"; exit 0; }
  echo '{}'; exit 0
fi
if [[ "$args" == *"/api/v1/user"* ]]; then      # GET authenticated user (repo_create routing)
  [[ -n "${CURL_SHIM_USER_FIXTURE:-}" ]] && { cat "$CURL_SHIM_USER_FIXTURE"; exit 0; }
  echo '{"login":"test-user"}'; exit 0
fi
if [[ -n "${CURL_SHIM_REPO_FIXTURE:-}" && "$args" == */repos/* ]]; then   # GET repo object (deps-unit assertion)
  cat "$CURL_SHIM_REPO_FIXTURE"; exit 0
fi
if [[ "$args" == */repos/*/* ]]; then           # remote_exists probe: GET /repos/{owner}/{repo}; rc 0 = exists
  exit "${CURL_SHIM_REPO_RC:-0}"
fi
echo "curl-shim: no route for: $args" >&2
exit 22
