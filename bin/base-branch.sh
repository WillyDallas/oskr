#!/usr/bin/env bash
# Resolve the base branch a task's PR should target (its Area branch, else the
# configured default) via the blacksmith. Backend-neutral.
# Usage: base-branch.sh <issue#>
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/harness-lib.sh"
blacksmith_base_branch "$@"
