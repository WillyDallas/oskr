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

cmd="${1:-}"; [[ "$#" -gt 0 ]] && shift
case "$cmd" in
  skeleton) oskr_setup_skeleton "$@" ;;
  *)        _setup_die "usage: oskr-setup.sh {skeleton} [workspace_dir]" ;;
esac
