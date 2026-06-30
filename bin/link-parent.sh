#!/usr/bin/env bash
# Link a child task under a parent (Area umbrella) via the blacksmith — native
# sub-issue on GitHub, body-fenced checklist on Forgejo.
# Usage: link-parent.sh <parent> <child>
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/harness-lib.sh"
blacksmith_link_parent "$@"
