#!/usr/bin/env bash
# oskr-setup.sh — workspace-tier bootstrap verbs (skeleton + global config).
# Pure filesystem/JSON; touches NO forge, so it stays OUTSIDE the backend seam
# (no gh/curl). The interactive walkthrough lives in skills/oskr-setup/SKILL.md,
# which gathers config then calls these verbs.
#
# Workspace CREATION anchors at an explicit dir (default $PWD) — it does NOT use
# the upward .oskr/ resolver (blacksmith_workspace_dir), which only FINDS an
# existing workspace. Secrets are NEVER written here (creds live in .env / gh).
set -euo pipefail

_setup_die() { echo "[oskr-setup] $1" >&2; exit 1; }

# Create the workspace skeleton and first-create an empty project registry.
# Idempotent on dirs (mkdir -p) and on the registry (first-create only).
#   skeleton <workspace_dir>
oskr_setup_skeleton() {
  local ws="${1:-$PWD}"
  mkdir -p "$ws/.oskr" "$ws/projects" "$ws/hjarne" "$ws/learning"
  if [[ ! -f "$ws/.oskr/registry.json" ]]; then
    printf '%s\n' '{"projects": []}' > "$ws/.oskr/registry.json"
  fi
}

# Write .oskr/config.json from environment-supplied NON-SECRET values. Guarded:
# refuses if a config already exists so re-running setup never clobbers a live
# workspace. Credentials are NOT written here — they live in the workspace .env
# (FORGEJO_TOKEN) / gh keychain; this records only backend selection + coords.
#   write-config <workspace_dir>
# Env: OSKR_FORGE (default github)  OSKR_BASE_BRANCH (default main)
#      OSKR_GITHUB_OWNER (optional) OSKR_FORGEJO_BASE_URL (optional)
oskr_setup_write_config() {
  local ws="${1:-$PWD}" cfg
  [[ -d "$ws/.oskr" ]] || _setup_die "no .oskr/ at $ws — run 'skeleton' first"
  cfg="$ws/.oskr/config.json"
  [[ -f "$cfg" ]] && _setup_die "workspace already configured ($cfg); not clobbering"
  jq -n \
    --arg forge "${OSKR_FORGE:-github}" \
    --arg base  "${OSKR_BASE_BRANCH:-main}" \
    --arg owner "${OSKR_GITHUB_OWNER:-}" \
    --arg furl  "${OSKR_FORGEJO_BASE_URL:-}" \
    '{version: 1, forge: $forge, base_branch: $base,
      github: {owner: $owner}, forgejo: {base_url: $furl}}' > "$cfg.tmp" \
    && mv "$cfg.tmp" "$cfg"
  jq . "$cfg" >/dev/null || _setup_die "wrote malformed config"
}

cmd="${1:-}"; [[ "$#" -gt 0 ]] && shift
case "$cmd" in
  skeleton)     oskr_setup_skeleton "$@" ;;
  write-config) oskr_setup_write_config "$@" ;;
  *)            _setup_die "usage: oskr-setup.sh {skeleton|write-config} [workspace_dir]" ;;
esac
