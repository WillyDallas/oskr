#!/usr/bin/env bash
# Record that <blocked> is BLOCKED BY <blocker> as a native typed edge via the
# blacksmith (read side: the board's blockedBy). Backend-neutral.
# Usage: add-dep.sh <blocked> <blocker>
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/harness-lib.sh"
blacksmith_add_dep "$@"
