#!/usr/bin/env bash
# hjarne-lib.sh — the brain write seam: oskr's pure-filesystem knowledge helpers.
# Sourceable; not directly executable. Forge-blind (no gh, no curl).
#
# These helpers file durable knowledge into the project brain (<workspace>/hjarne):
# raw archival, wiki routing, an append-only log, version-stamped pages, an inbox
# stage/drain, and the hjarne_integrate orchestrator. The /hjarne skill drives them.
#
# Scope assumption: this file is tail-sourced by bin/harness-lib.sh, so
# blacksmith_workspace_dir and _blacksmith_die are already in scope. It defines
# functions only — no top-level statement runs, so it is safe to `source` under
# `set -euo pipefail`.

# Echo the brain root: <workspace>/hjarne. Propagates blacksmith_workspace_dir's
# loud error to stderr when no workspace resolves.
hjarne_resolve_brain() {
  local ws
  ws=$(blacksmith_workspace_dir) || return 1
  echo "$ws/hjarne"
}
