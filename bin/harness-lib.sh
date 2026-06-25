#!/usr/bin/env bash
# harness-lib.sh — shared helpers for the oskr dispatcher scripts.
# Sourceable; not directly executable.
#
# Public functions (this section):
#   harness_config_path                  — absolute path to harness-config.json
#   harness_config_get <jq_path>         — scalar getter
#   harness_config_get_array <jq_path>   — array getter (one element per line)

# Each function uses `command jq` to avoid recursion into the test gh-shim.
# All functions either echo on stdout and return 0, or die with a message
# on stderr and return non-zero.

_harness_die() {
  echo "[harness] $1" >&2
  return 1
}

harness_config_path() {
  if [[ -n "${HARNESS_CONFIG:-}" ]]; then
    [[ -f "$HARNESS_CONFIG" ]] || { _harness_die "HARNESS_CONFIG set but file missing: $HARNESS_CONFIG"; return 1; }
    echo "$HARNESS_CONFIG"
    return 0
  fi
  if [[ -f "$PWD/harness-config.json" ]]; then
    echo "$PWD/harness-config.json"; return 0
  fi
  if [[ -f "$PWD/.claude/harness-config.json" ]]; then
    echo "$PWD/.claude/harness-config.json"; return 0
  fi
  _harness_die "not in an oskr project; expected harness-config.json at \$PWD or \$PWD/.claude/"
  return 1
}

harness_config_get() {
  local path="$1" cfg
  cfg=$(harness_config_path) || return 1
  jq -er "$path" "$cfg"
}

harness_config_get_array() {
  local path="$1" cfg
  cfg=$(harness_config_path) || return 1
  jq -er "${path}[]" "$cfg"
}

# ===========================================================================
# BACKEND: GitHub Projects v2
# ---------------------------------------------------------------------------
# Everything from here to the end of the file is the GitHub Projects v2
# backend: the complete set of board operations (project/field discovery,
# column resolution, issue<->item lookups, move, archive, board listing, and
# issue/label ops). This is THE SEAM — a second backend (Forgejo, via
# labels-as-columns) reimplements this same operation set. Callers in bin/
# MUST go through these functions; there must be no inline `gh api graphql`
# outside this file. See docs/design/platform-reframe.md and
# docs/research/2026-06-22-forgejo-backend-capability.md.
#
# Backend SELECTION — dispatching on harness-config.json `.backend` — lands
# with the Forgejo implementation; today there is only one backend.
# ---------------------------------------------------------------------------
# Project / field discovery
#
# This layer always hits gh; the cache layer below (_harness_get_discovery)
# wraps it, reading from / writing to disk. _harness_discover_raw() is the
# uncached entry point.

_harness_discover_raw() {
  local owner number repo
  owner=$(harness_config_get '.github.owner') || return 1
  repo=$(harness_config_get '.github.repo')   || return 1
  number=$(harness_config_get '.github.project_number') || return 1

  # shellcheck disable=SC2016
  gh api graphql -f query='
    query($owner: String!, $repo: String!, $number: Int!) {
      repository(owner: $owner, name: $repo) {
        projectV2(number: $number) {
          id
          fields(first: 50) {
            nodes {
              ... on ProjectV2SingleSelectField {
                id name
                options { id name }
              }
              ... on ProjectV2Field { id name }
            }
          }
        }
      }
    }
  ' -F owner="$owner" -F repo="$repo" -F number="$number" 2>/dev/null \
    || { _harness_die "GraphQL discovery failed; try: gh auth status"; return 1; }
}

harness_project_id() {
  _harness_get_discovery | jq -er '.data.repository.projectV2.id'
}

harness_status_field_id() {
  harness_field_id "Status"
}

harness_field_id() {
  local field_name="$1"
  _harness_get_discovery \
    | jq -er --arg n "$field_name" '
        .data.repository.projectV2.fields.nodes[]
        | select(.name == $n) | .id
      '
}

# --- Discovery cache -------------------------------------------------------

_harness_cache_dir() {
  echo "${XDG_CACHE_HOME:-$HOME/.cache}/oskr"
}

_harness_cache_file() {
  local owner repo number dir
  owner=$(harness_config_get '.github.owner') || return 1
  repo=$(harness_config_get '.github.repo')   || return 1
  number=$(harness_config_get '.github.project_number') || return 1
  dir=$(_harness_cache_dir)
  echo "$dir/${number}-${owner}-${repo}.json"
}

_harness_get_discovery() {
  local f
  f=$(_harness_cache_file) || return 1
  if [[ -f "$f" ]]; then
    cat "$f"
    return 0
  fi
  mkdir -p "$(dirname "$f")"
  local raw
  raw=$(_harness_discover_raw) || return 1
  printf '%s' "$raw" > "$f"
  printf '%s' "$raw"
}

harness_cache_clear() {
  local f
  f=$(_harness_cache_file) || return 1
  rm -f "$f"
}

# --- Column resolution -----------------------------------------------------

_harness_normalize_slug() {
  local s="$1"
  s=$(printf '%s' "$s" | tr '[:upper:]' '[:lower:]' | tr ' ' '_')
  printf '%s' "$s"
}

# Canonical slug → default display name
_harness_default_name_for_slug() {
  case "$1" in
    backlog)     echo "Backlog" ;;
    research)    echo "Research" ;;
    needs_input) echo "Needs Input" ;;
    planning)    echo "Planning" ;;
    approval)    echo "Approval" ;;
    ready)       echo "Ready" ;;
    in_progress) echo "In Progress" ;;
    in_review)   echo "In Review" ;;
    done)        echo "Done" ;;
    *)           return 1 ;;
  esac
}

# Echoes the display name to look up in the GraphQL Status options.
# Honors workflow.column_names[<slug>] aliasing.
_harness_display_name_for() {
  local input="$1" slug cfg alias
  slug=$(_harness_normalize_slug "$input")
  cfg=$(harness_config_path) || return 1
  alias=$(jq -r --arg s "$slug" '.workflow.column_names[$s] // ""' "$cfg")
  if [[ -n "$alias" ]]; then
    printf '%s' "$alias"
    return 0
  fi
  if _harness_default_name_for_slug "$slug" >/dev/null 2>&1; then
    _harness_default_name_for_slug "$slug"
    return 0
  fi
  # input was neither a recognized slug nor a defined alias key — pass through
  # in case it's a literal display name typed by the caller (e.g. "Needs Developer Input").
  printf '%s' "$input"
}

_harness_status_options_json() {
  _harness_get_discovery \
    | jq -c '
        .data.repository.projectV2.fields.nodes[]
        | select(.name == "Status") | .options
      '
}

harness_column_option_id() {
  local input="$1" display options uuid
  display=$(_harness_display_name_for "$input") || return 1
  options=$(_harness_status_options_json) || return 1
  uuid=$(printf '%s' "$options" | jq -r --arg n "$display" '.[] | select(.name == $n) | .id')

  if [[ -z "$uuid" ]]; then
    # lazy re-discover once
    harness_cache_clear
    options=$(_harness_status_options_json) || return 1
    uuid=$(printf '%s' "$options" | jq -r --arg n "$display" '.[] | select(.name == $n) | .id')
  fi

  if [[ -z "$uuid" ]]; then
    local valid
    valid=$(printf '%s' "$options" | jq -r '[.[] | .name] | join(", ")')
    _harness_die "unknown column '$input' (looked up as '$display'); valid: $valid"
    return 1
  fi
  printf '%s' "$uuid"
}

harness_column_name_for() {
  local uuid="$1" options
  options=$(_harness_status_options_json) || return 1
  printf '%s' "$options" | jq -er --arg id "$uuid" '.[] | select(.id == $id) | .name'
}

# --- Compound operations ---------------------------------------------------

harness_move_issue() {
  local item_id="$1" column="$2"
  local project_id field_id option_id
  project_id=$(harness_project_id) || return 1
  field_id=$(harness_status_field_id) || return 1
  option_id=$(harness_column_option_id "$column") || return 1

  # shellcheck disable=SC2016
  gh api graphql -f query='
    mutation($project: ID!, $item: ID!, $field: ID!, $value: String!) {
      updateProjectV2ItemFieldValue(input: {
        projectId: $project
        itemId: $item
        fieldId: $field
        value: { singleSelectOptionId: $value }
      }) {
        projectV2Item { id }
      }
    }
  ' -f project="$project_id" -f item="$item_id" -f field="$field_id" -f value="$option_id"
}

# --- Issue <-> item lookups ------------------------------------------------

# Echo the project item id (PVTI_…) for an issue number, or empty if the issue
# is not on the configured project board. Caller decides how to treat empty.
harness_find_item() {
  local issue_number="$1" owner repo number
  owner=$(harness_config_get '.github.owner')          || return 1
  repo=$(harness_config_get '.github.repo')            || return 1
  number=$(harness_config_get '.github.project_number') || return 1
  # shellcheck disable=SC2016
  gh api graphql -f query='
    query($owner: String!, $repo: String!, $number: Int!) {
      repository(owner: $owner, name: $repo) {
        issue(number: $number) {
          projectItems(first: 10) {
            nodes {
              id
              project { number }
            }
          }
        }
      }
    }
  ' -F owner="$owner" -F repo="$repo" -F number="$issue_number" \
    --jq ".data.repository.issue.projectItems.nodes[] | select(.project.number == $number) | .id"
}

# Echo the issue number backing a project item id (PVTI_…), or empty.
harness_item_issue_number() {
  local item_id="$1"
  # shellcheck disable=SC2016
  gh api graphql -f query='query($id: ID!) { node(id: $id) { ... on ProjectV2Item { content { ... on Issue { number } } } } }' \
    -F id="$item_id" --jq '.data.node.content.number'
}

# Echo the Status column name for a project item id (PVTI_…).
harness_item_status() {
  local item_id="$1"
  # shellcheck disable=SC2016
  gh api graphql -f query='
    query($id: ID!) {
      node(id: $id) {
        ... on ProjectV2Item {
          status: fieldValueByName(name: "Status") {
            ... on ProjectV2ItemFieldSingleSelectValue { name }
          }
        }
      }
    }
  ' -F id="$item_id" --jq '.data.node.status.name'
}

# Echo the Status column name for an issue number (looks it up on the board),
# or empty if the issue is not on the board.
harness_issue_status() {
  local issue_number="$1" owner repo number
  owner=$(harness_config_get '.github.owner')          || return 1
  repo=$(harness_config_get '.github.repo')            || return 1
  number=$(harness_config_get '.github.project_number') || return 1
  # shellcheck disable=SC2016
  gh api graphql -f query='
    query($owner: String!, $repo: String!, $number: Int!) {
      repository(owner: $owner, name: $repo) {
        projectV2(number: $number) {
          items(first: 100) {
            nodes {
              status: fieldValueByName(name: "Status") {
                ... on ProjectV2ItemFieldSingleSelectValue { name }
              }
              content { ... on Issue { number } }
            }
          }
        }
      }
    }
  ' -F owner="$owner" -F repo="$repo" -F number="$number" 2>/dev/null \
    | jq -r --argjson n "$issue_number" '.data.repository.projectV2.items.nodes[] | select(.content.number == $n) | .status.name' 2>/dev/null | head -n 1
}

# --- Board listing ---------------------------------------------------------

# Echo the full board as a GitHub-native blob, paginating internally:
#   {data:{repository:{projectV2:{items:{totalCount, nodes:[…]}}}}}
# NOTE: the node shape is GitHub-native (status.name / priority.name /
# category.name / content.{…}). Normalizing it to a backend-neutral shape so a
# Forgejo backend can return the same is a follow-up (see platform-reframe.md);
# for now the Forgejo backend must synthesize this exact shape.
harness_list_board() {
  local owner repo number after page board_total has_next nodes_file assembled rc
  owner=$(harness_config_get '.github.owner')          || return 1
  repo=$(harness_config_get '.github.repo')            || return 1
  number=$(harness_config_get '.github.project_number') || return 1
  nodes_file=$(mktemp -t harness-board.XXXXXX) || return 1
  after="null"
  board_total=0
  while :; do
    # shellcheck disable=SC2016
    page=$(gh api graphql -f query='
      query($owner: String!, $repo: String!, $number: Int!, $after: String) {
        repository(owner: $owner, name: $repo) {
          projectV2(number: $number) {
            items(first: 100, after: $after) {
              totalCount
              pageInfo { hasNextPage endCursor }
              nodes {
                id
                status: fieldValueByName(name: "Status") {
                  ... on ProjectV2ItemFieldSingleSelectValue { name }
                }
                priority: fieldValueByName(name: "Priority") {
                  ... on ProjectV2ItemFieldSingleSelectValue { name }
                }
                category: fieldValueByName(name: "Category") {
                  ... on ProjectV2ItemFieldSingleSelectValue { name }
                }
                content {
                  ... on Issue {
                    number
                    title
                    createdAt
                    body
                    assignees(first: 5) { nodes { login } }
                    comments(last: 5) { nodes { body } }
                    labels(first: 10) { nodes { name } }
                    blocking(first: 1) { totalCount }
                    blockedBy(first: 1) { totalCount }
                  }
                }
              }
            }
          }
        }
      }
    ' -F owner="$owner" -F repo="$repo" -F number="$number" -F after="$after" 2>/dev/null) || {
      rm -f "$nodes_file"
      _harness_die "board query failed (page after=$after)"
      return 1
    }
    printf '%s' "$page" | jq -c '.data.repository.projectV2.items.nodes[]' >> "$nodes_file"
    board_total=$(printf '%s' "$page" | jq '.data.repository.projectV2.items.totalCount')
    has_next=$(printf '%s' "$page" | jq -r '.data.repository.projectV2.items.pageInfo.hasNextPage')
    [[ "$has_next" == "true" ]] || break
    after=$(printf '%s' "$page" | jq -r '.data.repository.projectV2.items.pageInfo.endCursor')
  done
  # Assemble, then clean up — but return the assembly's status, not rm's, so a
  # failed final jq is surfaced rather than masked by a successful cleanup.
  assembled=$(jq -s '{data: {repository: {projectV2: {items: {totalCount: '"$board_total"', nodes: .}}}}}' "$nodes_file")
  rc=$?
  rm -f "$nodes_file"
  printf '%s\n' "$assembled"
  return "$rc"
}

# Echo the count of actionable issues on the board: those in the configured
# actionable columns, plus In Progress issues labeled dispatch-incomplete
# (resume path); loop-skip excluded. Mirrors board-dispatcher's candidate filter.
harness_count_actionable() {
  local owner repo number actionable_json inprogress_name
  owner=$(harness_config_get '.github.owner')          || return 1
  repo=$(harness_config_get '.github.repo')            || return 1
  number=$(harness_config_get '.github.project_number') || return 1
  actionable_json=$(
    while IFS= read -r slug; do
      _harness_display_name_for "$slug"
    done < <(harness_config_get_array '.workflow.actionable_columns') \
      | jq -R . | jq -sc .
  )
  inprogress_name=$(_harness_display_name_for in_progress)
  # shellcheck disable=SC2016
  gh api graphql -f query='
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
    | jq --argjson actionable "$actionable_json" --arg inprogress "$inprogress_name" '
        [.data.repository.projectV2.items.nodes[]
          | select(
              (.status.name as $n | $actionable | index($n))
              or (.status.name == $inprogress
                  and (((.content.labels.nodes // []) | map(.name) | index("dispatch-incomplete")) != null))
            )
          | select(((.content.labels.nodes // []) | map(.name) | index("loop-skip")) | not)
        ] | length
      ' 2>/dev/null || echo "0"
}

# --- Item / issue mutations ------------------------------------------------

# Archive a project item (the card leaves the board view; the issue itself —
# state, comments, labels — is untouched). Reversible via unarchive.
harness_archive_item() {
  local item_id="$1" project_id
  project_id=$(harness_project_id) || return 1
  # shellcheck disable=SC2016
  gh api graphql -f query='
    mutation($project: ID!, $item: ID!) {
      archiveProjectV2Item(input: { projectId: $project, itemId: $item }) {
        item { id isArchived }
      }
    }
  ' -f project="$project_id" -f item="$item_id"
}

# Echo the number of OPEN PRs whose head branch is $1 (0 on any error).
harness_pr_open_count() {
  local branch="$1" owner repo
  owner=$(harness_config_get '.github.owner') || return 1
  repo=$(harness_config_get '.github.repo')   || return 1
  gh pr list --repo "$owner/$repo" --head "$branch" --state open --json number --jq 'length' 2>/dev/null || echo "0"
}

# Ensure a label exists (idempotent; never fails the caller).
harness_ensure_label() {
  local name="$1" description="$2" color="$3" owner repo
  owner=$(harness_config_get '.github.owner') || return 1
  repo=$(harness_config_get '.github.repo')   || return 1
  gh label create "$name" --repo "$owner/$repo" --description "$description" --color "$color" 2>/dev/null || true
}

# Add a label to an issue (never fails the caller).
harness_issue_add_label() {
  local issue="$1" label="$2" owner repo
  owner=$(harness_config_get '.github.owner') || return 1
  repo=$(harness_config_get '.github.repo')   || return 1
  gh issue edit "$issue" --repo "$owner/$repo" --add-label "$label" >/dev/null 2>&1 || true
}

# Post a comment on an issue (never fails the caller).
harness_issue_comment() {
  local issue="$1" body="$2" owner repo
  owner=$(harness_config_get '.github.owner') || return 1
  repo=$(harness_config_get '.github.repo')   || return 1
  gh issue comment "$issue" --repo "$owner/$repo" --body "$body" >/dev/null 2>&1 || true
}

