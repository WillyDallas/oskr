#!/usr/bin/env bash
# adopt-harvest.sh — full-migration adopt, step 1. Read ALL existing issues (via
# the blacksmith, so backend-neutral) into a markdown reconciliation tasklist. The
# developer then reconciles current state BY HAND (see docs/adopt-reintake.md)
# before adopt-reemit.sh re-emits the result. No forge calls inline — all through
# blacksmith_list_issues.
# Usage: adopt-harvest.sh <out_file>
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/harness-lib.sh"

out="${1:?usage: adopt-harvest.sh <out_file>}"
issues=$(blacksmith_list_issues) || exit 1
{
  echo "# Adopt harvest — reconcile current state, then re-emit"
  echo "<!-- oskr:adopt-harvest -->"
  echo
  echo "Reconcile this list by hand (see docs/adopt-reintake.md), then feed the"
  echo "reconciled plan to: adopt-reemit.sh <reconciled-plan.json>"
  echo
  printf '%s' "$issues" | jq -r '.[] | "- [ ] #\(.number) \(.title) (\(.state))"'
} > "$out"
echo "$out"
