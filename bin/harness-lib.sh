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
  local path="$1" cfg out gcfg
  cfg=$(blacksmith_config_path) || return 1
  # Project tier first. A resolving key returns exactly what jq emits today;
  # the global fallback is strictly additive (present-key reads unchanged).
  if out=$(jq -er "$path" "$cfg" 2>/dev/null); then
    printf '%s\n' "$out"
    return 0
  fi
  # Absent from the project config: consult the global tier if one resolves.
  if gcfg=$(blacksmith_global_config_path 2>/dev/null); then
    if out=$(jq -er "$path" "$gcfg" 2>/dev/null); then
      printf '%s\n' "$out"
      return 0
    fi
  fi
  # Neither tier resolved the key: reproduce today's failure (jq error -> stderr).
  jq -er "$path" "$cfg"
}

blacksmith_config_get_array() {
  local path="$1" cfg
  cfg=$(blacksmith_config_path) || return 1
  jq -er "${path}[]" "$cfg"
}

# --- workspace-root resolution ---------------------------------------------

# Echo the workspace root: the nearest ancestor of $PWD containing a .oskr/
# directory. $OSKR_WORKSPACE, if non-empty, overrides the walk (and must itself
# contain .oskr/). Walks the filesystem, not git, so it crosses the gitignored
# project-repo boundary (e.g. projects/oskr inside the workspace). Loud error
# when neither resolves.
blacksmith_workspace_dir() {
  if [[ -n "${OSKR_WORKSPACE:-}" ]]; then
    if [[ -d "$OSKR_WORKSPACE/.oskr" ]]; then
      echo "$OSKR_WORKSPACE"; return 0
    fi
    _blacksmith_die "OSKR_WORKSPACE set but no .oskr/ found at: $OSKR_WORKSPACE"
    return 1
  fi
  local dir="$PWD"
  while :; do
    if [[ -d "$dir/.oskr" ]]; then
      echo "$dir"; return 0
    fi
    [[ "$dir" == "/" ]] && break
    dir=$(dirname "$dir")
  done
  _blacksmith_die "not inside an oskr workspace; no ancestor .oskr/ found and OSKR_WORKSPACE unset"
  return 1
}

# Echo the global config file (<workspace>/.oskr/config.json), or fail quietly
# (return 1, no stderr) when no workspace or no global config exists. Quiet by
# design: it is a fallback probe, not a primary resolver.
blacksmith_global_config_path() {
  local ws gcfg
  ws=$(blacksmith_workspace_dir 2>/dev/null) || return 1
  gcfg="$ws/.oskr/config.json"
  [[ -f "$gcfg" ]] || return 1
  echo "$gcfg"
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

# #26 graph/write primitives (added per slice). Native-first on each forge;
# normalized to a backend-neutral shape so the dispatcher never parses prose.
blacksmith_read_deps()         { _blacksmith_dispatch read_deps "$@"; }
blacksmith_create_issue()      { _blacksmith_dispatch create_issue "$@"; }
blacksmith_link_parent()       { _blacksmith_dispatch link_parent "$@"; }
blacksmith_list_children()     { _blacksmith_dispatch list_children "$@"; }
blacksmith_set_milestone()     { _blacksmith_dispatch set_milestone "$@"; }
blacksmith_add_dep()           { _blacksmith_dispatch add_dep "$@"; }
blacksmith_base_branch()       { _blacksmith_dispatch base_branch "$@"; }
blacksmith_count_issues()      { _blacksmith_dispatch count_issues "$@"; }
blacksmith_provision_board()   { _blacksmith_dispatch provision_board "$@"; }
blacksmith_remote_exists()     { _blacksmith_dispatch remote_exists "$@"; }

# Board provisioning (init / setup; #27 T5). Routes through the seam like every op.
blacksmith_provision_status_columns() { _blacksmith_dispatch provision_status_columns "$@"; }

# Adopt full re-intake (#27 T7): harvest read + Epoch milestone materialization.
blacksmith_list_issues()       { _blacksmith_dispatch list_issues "$@"; }
blacksmith_create_milestone()  { _blacksmith_dispatch create_milestone "$@"; }

# --- column-vocabulary helpers (forge-agnostic) ----------------------------

_blacksmith_normalize_slug() {
  local s="$1"
  s=$(printf '%s' "$s" | tr '[:upper:]' '[:lower:]' | tr ' ' '_')
  printf '%s' "$s"
}

# Canonical slug → default display name (8-column scheme; #27 T5).
_blacksmith_default_name_for_slug() {
  case "$1" in
    backlog)       echo "Backlog" ;;
    scoping)       echo "Scoping" ;;
    planning)      echo "Planning" ;;
    plan_approval) echo "Plan Approval" ;;
    ready)         echo "Ready" ;;
    in_progress)   echo "In Progress" ;;
    in_review)     echo "In Review" ;;
    done)          echo "Done" ;;
    *)             return 1 ;;
  esac
}

# The canonical board columns in board order — the SINGLE source of truth that kills
# the provisioning-vs-runtime column drift (#52). Provisioning maps each slug to its
# display name via _blacksmith_default_name_for_slug.
_blacksmith_board_column_slugs() {
  printf '%s\n' backlog scoping planning plan_approval ready in_progress in_review done
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

# --- Board provisioning (init/setup; #27 T5) -------------------------------

# GitHub single-select option color (enum) for a column slug — presentation only.
_blacksmith_github_color_for_slug() {
  case "$1" in
    backlog)       echo GRAY ;;
    scoping)       echo BLUE ;;
    planning)      echo PURPLE ;;
    plan_approval) echo YELLOW ;;
    ready)         echo GREEN ;;
    in_progress)   echo BLUE ;;
    in_review)     echo PURPLE ;;
    done)          echo GREEN ;;
    *)             echo GRAY ;;
  esac
}

# Build the GraphQL singleSelectOptions array literal for the 8 canonical columns,
# from the single-source-of-truth slug list. name+color+description mirror the shape
# GitHub's ProjectV2SingleSelectFieldOptionInput requires.
_blacksmith_github_status_options_literal() {
  local slug name color out=""
  while IFS= read -r slug; do
    name=$(_blacksmith_default_name_for_slug "$slug") || return 1
    color=$(_blacksmith_github_color_for_slug "$slug")
    out+="{ name: \"$name\", color: $color, description: \"\" },"
  done < <(_blacksmith_board_column_slugs)
  printf '[%s]' "${out%,}"
}

# Provision the project's Status single-select field with the 8 canonical columns.
# Augments the existing Status field IN PLACE (id-preserving, no orphaned assignments);
# on failure, creates a separate "Phase" field with the same options. Echoes the
# resulting status field NAME ("Status" | "Phase") so the caller records
# workflow.status_field_name.  provision_status_columns <project_node_id>
_blacksmith_github_provision_status_columns() {
  local project_id="$1" options field_id resp
  [[ -n "$project_id" ]] || { _blacksmith_die "provision_status_columns: project node id required"; return 1; }
  options=$(_blacksmith_github_status_options_literal) || return 1
  # shellcheck disable=SC2016
  field_id=$(gh api graphql -f query='
    query($projectId: ID!) {
      node(id: $projectId) {
        ... on ProjectV2 {
          fields(first: 50) { nodes { ... on ProjectV2SingleSelectField { id name } } }
        }
      }
    }
  ' -f projectId="$project_id" --jq '.data.node.fields.nodes[] | select(.name == "Status") | .id' 2>/dev/null)
  if [[ -n "$field_id" ]]; then
    resp=$(gh api graphql -f query="
      mutation(\$fieldId: ID!) {
        updateProjectV2Field(input: { fieldId: \$fieldId, singleSelectOptions: $options }) {
          projectV2Field { ... on ProjectV2SingleSelectField { id name } }
        }
      }
    " -f fieldId="$field_id" 2>&1)
    grep -q '"errors"' <<<"$resp" || { printf 'Status'; return 0; }
  fi
  gh api graphql -f query="
    mutation(\$projectId: ID!) {
      createProjectV2Field(input: {
        projectId: \$projectId, dataType: SINGLE_SELECT, name: \"Phase\",
        singleSelectOptions: $options
      }) { projectV2Field { ... on ProjectV2SingleSelectField { id name } } }
    }
  " -f projectId="$project_id" >/dev/null 2>&1 \
    || { _blacksmith_die "provision_status_columns: could not augment Status nor create Phase"; return 1; }
  printf 'Phase'
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

# Echo the full board in the backend-NEUTRAL shape (#26 slice 5), paginating
# internally:
#   { total: <int>, items: [ { number, title, status, priority, category,
#     createdAt, body, assignees:[login], comments:[body], labels:[name],
#     blocking:<int>, blockedBy:<int> } ] }
# status/priority/category are column DISPLAY NAMES (resolved identically by both
# forges via config). The Forgejo backend synthesizes this same shape from labels
# + native dep counts. `total` is the forge's item count (pagination integrity).
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
  assembled=$(jq -s '{total: '"$board_total"', items: [ .[] | {
      number:    .content.number,
      title:     .content.title,
      status:    (.status.name   // null),
      priority:  (.priority.name // null),
      category:  (.category.name // null),
      createdAt: .content.createdAt,
      body:      .content.body,
      assignees: [ (.content.assignees.nodes // [])[] | .login ],
      comments:  [ (.content.comments.nodes  // [])[] | .body  ],
      labels:    [ (.content.labels.nodes    // [])[] | .name  ],
      blocking:  (.content.blocking.totalCount  // 0),
      blockedBy: (.content.blockedBy.totalCount // 0)
    } ] }' "$nodes_file")
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

# Probe whether owner/repo exists on GitHub. Returns 0 if it exists, non-zero
# otherwise. Used by init v2 mode detection (create-new vs clone). No stdout.
#   remote_exists <owner> <repo>
_blacksmith_github_remote_exists() {
  local owner="$1" repo="$2"
  gh repo view "${owner}/${repo}" --json nameWithOwner >/dev/null 2>&1
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

# --- Dependencies (native; #26 slice 2) ------------------------------------

# Echo the blocked-by edges of an issue as a normalized JSON array:
#   [ { number, state, title, repository, url } ]
# Native GitHub issue-dependencies API (GA 2025-08-21) — NOT body-parse.
_blacksmith_github_read_deps() {
  local issue="$1" owner repo raw
  owner=$(blacksmith_config_get '.github.owner') || return 1
  repo=$(blacksmith_config_get '.github.repo')   || return 1
  raw=$(gh api "repos/${owner}/${repo}/issues/${issue}/dependencies/blocked_by?per_page=100" 2>/dev/null) \
    || { _blacksmith_die "read_deps query failed for issue #$issue"; return 1; }
  printf '%s' "$raw" | jq -c '[ .[] | {
      number,
      state,
      title,
      repository: (.repository.full_name // ((.repository_url // "") | sub("^https?://[^/]+/repos/"; ""))),
      url: .html_url
    } ]'
}

# --- Issue harvest (adopt full-migration; #27) ------------------------------

# Echo ALL repo issues (open + closed; pull requests excluded) as the neutral
# array [ { number, title, state, body, labels:[name] } ]. The off-board backlog
# source the adopt harvest reconciles. Native REST list, paginated to 100.
#   list_issues
_blacksmith_github_list_issues() {
  local owner repo raw
  owner=$(blacksmith_config_get '.github.owner') || return 1
  repo=$(blacksmith_config_get '.github.repo')   || return 1
  raw=$(gh api "repos/${owner}/${repo}/issues?state=all&per_page=100" 2>/dev/null) \
    || { _blacksmith_die "list_issues query failed for ${owner}/${repo}"; return 1; }
  printf '%s' "$raw" | jq -c '[ .[]
    | select(has("pull_request") | not)
    | { number, title, state, body: (.body // ""), labels: [ (.labels // [])[] | .name ] } ]'
}

# --- Issue creation (native; #26 slice 3) ----------------------------------

# Create an issue and add it to the configured Project v2 board. Echoes the
# backend-neutral result: { number, url }. (The Project item id is GitHub-only,
# so it is NOT in the neutral output — callers compose move/set by number.)
#   create_issue <title> [body] [labels_csv]
_blacksmith_github_create_issue() {
  local title="$1" body="${2:-}" labels_csv="${3:-}"
  local owner repo raw number node_id url project_id
  local -a label_args=()
  [[ -n "$title" ]] || { _blacksmith_die "create_issue: title required"; return 1; }
  owner=$(blacksmith_config_get '.github.owner') || return 1
  repo=$(blacksmith_config_get '.github.repo')   || return 1
  if [[ -n "$labels_csv" ]]; then
    local l; local -a _labels=()
    IFS=',' read -ra _labels <<< "$labels_csv"   # IFS scoped to this read only
    for l in "${_labels[@]}"; do label_args+=( -f "labels[]=$l" ); done
  fi
  # NOTE: "${label_args[@]+...}" — empty-array-safe expansion; a bare
  # "${label_args[@]}" on an empty array trips `set -u` on bash 3.2 (macOS).
  raw=$(gh api "repos/${owner}/${repo}/issues" -f title="$title" -f body="$body" "${label_args[@]+"${label_args[@]}"}" 2>/dev/null) \
    || { _blacksmith_die "create_issue failed (gh api)"; return 1; }
  number=$(printf '%s' "$raw" | jq -er '.number')  || { _blacksmith_die "create_issue: no number in response"; return 1; }
  node_id=$(printf '%s' "$raw" | jq -er '.node_id') || { _blacksmith_die "create_issue: no node_id in response"; return 1; }
  url=$(printf '%s' "$raw" | jq -r '.html_url')
  # Add the new issue to the configured Project v2 board (GraphQL, not preview REST).
  project_id=$(_blacksmith_github_project_id) || return 1
  # shellcheck disable=SC2016
  gh api graphql -f query='
    mutation($project: ID!, $content: ID!) {
      addProjectV2ItemById(input: { projectId: $project, contentId: $content }) {
        item { id }
      }
    }
  ' -f project="$project_id" -f content="$node_id" >/dev/null 2>&1 \
    || { _blacksmith_die "create_issue: created #$number but failed to add it to the board"; return 1; }
  jq -nc --argjson n "$number" --arg u "$url" '{number: $n, url: $u}'
}

# --- Parent/child hierarchy (native sub-issues; #26 slice 4) ---------------

# Link a child issue under a parent via native GitHub sub-issues. GOTCHA: the
# sub-issues API takes the child's DATABASE id (int64), NOT its issue number, so
# resolve the id first. Side-effect op; no stdout on success.
#   link_parent <parent_number> <child_number>
_blacksmith_github_link_parent() {
  local parent="$1" child="$2" owner repo child_id
  owner=$(blacksmith_config_get '.github.owner') || return 1
  repo=$(blacksmith_config_get '.github.repo')   || return 1
  child_id=$(gh api "repos/${owner}/${repo}/issues/${child}" --jq '.id' 2>/dev/null) \
    || { _blacksmith_die "link_parent: cannot resolve child #$child"; return 1; }
  gh api "repos/${owner}/${repo}/issues/${parent}/sub_issues" -F sub_issue_id="$child_id" >/dev/null 2>&1 \
    || { _blacksmith_die "link_parent: failed to link #$child under #$parent"; return 1; }
}

# Echo a parent's children as a normalized JSON array: [ { number, state, title, url } ].
# Native sub-issues query (GA 2025-04-09) — not body-parse.
#   list_children <parent_number>
_blacksmith_github_list_children() {
  local parent="$1" owner repo raw
  owner=$(blacksmith_config_get '.github.owner') || return 1
  repo=$(blacksmith_config_get '.github.repo')   || return 1
  raw=$(gh api "repos/${owner}/${repo}/issues/${parent}/sub_issues?per_page=100" 2>/dev/null) \
    || { _blacksmith_die "list_children: query failed for #$parent"; return 1; }
  printf '%s' "$raw" | jq -c '[ .[] | { number, state, title, url: .html_url } ]'
}

# --- Milestone assignment (Epoch placement; pipeline redesign) --------------
# Set an issue's milestone by TITLE — the milestone must already exist (creating
# Epoch milestones is a one-time setup step; SETTING one per issue is not). Resolves
# title -> number, then PATCHes the issue. Side-effect op; no stdout on success.
#   set_milestone <issue> <milestone_title>
_blacksmith_github_set_milestone() {
  local issue="$1" title="$2" owner repo raw number
  [[ -n "$title" ]] || { _blacksmith_die "set_milestone: milestone title required"; return 1; }
  owner=$(blacksmith_config_get '.github.owner') || return 1
  repo=$(blacksmith_config_get '.github.repo')   || return 1
  raw=$(gh api "repos/${owner}/${repo}/milestones?state=all&per_page=100" 2>/dev/null) \
    || { _blacksmith_die "set_milestone: cannot list milestones"; return 1; }
  number=$(printf '%s' "$raw" | jq -er --arg t "$title" 'map(select(.title==$t)) | .[0].number') \
    || { _blacksmith_die "set_milestone: milestone '$title' not found (create it first)"; return 1; }
  gh api "repos/${owner}/${repo}/issues/${issue}" -X PATCH -F milestone="$number" >/dev/null 2>&1 \
    || { _blacksmith_die "set_milestone: failed to set #$issue -> '$title'"; return 1; }
}

# --- Dependency write (native blocked-by edge) ------------------------------
# Record that <blocked> is BLOCKED BY <blocker> as a native typed edge (the read
# side is blacksmith_read_deps). GOTCHA: the dependencies API takes the blocker's
# DATABASE id (int64), NOT its issue number — resolve it first (like link_parent).
# Side-effect op; no stdout on success. add_dep <blocked_number> <blocker_number>
_blacksmith_github_add_dep() {
  local blocked="$1" blocker="$2" owner repo blocker_id
  owner=$(blacksmith_config_get '.github.owner') || return 1
  repo=$(blacksmith_config_get '.github.repo')   || return 1
  blocker_id=$(gh api "repos/${owner}/${repo}/issues/${blocker}" --jq '.id' 2>/dev/null) \
    || { _blacksmith_die "add_dep: cannot resolve blocker #$blocker"; return 1; }
  gh api "repos/${owner}/${repo}/issues/${blocked}/dependencies/blocked_by" -F issue_id="$blocker_id" >/dev/null 2>&1 \
    || { _blacksmith_die "add_dep: failed to record #$blocked blocked-by #$blocker"; return 1; }
}

# --- Base-branch resolution (per-Area; pipeline back-end) -------------------

# Forge-agnostic: read the Area branch from the adapter-owned marker `scope` writes
# (`<!-- oskr:area-branch <branch> -->`). NOT human prose — phrases like "the Area
# branch: read the base ..." collide. Echoes the branch or nothing.
_blacksmith_area_branch_from_body() {
  printf '%s' "$1" | sed -nE 's@.*<!-- oskr:area-branch ([A-Za-z0-9._/-]+) -->.*@\1@p' | head -1
}

# Resolve the base branch a task's PR should target: the Area branch recorded on
# its umbrella's PRD Placement (own body first, then the native parent), falling
# back to config .base_branch (default main) for solo / area-less tasks. Every
# execution site calls this — the one base seam. base_branch <issue#>
_blacksmith_github_base_branch() {
  local issue="$1" owner repo body ab parent default
  owner=$(blacksmith_config_get '.github.owner') || return 1
  repo=$(blacksmith_config_get '.github.repo')   || return 1
  default=$(blacksmith_config_get '.base_branch' 2>/dev/null || true); [[ -n "$default" && "$default" != "null" ]] || default="main"
  body=$(gh api "repos/${owner}/${repo}/issues/${issue}" --jq '.body // ""' 2>/dev/null || true)
  ab=$(_blacksmith_area_branch_from_body "$body"); [[ -n "$ab" ]] && { printf '%s' "$ab"; return 0; }
  parent=$(gh api "repos/${owner}/${repo}/issues/${issue}/parent" --jq '.number' 2>/dev/null || true)
  if [[ -n "$parent" && "$parent" != "null" ]]; then
    body=$(gh api "repos/${owner}/${repo}/issues/${parent}" --jq '.body // ""' 2>/dev/null || true)
    ab=$(_blacksmith_area_branch_from_body "$body"); [[ -n "$ab" ]] && { printf '%s' "$ab"; return 0; }
  fi
  printf '%s' "$default"
}

# --- Existing-issue detection (adopt consent gate; #27 T6) ------------------
# Echo the count of EXISTING issues on the configured repo (open+closed). Pull
# requests are EXCLUDED — GitHub's REST issues list interleaves PRs. The adopt
# consent gate reads this: >0 => prompt full-vs-register; 0 => no prompt. Single
# page (per_page=100) is sufficient for the >0-vs-0 gate. Never fails the caller
# (echo 0 on any error) so the gate degrades to "no existing".
_blacksmith_github_count_issues() {
  local owner repo
  owner=$(blacksmith_config_get '.github.owner') || return 1
  repo=$(blacksmith_config_get '.github.repo')   || return 1
  gh api "repos/${owner}/${repo}/issues?state=all&per_page=100" \
    --jq '[ .[] | select(has("pull_request") | not) ] | length' 2>/dev/null || echo 0
}

# ===========================================================================
# FORGEJO BACKEND (_blacksmith_forgejo_*)
# ---------------------------------------------------------------------------
# Forgejo/Gitea has no Projects/board REST API, so columns/fields are exclusive
# scoped labels; the issue IS the board item. Transport is raw REST over curl
# with a PAT, base URL + owner/repo from the project config's `.forgejo` section,
# token from $FORGEJO_TOKEN. See docs/research/2026-06-27-backend-capability.md.
# ---------------------------------------------------------------------------

# Authenticated Forgejo REST call. Keeps the PAT OFF argv — it is passed via a
# curl config read from stdin, so the secret never appears in the process table
# (`ps`). The JSON body (non-secret) stays on argv. Echoes the response body.
#   _blacksmith_forgejo_curl <METHOD> <path> [json_body]
_blacksmith_forgejo_curl() {
  local method="$1" path="$2" body="${3:-}" base url
  base=$(blacksmith_config_get '.forgejo.base_url') || return 1
  url="${base%/}/api/v1${path}"
  local -a args=(-fsS --config - -X "$method")
  [[ -n "$body" ]] && args+=(-H "Content-Type: application/json" -d "$body")
  args+=("$url")
  curl "${args[@]}" <<CFG
header = "Authorization: token ${FORGEJO_TOKEN:-}"
CFG
}

# Echo the blocked-by edges of an issue as the SAME normalized JSON array the
# GitHub backend returns. Native Forgejo issue-dependencies API (GA since v1.20):
#   GET /api/v1/repos/{owner}/{repo}/issues/{index}/dependencies = the blockers.
_blacksmith_forgejo_read_deps() {
  local issue="$1" owner repo raw
  owner=$(blacksmith_config_get '.forgejo.owner') || return 1
  repo=$(blacksmith_config_get '.forgejo.repo')   || return 1
  raw=$(_blacksmith_forgejo_curl GET "/repos/${owner}/${repo}/issues/${issue}/dependencies") \
    || { _blacksmith_die "read_deps (forgejo) query failed for issue #$issue"; return 1; }
  printf '%s' "$raw" | jq -c '[ .[] | {
      number,
      state,
      title,
      repository: (.repository.full_name // ""),
      url: .html_url
    } ]'
}

# Forgejo harvest: same neutral shape. `type=issues` excludes PRs server-side.
_blacksmith_forgejo_list_issues() {
  local owner repo raw
  owner=$(blacksmith_config_get '.forgejo.owner') || return 1
  repo=$(blacksmith_config_get '.forgejo.repo')   || return 1
  raw=$(_blacksmith_forgejo_curl GET "/repos/${owner}/${repo}/issues?type=issues&state=all&limit=100") \
    || { _blacksmith_die "list_issues (forgejo) query failed"; return 1; }
  printf '%s' "$raw" | jq -c '[ .[]
    | { number, title, state, body: (.body // ""), labels: [ (.labels // [])[] | .name ] } ]'
}

# Probe whether owner/repo exists on the Forgejo instance. Returns 0 if it
# exists, non-zero otherwise. Same neutral contract as the GitHub probe.
#   remote_exists <owner> <repo>
_blacksmith_forgejo_remote_exists() {
  local owner="$1" repo="$2"
  _blacksmith_forgejo_curl GET "/repos/${owner}/${repo}" >/dev/null 2>&1
}

# On Forgejo the issue IS the board item, so the "item handle" callers pass around
# is just the issue number. find_item echoes it back if the issue exists.
_blacksmith_forgejo_find_item() {
  local issue="$1" owner repo
  owner=$(blacksmith_config_get '.forgejo.owner') || return 1
  repo=$(blacksmith_config_get '.forgejo.repo')   || return 1
  if _blacksmith_forgejo_curl GET "/repos/${owner}/${repo}/issues/${issue}" >/dev/null 2>&1; then
    printf '%s' "$issue"
  fi
}

# The handle already IS the issue number.
_blacksmith_forgejo_item_issue_number() { printf '%s' "$1"; }

# Create an issue (+ initial status/backlog and any csv labels, by name). Echoes
# the neutral { number, url }. Requires the scoped labels to exist on the repo
# (provisioned in setup); a missing label is tolerated so the issue still lands.
#   create_issue <title> [body] [labels_csv]
_blacksmith_forgejo_create_issue() {
  local title="$1" body="${2:-}" labels_csv="${3:-}" owner repo raw number url
  [[ -n "$title" ]] || { _blacksmith_die "create_issue: title required"; return 1; }
  owner=$(blacksmith_config_get '.forgejo.owner') || return 1
  repo=$(blacksmith_config_get '.forgejo.repo')   || return 1
  raw=$(_blacksmith_forgejo_curl POST "/repos/${owner}/${repo}/issues" \
        "$(jq -nc --arg t "$title" --arg b "$body" '{title:$t, body:$b}')") \
    || { _blacksmith_die "create_issue (forgejo) failed"; return 1; }
  number=$(jq -er '.number' <<<"$raw")  || { _blacksmith_die "create_issue: no number in response"; return 1; }
  url=$(jq -r '.html_url' <<<"$raw")
  local -a names=("status/backlog")
  if [[ -n "$labels_csv" ]]; then
    local -a extra=(); IFS=',' read -ra extra <<<"$labels_csv"
    names+=("${extra[@]+"${extra[@]}"}")
  fi
  local labels_json; labels_json=$(printf '%s\n' "${names[@]}" | jq -R . | jq -sc '{labels: .}')
  _blacksmith_forgejo_curl POST "/repos/${owner}/${repo}/issues/${number}/labels" "$labels_json" >/dev/null 2>&1 || true
  jq -nc --argjson n "$number" --arg u "$url" '{number: $n, url: $u}'
}

# Move an issue to a column by adding the exclusive status/<slug> label. The
# exclusive flag auto-evicts the previous status/* label in one atomic call
# (verified live). column may be a slug or display name; normalize to the slug.
#   move_issue <issue_number> <column>
_blacksmith_forgejo_move_issue() {
  local issue="$1" column="$2" owner repo slug
  owner=$(blacksmith_config_get '.forgejo.owner') || return 1
  repo=$(blacksmith_config_get '.forgejo.repo')   || return 1
  slug=$(_blacksmith_normalize_slug "$column")
  _blacksmith_forgejo_curl POST "/repos/${owner}/${repo}/issues/${issue}/labels" \
    "$(jq -nc --arg l "status/${slug}" '{labels: [$l]}')" >/dev/null \
    || { _blacksmith_die "move_issue (forgejo) failed: #$issue -> status/$slug"; return 1; }
}

# Echo the column DISPLAY NAME for an issue (read off its status/* label), or
# empty if uncolumned. Display name resolved via config, identical to GitHub.
_blacksmith_forgejo_issue_status() {
  local issue="$1" owner repo raw slug
  owner=$(blacksmith_config_get '.forgejo.owner') || return 1
  repo=$(blacksmith_config_get '.forgejo.repo')   || return 1
  raw=$(_blacksmith_forgejo_curl GET "/repos/${owner}/${repo}/issues/${issue}") || return 1
  slug=$(printf '%s' "$raw" | jq -r '
    [ (.labels // [])[].name | select(startswith("status/")) ][0] // "" | sub("^status/"; "")')
  [[ -n "$slug" ]] || return 0
  _blacksmith_display_name_for "$slug"
}

# The handle is the issue number, so item_status == issue_status.
_blacksmith_forgejo_item_status() { _blacksmith_forgejo_issue_status "$@"; }

# Ensure a label exists (idempotent; never fails the caller). Forgejo wants a
# '#'-prefixed hex color; the neutral callers pass bare hex (GitHub style).
_blacksmith_forgejo_ensure_label() {
  local name="$1" description="${2:-}" color="${3:-888888}" owner repo
  owner=$(blacksmith_config_get '.forgejo.owner') || return 1
  repo=$(blacksmith_config_get '.forgejo.repo')   || return 1
  [[ "$color" == \#* ]] || color="#$color"
  _blacksmith_forgejo_curl POST "/repos/${owner}/${repo}/labels" \
    "$(jq -nc --arg n "$name" --arg d "$description" --arg c "$color" '{name:$n, description:$d, color:$c}')" \
    >/dev/null 2>&1 || true
}

# Idempotent EXCLUSIVE scoped-label create (a single-select board column). Unlike
# the neutral _blacksmith_forgejo_ensure_label, sets exclusive:true so assigning one
# label in a scope auto-evicts the prior same-scope label (server-enforced; see
# docs/research/2026-06-27-backend-capability.md:43-49). Never fails the caller
# (re-creating an existing label 422s and is tolerated for idempotency).
#   _blacksmith_forgejo_ensure_exclusive_label <name> [description] [color]
_blacksmith_forgejo_ensure_exclusive_label() {
  local name="$1" description="${2:-}" color="${3:-ededed}" owner repo
  owner=$(blacksmith_config_get '.forgejo.owner') || return 1
  repo=$(blacksmith_config_get '.forgejo.repo')   || return 1
  [[ "$color" == \#* ]] || color="#$color"
  _blacksmith_forgejo_curl POST "/repos/${owner}/${repo}/labels" \
    "$(jq -nc --arg n "$name" --arg d "$description" --arg c "$color" \
        '{name:$n, exclusive:true, color:$c, description:$d}')" \
    >/dev/null 2>&1 || true
}

# Assert the per-repo issue-dependencies unit is enabled. If it is off, Forgejo's
# /dependencies endpoints 404 and read_deps/add_dep silently degrade — so this is a
# LOUD gate at provisioning time, not a silent skip. Reads internal_tracker off the
# repo object. See docs/research/2026-06-27-backend-capability.md:41,124.
#   _blacksmith_forgejo_assert_deps_unit <owner> <repo>
_blacksmith_forgejo_assert_deps_unit() {
  local owner="$1" repo="$2" raw enabled
  raw=$(_blacksmith_forgejo_curl GET "/repos/${owner}/${repo}") \
    || { _blacksmith_die "provision_board: cannot read repo ${owner}/${repo} to verify the issue-dependencies unit"; return 1; }
  enabled=$(printf '%s' "$raw" | jq -r '.internal_tracker.enable_issue_dependencies // false')
  [[ "$enabled" == "true" ]] \
    || { _blacksmith_die "provision_board: issue-dependencies unit is DISABLED on ${owner}/${repo}; enable it (repo Settings -> Units) before onboarding"; return 1; }
}

# Provision a Forgejo repo's board behind the seam: assert the issue-dependencies
# unit, then create the 8 status columns + priority/size/category taxonomy as
# EXCLUSIVE scoped labels. Idempotent on labels; fails LOUDLY if the deps unit is off.
# Live acceptance is Area 5's gate (bin/smoke/forgejo-roundtrip.sh); curl-shim-proven here.
#   provision_board
_blacksmith_forgejo_provision_board() {
  local owner repo slug
  owner=$(blacksmith_config_get '.forgejo.owner') || return 1
  repo=$(blacksmith_config_get '.forgejo.repo')   || return 1
  _blacksmith_forgejo_assert_deps_unit "$owner" "$repo" || return 1

  # The reshaped 8-column status scheme (slugs only; display names live in
  # _blacksmith_default_name_for_slug, owned by the T5 reshape — independent here).
  for slug in backlog scoping planning plan_approval ready in_progress in_review done; do
    _blacksmith_forgejo_ensure_exclusive_label "status/${slug}" "oskr status column" "ededed"
  done
  # Priority / Size / Category taxonomy (each scope single-select).
  for slug in p1 p2 p3;                      do _blacksmith_forgejo_ensure_exclusive_label "priority/${slug}" "oskr priority" "d73a4a"; done
  for slug in xs s m l xl;                   do _blacksmith_forgejo_ensure_exclusive_label "size/${slug}"     "oskr size"     "0e8a16"; done
  for slug in feature bug chore spike docs;  do _blacksmith_forgejo_ensure_exclusive_label "category/${slug}" "oskr category" "5319e7"; done
}

# Add a label to an issue by name (never fails the caller).
_blacksmith_forgejo_issue_add_label() {
  local issue="$1" label="$2" owner repo
  owner=$(blacksmith_config_get '.forgejo.owner') || return 1
  repo=$(blacksmith_config_get '.forgejo.repo')   || return 1
  _blacksmith_forgejo_curl POST "/repos/${owner}/${repo}/issues/${issue}/labels" \
    "$(jq -nc --arg l "$label" '{labels: [$l]}')" >/dev/null 2>&1 || true
}

# Post a comment on an issue (never fails the caller).
_blacksmith_forgejo_issue_comment() {
  local issue="$1" body="$2" owner repo
  owner=$(blacksmith_config_get '.forgejo.owner') || return 1
  repo=$(blacksmith_config_get '.forgejo.repo')   || return 1
  _blacksmith_forgejo_curl POST "/repos/${owner}/${repo}/issues/${issue}/comments" \
    "$(jq -nc --arg b "$body" '{body: $b}')" >/dev/null 2>&1 || true
}

# Echo the whole board in the backend-NEUTRAL shape (same as the GitHub backend):
#   { total, items:[ {number,title,status,priority,category,createdAt,body,
#                     assignees,comments,labels,blocking,blockedBy} ] }
# Synthesized from labels: status/priority/category come from the scoped labels
# (status mapped slug->display name, identical to GitHub); `labels` excludes the
# scoped ones. blocking/blockedBy are 0 (Forgejo's issue list carries no dep count;
# the dispatcher RANKS by them but never GATES, so this degrades ranking only).
_blacksmith_forgejo_list_board() {
  local owner repo raw smap
  owner=$(blacksmith_config_get '.forgejo.owner') || return 1
  repo=$(blacksmith_config_get '.forgejo.repo')   || return 1
  raw=$(_blacksmith_forgejo_curl GET "/repos/${owner}/${repo}/issues?type=issues&state=all&limit=100") || return 1
  smap=$(for s in backlog research needs_input planning approval ready in_progress in_review "done"; do
           printf '%s\t%s\n' "$s" "$(_blacksmith_display_name_for "$s")"
         done | jq -R 'split("\t") | {key: .[0], value: .[1]}' | jq -sc 'from_entries')
  printf '%s' "$raw" | jq -c --argjson smap "$smap" '
    [ .[]
      | ([ (.labels // [])[].name ]) as $labs
      | ($labs | map(select(startswith("status/")))   | (.[0] // "") | sub("^status/";"")) as $sslug
      | ($labs | map(select(startswith("priority/"))) | (.[0] // "") | sub("^priority/";"")) as $pslug
      | ($labs | map(select(startswith("category/"))) | (.[0] // "") | sub("^category/";"")) as $cslug
      | {
          number,
          title,
          status:   (if $sslug=="" then null else ($smap[$sslug] // $sslug) end),
          priority: (if $pslug=="" then null else $pslug end),
          category: (if $cslug=="" then null else $cslug end),
          createdAt: .created_at,
          body: (.body // ""),
          assignees: [ (.assignees // [])[].login ],
          comments: [],
          labels: [ $labs[] | select((startswith("status/") or startswith("priority/") or startswith("size/") or startswith("category/")) | not) ],
          blocking: 0,
          blockedBy: 0
        }
    ] | { total: length, items: . }'
}

# Echo the count of actionable issues (same filter as the GitHub backend); reuses
# the neutral board so the logic lives in one place.
_blacksmith_forgejo_count_actionable() {
  local actionable_json inprogress
  actionable_json=$(
    while IFS= read -r slug; do _blacksmith_display_name_for "$slug"; done \
      < <(blacksmith_config_get_array '.workflow.actionable_columns') | jq -R . | jq -sc .
  )
  inprogress=$(_blacksmith_display_name_for in_progress)
  _blacksmith_forgejo_list_board | jq --argjson act "$actionable_json" --arg ip "$inprogress" '
    [ .items[]
      | select( (.status as $n | $act | index($n))
                or (.status == $ip and (((.labels // []) | index("dispatch-incomplete")) != null)) )
      | select(((.labels // []) | index("loop-skip")) | not)
    ] | length'
}

# Archive = drop the issue off the board view by removing its status/* label
# (the issue itself is untouched). Forgejo has no project card to archive; this is
# the labels-as-columns analog. Never fails the caller.
_blacksmith_forgejo_archive_item() {
  local issue="$1" owner repo lid
  owner=$(blacksmith_config_get '.forgejo.owner') || return 1
  repo=$(blacksmith_config_get '.forgejo.repo')   || return 1
  lid=$(_blacksmith_forgejo_curl GET "/repos/${owner}/${repo}/issues/${issue}/labels" 2>/dev/null \
        | jq -r '[.[] | select(.name | startswith("status/"))][0].id // empty')
  [[ -n "$lid" ]] || return 0
  _blacksmith_forgejo_curl DELETE "/repos/${owner}/${repo}/issues/${issue}/labels/${lid}" >/dev/null 2>&1 || true
}

# --- Parent/child hierarchy (body-fenced; the one forced body-parse case) ---
# Forgejo has no native sub-issues, so containment is an adapter-owned, HTML-comment-
# fenced checklist in the PARENT body (canonical), parsed ONLY inside the fence.

# Rebuild the parent body with <child> added to the fenced child list. Pure text.
_blacksmith_fj_children_rewrite() {
  local body="$1" child="$2"
  local open="<!-- blacksmith:children -->" close="<!-- /blacksmith:children -->"
  local existing nums stripped fence n
  existing=$(printf '%s' "$body" | awk -v o="$open" -v c="$close" \
    '$0==o{inf=1;next} $0==c{inf=0;next} inf{print}' | grep -oE '#[0-9]+' | tr -d '#')
  nums=$(printf '%s\n%s\n' "$existing" "$child" | grep -E '^[0-9]+$' | sort -n -u)
  stripped=$(printf '%s' "$body" | awk -v o="$open" -v c="$close" \
    '$0==o{skip=1} !skip{print} $0==c{skip=0}')
  fence="$open"$'\n'
  while IFS= read -r n; do [[ -n "$n" ]] && fence+="- [ ] #${n}"$'\n'; done <<< "$nums"
  fence+="$close"
  printf '%s\n\n%s\n' "$(printf '%s' "$stripped" | sed -e 's/[[:space:]]*$//')" "$fence"
}

# Echo the child numbers in the parent's fenced list, one per line.
_blacksmith_fj_children_nums() {
  local body="$1" open="<!-- blacksmith:children -->" close="<!-- /blacksmith:children -->"
  printf '%s' "$body" | awk -v o="$open" -v c="$close" \
    '$0==o{inf=1;next} $0==c{inf=0;next} inf{print}' | grep -oE '#[0-9]+' | tr -d '#' | sort -n -u
}

# Link a child under a parent: add it to the parent's fenced checklist (canonical)
# and drop a parent marker in the child body. link_parent <parent> <child>
_blacksmith_forgejo_link_parent() {
  local parent="$1" child="$2" owner repo pbody nbody cbody
  owner=$(blacksmith_config_get '.forgejo.owner') || return 1
  repo=$(blacksmith_config_get '.forgejo.repo')   || return 1
  pbody=$(_blacksmith_forgejo_curl GET "/repos/${owner}/${repo}/issues/${parent}" | jq -r '.body // ""') \
    || { _blacksmith_die "link_parent: cannot read parent #$parent"; return 1; }
  nbody=$(_blacksmith_fj_children_rewrite "$pbody" "$child")
  _blacksmith_forgejo_curl PATCH "/repos/${owner}/${repo}/issues/${parent}" \
    "$(jq -nc --arg b "$nbody" '{body: $b}')" >/dev/null \
    || { _blacksmith_die "link_parent: failed to update parent #$parent"; return 1; }
  cbody=$(_blacksmith_forgejo_curl GET "/repos/${owner}/${repo}/issues/${child}" | jq -r '.body // ""')
  if ! printf '%s' "$cbody" | grep -q 'blacksmith:parent'; then
    _blacksmith_forgejo_curl PATCH "/repos/${owner}/${repo}/issues/${child}" \
      "$(jq -nc --arg b "${cbody}"$'\n\n'"<!-- blacksmith:parent #${parent} -->" '{body: $b}')" >/dev/null 2>&1 || true
  fi
}

# Echo a parent's children as the neutral array [ {number,state,title,url} ], read
# from the fenced list (then one fetch per child for state/title/url).
_blacksmith_forgejo_list_children() {
  local parent="$1" owner repo pbody items n ci
  owner=$(blacksmith_config_get '.forgejo.owner') || return 1
  repo=$(blacksmith_config_get '.forgejo.repo')   || return 1
  pbody=$(_blacksmith_forgejo_curl GET "/repos/${owner}/${repo}/issues/${parent}" | jq -r '.body // ""') || return 1
  items="[]"
  while IFS= read -r n; do
    [[ -n "$n" ]] || continue
    ci=$(_blacksmith_forgejo_curl GET "/repos/${owner}/${repo}/issues/${n}" 2>/dev/null) || continue
    items=$(printf '%s' "$ci" | jq -c --argjson acc "$items" '$acc + [{number, state, title, url: .html_url}]')
  done <<< "$(_blacksmith_fj_children_nums "$pbody")"
  printf '%s' "$items"
}

# --- Milestone assignment (Forgejo; native milestones, set by id) -----------
# Set an issue's milestone by TITLE (must already exist). Resolves title -> id via
# the milestones list, then PATCHes the issue. set_milestone <issue> <title>
_blacksmith_forgejo_set_milestone() {
  local issue="$1" title="$2" owner repo raw mid
  [[ -n "$title" ]] || { _blacksmith_die "set_milestone: milestone title required"; return 1; }
  owner=$(blacksmith_config_get '.forgejo.owner') || return 1
  repo=$(blacksmith_config_get '.forgejo.repo')   || return 1
  raw=$(_blacksmith_forgejo_curl GET "/repos/${owner}/${repo}/milestones?state=all&limit=100") \
    || { _blacksmith_die "set_milestone (forgejo): cannot list milestones"; return 1; }
  mid=$(printf '%s' "$raw" | jq -er --arg t "$title" 'map(select(.title==$t)) | .[0].id') \
    || { _blacksmith_die "set_milestone (forgejo): milestone '$title' not found (create it first)"; return 1; }
  _blacksmith_forgejo_curl PATCH "/repos/${owner}/${repo}/issues/${issue}" \
    "$(jq -nc --argjson m "$mid" '{milestone: $m}')" >/dev/null \
    || { _blacksmith_die "set_milestone (forgejo): failed to set #$issue -> '$title'"; return 1; }
}

# --- Dependency write (Forgejo native blocked-by) ---------------------------
# Record that <blocked> is BLOCKED BY <blocker>. Forgejo's dependency POST takes
# IssueMeta{owner,repo,index} where index = the blocker's issue NUMBER (not a db
# id). The read side is blacksmith_read_deps. add_dep <blocked> <blocker>
_blacksmith_forgejo_add_dep() {
  local blocked="$1" blocker="$2" owner repo
  owner=$(blacksmith_config_get '.forgejo.owner') || return 1
  repo=$(blacksmith_config_get '.forgejo.repo')   || return 1
  _blacksmith_forgejo_curl POST "/repos/${owner}/${repo}/issues/${blocked}/dependencies" \
    "$(jq -nc --arg o "$owner" --arg r "$repo" --argjson i "$blocker" '{owner:$o, repo:$r, index:$i}')" >/dev/null \
    || { _blacksmith_die "add_dep (forgejo): failed to record #$blocked blocked-by #$blocker"; return 1; }
}

# Resolve a task's base branch: the Area branch on its umbrella's PRD Placement
# (own body, then the parent via the body-fenced `blacksmith:parent #N` marker),
# else config .base_branch (default main). Mirrors the GitHub resolver's neutral
# behavior. base_branch <issue#>
_blacksmith_forgejo_base_branch() {
  local issue="$1" owner repo body ab parent default
  owner=$(blacksmith_config_get '.forgejo.owner') || return 1
  repo=$(blacksmith_config_get '.forgejo.repo')   || return 1
  default=$(blacksmith_config_get '.base_branch' 2>/dev/null || true); [[ -n "$default" && "$default" != "null" ]] || default="main"
  body=$(_blacksmith_forgejo_curl GET "/repos/${owner}/${repo}/issues/${issue}" 2>/dev/null | jq -r '.body // ""' || true)
  ab=$(_blacksmith_area_branch_from_body "$body"); [[ -n "$ab" ]] && { printf '%s' "$ab"; return 0; }
  parent=$(printf '%s' "$body" | sed -nE 's@.*blacksmith:parent #([0-9]+).*@\1@p' | head -1)
  if [[ -n "$parent" ]]; then
    body=$(_blacksmith_forgejo_curl GET "/repos/${owner}/${repo}/issues/${parent}" 2>/dev/null | jq -r '.body // ""' || true)
    ab=$(_blacksmith_area_branch_from_body "$body"); [[ -n "$ab" ]] && { printf '%s' "$ab"; return 0; }
  fi
  printf '%s' "$default"
}

# Echo the count of EXISTING issues (adopt consent gate; #27 T6). Forgejo's
# ?type=issues already excludes PRs. Never fails the caller (echo 0 on error).
_blacksmith_forgejo_count_issues() {
  local owner repo raw
  owner=$(blacksmith_config_get '.forgejo.owner') || return 1
  repo=$(blacksmith_config_get '.forgejo.repo')   || return 1
  raw=$(_blacksmith_forgejo_curl GET "/repos/${owner}/${repo}/issues?state=all&type=issues&limit=50") \
    || { echo 0; return 0; }
  printf '%s' "$raw" | jq 'length' 2>/dev/null || echo 0
}
