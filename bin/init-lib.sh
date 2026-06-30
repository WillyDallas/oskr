#!/usr/bin/env bash
# init-lib.sh — init v2 helpers: mode detection + config emission.
# Sourceable; NOT directly executable. Pure (network-free, disk-free) by design —
# the one forge-coupled detection input (does the repo exist on the forge?) is
# supplied by the caller via blacksmith_remote_exists (harness-lib.sh), keeping
# these functions subshell-testable. See docs/design/platform-reframe.md and the
# Area #27 PRD.

_init_die() {
  echo "[init] $1" >&2
  return 1
}

# init_detect_mode <is_git> <has_origin> <remote_exists> <config_present>
# Each arg is "yes" or "no" (anything not "yes" is treated as "no"). Echoes
# exactly one of:
#   already-init  — harness-config.json present; the caller refuses re-init
#   adopt         — local git repo already wired to an origin remote
#   clone         — repo exists on the forge but not here
#   create-new    — nothing exists locally or on the forge
# Precedence: config > origin > forge-remote > nothing. Pure; no network, no disk.
init_detect_mode() {
  local is_git="${1:-no}" has_origin="${2:-no}" remote_exists="${3:-no}" config_present="${4:-no}"
  if [[ "$config_present" == "yes" ]]; then echo "already-init"; return 0; fi
  if [[ "$is_git" == "yes" && "$has_origin" == "yes" ]]; then echo "adopt"; return 0; fi
  if [[ "$remote_exists" == "yes" ]]; then echo "clone"; return 0; fi
  echo "create-new"
}
