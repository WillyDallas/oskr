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

# --- Project / field discovery ---------------------------------------------
#
# Note: this layer always hits gh; Task 5's cache layer wraps these via
# _harness_get_discovery() which reads from / writes to disk. Until Task 5
# lands, _harness_discover_raw() is the entry point.

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
