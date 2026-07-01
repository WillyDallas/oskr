#!/usr/bin/env bash
# registry.sh — oskr's workspace project registry CLI.
# Reads/writes <workspace>/.oskr/registry.json. The workspace root is resolved by
# the blacksmith resolver (blacksmith_workspace_dir; honors $OSKR_WORKSPACE). State
# lives in the WORKSPACE, never in the plugin source tree.
#
# Subcommands:
#   add     upsert-by-name a managed-project entry (idempotent; no dup by name)
#   list    echo the registry's .projects array (JSON)
#   migrate one-time, idempotent relocation of the legacy in-plugin registry
#
# Pure jq over local files; NO forge (gh/curl) calls — keeps the bin/ seam guard green.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/harness-lib.sh"

# Legacy in-plugin registry SOURCE (overridable so tests stay hermetic). registry.sh
# is the ONLY file allowed to name this path — it READS it to relocate it (migrate),
# and never writes plugin state. The stateless-plugin guard whitelists this file.
LEGACY_REGISTRY="${OSKR_LEGACY_REGISTRY:-$HOME/WillyDev/oskr/repos/projects.json}"

_registry_die() { echo "[registry] $1" >&2; exit 1; }

# Echo the workspace .oskr/ dir (created if missing). Does NOT create registry.json.
# Relies on the frozen T1 contract: blacksmith_workspace_dir echoes the workspace ROOT.
_registry_oskr_dir() {
  local ws
  ws=$(blacksmith_workspace_dir) || return 1
  mkdir -p "$ws/.oskr"
  printf '%s' "$ws/.oskr"
}

# Echo the registry.json path, first-creating an empty registry when absent.
_registry_file() {
  local d f
  d=$(_registry_oskr_dir) || return 1
  f="$d/registry.json"
  [[ -f "$f" ]] || echo '{"projects": []}' > "$f"
  printf '%s' "$f"
}

registry_add() {
  local name="" path="" forge="github"
  local owner="" repo="" project_number="" base_url=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)           name="$2"; shift 2 ;;
      --path)           path="$2"; shift 2 ;;
      --forge)          forge="$2"; shift 2 ;;
      --owner)          owner="$2"; shift 2 ;;
      --repo)           repo="$2"; shift 2 ;;
      --project-number) project_number="$2"; shift 2 ;;
      --base-url)       base_url="$2"; shift 2 ;;
      *) _registry_die "add: unknown flag '$1'" ;;
    esac
  done
  [[ -n "$name" ]] || _registry_die "add: --name required"
  [[ -n "$path" ]] || _registry_die "add: --path required"

  local f; f=$(_registry_file) || exit 1

  # Idempotent: a project with this name already present => no-op (no duplicate).
  if jq -e --arg n "$name" 'any(.projects[]; .name == $n)' "$f" >/dev/null 2>&1; then
    echo "[registry] '$name' already registered; no-op" >&2
    return 0
  fi

  local coords
  case "$forge" in
    github)
      coords=$(jq -nc --arg o "$owner" --arg r "$repo" --argjson pn "${project_number:-0}" \
        '{owner: $o, repo: $r, project_number: $pn}') ;;
    forgejo)
      coords=$(jq -nc --arg b "$base_url" --arg o "$owner" --arg r "$repo" \
        '{base_url: $b, owner: $o, repo: $r}') ;;
    *) _registry_die "add: unknown forge '$forge' (expected github|forgejo)" ;;
  esac

  local entry
  entry=$(jq -nc \
    --arg name "$name" --arg path "$path" --arg forge "$forge" \
    --argjson coords "$coords" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{name: $name, path: $path, forge: $forge} + {($forge): $coords} + {registered_at: $ts}')

  jq --argjson e "$entry" '.projects += [$e]' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}

registry_list() {
  local f; f=$(_registry_file) || exit 1
  jq -c '.projects' "$f"
}

# One-time, idempotent relocation of the legacy in-plugin registry into the
# workspace. Transforms GitHub-only legacy entries ({github:"owner/repo",
# project_number}) into the forge-tagged shape. No-op when the target already
# exists (already migrated) or the source is absent (nothing to migrate).
# SEQUENCING (T3): this MUST run before the first `add` in a workspace — `add`
# first-creates registry.json, after which this guard short-circuits and the
# legacy entries would be lost.
registry_migrate() {
  local d target
  d=$(_registry_oskr_dir) || exit 1
  target="$d/registry.json"

  if [[ -f "$target" ]]; then
    echo "[registry] already migrated ($target exists); no-op" >&2
    return 0
  fi
  if [[ ! -f "$LEGACY_REGISTRY" ]]; then
    echo "[registry] no legacy registry at $LEGACY_REGISTRY; no-op" >&2
    return 0
  fi

  jq '{projects: [ .projects[] | {
        name,
        path,
        forge: "github",
        github: {
          owner: ((.github // "") | split("/")[0]),
          repo:  ((.github // "") | split("/")[1]),
          project_number: (.project_number // 0)
        },
        registered_at: (.registered_at // "")
      } ]}' "$LEGACY_REGISTRY" > "$target.tmp" && mv "$target.tmp" "$target"
  echo "[registry] migrated $LEGACY_REGISTRY -> $target" >&2
}

case "${1:-}" in
  add)     shift; registry_add "$@" ;;
  list)    shift; registry_list "$@" ;;
  migrate) shift; registry_migrate "$@" ;;  # defined in Task 2
  *)       _registry_die "usage: registry.sh {add|list|migrate} ..." ;;
esac
