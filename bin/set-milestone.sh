#!/usr/bin/env bash
# Set an issue's milestone (the Epoch) BY TITLE via the blacksmith. The milestone
# must already exist — creating Epoch milestones is a one-time setup step.
# Usage: set-milestone.sh <issue> <milestone_title>
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/harness-lib.sh"
blacksmith_set_milestone "$@"
