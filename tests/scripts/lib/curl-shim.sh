#!/usr/bin/env bash
# Drop-in `curl` replacement for tests of the Forgejo backend. Routes by URL
# content to a canned JSON fixture and logs each call to $CURL_SHIM_CALL_LOG.
# Auth header and flags (-fsS etc.) are accepted and ignored; the shim only
# inspects the URL. Mirrors lib/gh-shim.sh for the gitea-family REST transport.
#
# Fixture routing (first match wins):
#   .../dependencies   + $CURL_SHIM_DEPS_FIXTURE   -> that fixture
: "${CURL_SHIM_CALL_LOG:?CURL_SHIM_CALL_LOG not set}"
printf 'curl %s\n' "$*" >> "$CURL_SHIM_CALL_LOG"

args="$*"
# Routes, most-specific first (Forgejo REST endpoints under /api/v1).
if [[ "$args" == *"/dependencies"* ]]; then
  [[ -n "${CURL_SHIM_DEPS_FIXTURE:-}" ]] && { cat "$CURL_SHIM_DEPS_FIXTURE"; exit 0; }
  echo '[]'; exit 0
fi
if [[ "$args" == *"/milestones"* ]]; then               # GET milestones (set_milestone title->id)
  [[ -n "${CURL_SHIM_MILESTONES_FIXTURE:-}" ]] && { cat "$CURL_SHIM_MILESTONES_FIXTURE"; exit 0; }
  echo '[]'; exit 0
fi
if [[ "$args" == */issues/*/labels* ]]; then            # add issue labels (move / create / add_label)
  [[ -n "${CURL_SHIM_ISSUE_LABELS_FIXTURE:-}" ]] && { cat "$CURL_SHIM_ISSUE_LABELS_FIXTURE"; exit 0; }
  echo '[{"name":"status/backlog"}]'; exit 0
fi
if [[ "$args" == */issues/*/comments* ]]; then          # post comment
  echo '{"id":1}'; exit 0
fi
if [[ "$args" == */repos/*/labels* ]]; then             # repo label create (ensure_label)
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
echo "curl-shim: no route for: $args" >&2
exit 22
