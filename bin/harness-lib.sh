#!/usr/bin/env bash
# harness-lib.sh — the blacksmith: oskr's forge-adapter library.
# Sourceable; not directly executable.
#
# The "blacksmith" is the forge-agnostic board/issue operation layer. Public verbs
# (blacksmith_*) dispatch on the project's configured `forge` (github|forgejo; default
# github) to a per-forge implementation (_blacksmith_github_* / _blacksmith_forgejo_*).
# Callers in bin/ MUST go through the public blacksmith_* verbs; there must be no inline
# `gh`/forge API calls outside this file. See docs/design/platform-reframe.md,
# docs/design/pipeline-redesign.md, and docs/research/2026-06-27-backend-capability.md.
#
# Layers:
#   blacksmith_config_*        forge-agnostic config getters (NOT dispatched)
#   _blacksmith_forge          read the configured forge slug (default github)
#   _blacksmith_dispatch       <op> -> _blacksmith_<forge>_<op>
#   blacksmith_<verb>          public op = one-line dispatcher
#   _blacksmith_<forge>_<verb> the per-forge implementation
#
# Each function uses `command jq` is unnecessary; jq is called directly. All functions
# either echo on stdout and return 0, or die with a message on stderr and return non-zero.

_blacksmith_die() {
  echo "[blacksmith] $1" >&2
  return 1
}

# --- forge-agnostic config getters -----------------------------------------

blacksmith_config_path() {
  if [[ -n "${HARNESS_CONFIG:-}" ]]; then
    [[ -f "$HARNESS_CONFIG" ]] || { _blacksmith_die "HARNESS_CONFIG set but file missing: $HARNESS_CONFIG"; return 1; }
    echo "$HARNESS_CONFIG"
    return 0
  fi
  if [[ -f "$PWD/harness-config.json" ]]; then
    echo "$PWD/harness-config.json"; return 0
  fi
  if [[ -f "$PWD/.claude/harness-config.json" ]]; then
    echo "$PWD/.claude/harness-config.json"; return 0
  fi
  _blacksmith_die "not in an oskr project; expected harness-config.json at \$PWD or \$PWD/.claude/"
  return 1
}

blacksmith_config_get() {
  local path="$1" cfg
  cfg=$(blacksmith_config_path) || return 1
  jq -er "$path" "$cfg"
}

blacksmith_config_get_array() {
  local path="$1" cfg
  cfg=$(blacksmith_config_path) || return 1
  jq -er "${path}[]" "$cfg"
}

# --- forge dispatch ---------------------------------------------------------

# Echo the configured forge slug (default: github). Forge-agnostic config read;
# a missing/unreadable config falls back to github so non-project contexts still work.
_blacksmith_forge() {
  local cfg forge
  cfg=$(blacksmith_config_path 2>/dev/null) || { printf 'github'; return 0; }
  forge=$(jq -er '.forge // "github"' "$cfg" 2>/dev/null) || forge=github
  printf '%s' "$forge"
}

# _blacksmith_dispatch <op> [args...] -> calls _blacksmith_<forge>_<op> [args...]
_blacksmith_dispatch() {
  local op="$1"; shift
  local forge fn
  forge=$(_blacksmith_forge)
  fn="_blacksmith_${forge}_${op}"
  if ! declare -F "$fn" >/dev/null 2>&1; then
    _blacksmith_die "forge '$forge' has no implementation for '$op' (missing $fn)"
    return 1
  fi
  "$fn" "$@"
}

# --- public forge ops (each verb is a one-line dispatcher) ------------------

blacksmith_move_issue()        { _blacksmith_dispatch move_issue "$@"; }
blacksmith_find_item()         { _blacksmith_dispatch find_item "$@"; }
blacksmith_item_issue_number() { _blacksmith_dispatch item_issue_number "$@"; }
blacksmith_item_status()       { _blacksmith_dispatch item_status "$@"; }
blacksmith_issue_status()      { _blacksmith_dispatch issue_status "$@"; }
blacksmith_list_board()        { _blacksmith_dispatch list_board "$@"; }
blacksmith_count_actionable()  { _blacksmith_dispatch count_actionable "$@"; }
blacksmith_archive_item()      { _blacksmith_dispatch archive_item "$@"; }
blacksmith_pr_open_count()     { _blacksmith_dispatch pr_open_count "$@"; }
blacksmith_ensure_label()      { _blacksmith_dispatch ensure_label "$@"; }
blacksmith_issue_add_label()   { _blacksmith_dispatch issue_add_label "$@"; }
blacksmith_issue_comment()     { _blacksmith_dispatch issue_comment "$@"; }

# --- column-vocabulary helpers (forge-agnostic) ----------------------------

_blacksmith_normalize_slug() {
  local s="$1"
  s=$(printf '%s' "$s" | tr '[:upper:]' '[:lower:]' | tr ' ' '_')
  printf '%s' "$s"
}

# Canonical slug → default display name
_blacksmith_default_name_for_slug() {
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

# Echoes the display name to look up in a backend's column representation.
# Honors workflow.column_names[<slug>] aliasing.
_blacksmith_display_name_for() {
  local input="$1" slug cfg alias
  slug=$(_blacksmith_normalize_slug "$input")
  cfg=$(blacksmith_config_path) || return 1
  alias=$(jq -r --arg s "$slug" '.workflow.column_names[$s] // ""' "$cfg")
  if [[ -n "$alias" ]]; then
    printf '%s' "$alias"
    return 0
  fi
  if _blacksmith_default_name_for_slug "$slug" >/dev/null 2>&1; then
    _blacksmith_default_name_for_slug "$slug"
    return 0
  fi
  # input was neither a recognized slug nor a defined alias key — pass through
  # in case it's a literal display name typed by the caller (e.g. "Needs Developer Input").
  printf '%s' "$input"
}

# ===========================================================================
# GITHUB BACKEND (_blacksmith_github_*)
# ---------------------------------------------------------------------------
# The complete GitHub Projects v2 implementation of the blacksmith op set:
# project/field discovery, column resolution, issue<->item lookups, move,
# archive, board listing, and issue/label ops. A second backend (Forgejo, via
# labels-as-columns) reimplements this same operation set as _blacksmith_forgejo_*.
# ---------------------------------------------------------------------------
# Project / field discovery
#
# This layer always hits gh; the cache layer below (_blacksmith_github_get_discovery)
# wraps it, reading from / writing to disk. _blacksmith_github_discover_raw() is the
# uncached entry point.

_blacksmith_github_discover_raw() {
  local owner number repo
  owner=$(blacksmith_config_get '.github.owner') || return 1
  repo=$(blacksmith_config_get '.github.repo')   || return 1
  number=$(blacksmith_config_get '.github.project_number') || return 1

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
    || { _blacksmith_die "GraphQL discovery failed; try: gh auth status"; return 1; }
}

_blacksmith_github_project_id() {
  _blacksmith_github_get_discovery | jq -er '.data.repository.projectV2.id'
}

_blacksmith_github_status_field_id() {
  _blacksmith_github_field_id "Status"
}

_blacksmith_github_field_id() {
  local field_name="$1"
  _blacksmith_github_get_discovery \
    | jq -er --arg n "$field_name" '
        .data.repository.projectV2.fields.nodes[]
        | select(.name == $n) | .id
      '
}

# --- Discovery cache -------------------------------------------------------

_blacksmith_github_cache_dir() {
  echo "${XDG_CACHE_HOME:-$HOME/.cache}/oskr"
}

_blacksmith_github_cache_file() {
  local owner repo number dir
  owner=$(blacksmith_config_get '.github.owner') || return 1
  repo=$(blacksmith_config_get '.github.repo')   || return 1
  number=$(blacksmith_config_get '.github.project_number') || return 1
  dir=$(_blacksmith_github_cache_dir)
  echo "$dir/${number}-${owner}-${repo}.json"
}

_blacksmith_github_get_discovery() {
  local f
  f=$(_blacksmith_github_cache_file) || return 1
  if [[ -f "$f" ]]; then
    cat "$f"
    return 0
  fi
  mkdir -p "$(dirname "$f")"
  local raw
  raw=$(_blacksmith_github_discover_raw) || return 1
  printf '%s' "$raw" > "$f"
  printf '%s' "$raw"
}

_blacksmith_github_cache_clear() {
  local f
  f=$(_blacksmith_github_cache_file) || return 1
  rm -f "$f"
}

# --- Column resolution -----------------------------------------------------

_blacksmith_github_status_options_json() {
  _blacksmith_github_get_discovery \
    | jq -c '
        .data.repository.projectV2.fields.nodes[]
        | select(.name == "Status") | .options
      '
}

_blacksmith_github_column_option_id() {
  local input="$1" display options uuid
  display=$(_blacksmith_display_name_for "$input") || return 1
  options=$(_blacksmith_github_status_options_json) || return 1
  uuid=$(printf '%s' "$options" | jq -r --arg n "$display" '.[] | select(.name == $n) | .id')

  if [[ -z "$uuid" ]]; then
    # lazy re-discover once
    _blacksmith_github_cache_clear
    options=$(_blacksmith_github_status_options_json) || return 1
    uuid=$(printf '%s' "$options" | jq -r --arg n "$display" '.[] | select(.name == $n) | .id')
  fi

  if [[ -z "$uuid" ]]; then
    local valid
    valid=$(printf '%s' "$options" | jq -r '[.[] | .name] | join(", ")')
    _blacksmith_die "unknown column '$input' (looked up as '$display'); valid: $valid"
    return 1
  fi
  printf '%s' "$uuid"
}

_blacksmith_github_column_name_for() {
  local uuid="$1" options
  options=$(_blacksmith_github_status_options_json) || return 1
  printf '%s' "$options" | jq -er --arg id "$uuid" '.[] | select(.id == $id) | .name'
}

# --- Compound operations ---------------------------------------------------

_blacksmith_github_move_issue() {
  local item_id="$1" column="$2"
  local project_id field_id option_id
  project_id=$(_blacksmith_github_project_id) || return 1
  field_id=$(_blacksmith_github_status_field_id) || return 1
  option_id=$(_blacksmith_github_column_option_id "$column") || return 1

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
_blacksmith_github_find_item() {
  local issue_number="$1" owner repo number
  owner=$(blacksmith_config_get '.github.owner')          || return 1
  repo=$(blacksmith_config_get '.github.repo')            || return 1
  number=$(blacksmith_config_get '.github.project_number') || return 1
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
_blacksmith_github_item_issue_number() {
  local item_id="$1"
  # shellcheck disable=SC2016
  gh api graphql -f query='query($id: ID!) { node(id: $id) { ... on ProjectV2Item { content { ... on Issue { number } } } } }' \
    -F id="$item_id" --jq '.data.node.content.number'
}

# Echo the Status column name for a project item id (PVTI_…).
_blacksmith_github_item_status() {
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
_blacksmith_github_issue_status() {
  local issue_number="$1" owner repo number
  owner=$(blacksmith_config_get '.github.owner')          || return 1
  repo=$(blacksmith_config_get '.github.repo')            || return 1
  number=$(blacksmith_config_get '.github.project_number') || return 1
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
# Forgejo backend can return the same is slice 5 of #26 (see PRD); for now the
# Forgejo backend must synthesize this exact shape.
_blacksmith_github_list_board() {
  local owner repo number after page board_total has_next nodes_file assembled rc
  owner=$(blacksmith_config_get '.github.owner')          || return 1
  repo=$(blacksmith_config_get '.github.repo')            || return 1
  number=$(blacksmith_config_get '.github.project_number') || return 1
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
      _blacksmith_die "board query failed (page after=$after)"
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
_blacksmith_github_count_actionable() {
  local owner repo number actionable_json inprogress_name
  owner=$(blacksmith_config_get '.github.owner')          || return 1
  repo=$(blacksmith_config_get '.github.repo')            || return 1
  number=$(blacksmith_config_get '.github.project_number') || return 1
  actionable_json=$(
    while IFS= read -r slug; do
      _blacksmith_display_name_for "$slug"
    done < <(blacksmith_config_get_array '.workflow.actionable_columns') \
      | jq -R . | jq -sc .
  )
  inprogress_name=$(_blacksmith_display_name_for in_progress)
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
_blacksmith_github_archive_item() {
  local item_id="$1" project_id
  project_id=$(_blacksmith_github_project_id) || return 1
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
_blacksmith_github_pr_open_count() {
  local branch="$1" owner repo
  owner=$(blacksmith_config_get '.github.owner') || return 1
  repo=$(blacksmith_config_get '.github.repo')   || return 1
  gh pr list --repo "$owner/$repo" --head "$branch" --state open --json number --jq 'length' 2>/dev/null || echo "0"
}

# Ensure a label exists (idempotent; never fails the caller).
_blacksmith_github_ensure_label() {
  local name="$1" description="$2" color="$3" owner repo
  owner=$(blacksmith_config_get '.github.owner') || return 1
  repo=$(blacksmith_config_get '.github.repo')   || return 1
  gh label create "$name" --repo "$owner/$repo" --description "$description" --color "$color" 2>/dev/null || true
}

# Add a label to an issue (never fails the caller).
_blacksmith_github_issue_add_label() {
  local issue="$1" label="$2" owner repo
  owner=$(blacksmith_config_get '.github.owner') || return 1
  repo=$(blacksmith_config_get '.github.repo')   || return 1
  gh issue edit "$issue" --repo "$owner/$repo" --add-label "$label" >/dev/null 2>&1 || true
}

# Post a comment on an issue (never fails the caller).
_blacksmith_github_issue_comment() {
  local issue="$1" body="$2" owner repo
  owner=$(blacksmith_config_get '.github.owner') || return 1
  repo=$(blacksmith_config_get '.github.repo')   || return 1
  gh issue comment "$issue" --repo "$owner/$repo" --body "$body" >/dev/null 2>&1 || true
}
