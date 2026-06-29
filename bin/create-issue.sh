#!/usr/bin/env bash
# Create an issue (+ add it to the board) via the blacksmith. Echoes { number, url }.
# Backend-neutral: works on GitHub or Forgejo per the project's harness-config.
# Usage: create-issue.sh <title> [body] [labels_csv]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/harness-lib.sh"
blacksmith_create_issue "$@"
