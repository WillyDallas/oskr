#!/usr/bin/env bash
# Adopt detection (#27 T6): probe the configured forge for EXISTING issues and
# emit the consent-gate verdict for init's adopt mode. Forge-agnostic — all forge
# I/O goes through the blacksmith, so this script makes NO inline gh/curl calls.
#
#   stdout: "existing <N>"  (N>0 — repo has a workflow; prompt full-vs-register)
#           "empty 0"       (no existing issues; proceed without a migration prompt)
#
# Reads repo coords from the harness-config.json that init's mode-detection +
# config emission (#27 T4) writes for adopt mode before this gate runs.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/harness-lib.sh"

count=$(blacksmith_count_issues || echo 0)
[[ "$count" =~ ^[0-9]+$ ]] || count=0
if [[ "$count" -gt 0 ]]; then
  echo "existing $count"
else
  echo "empty 0"
fi
