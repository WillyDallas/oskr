#!/usr/bin/env bash
# Echo an Area umbrella's children as JSON [ {number,state,title,url} ] via the
# blacksmith — native sub-issues on GitHub, fenced checklist on Forgejo.
# Usage: list-children.sh <parent>
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/harness-lib.sh"
blacksmith_list_children "$@"
