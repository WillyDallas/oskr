#!/usr/bin/env bash
# adopt-reemit.sh — full-migration adopt, step 3. Re-emit a reconciled plan into
# oskr board structure: one Epoch milestone, each phase an Area umbrella
# (type/umbrella + area/<slug>), each task a slim ## Parent/## What/## AC issue
# (delivery/manual) linked beneath its umbrella. Backend-neutral — every forge op
# goes through the blacksmith. The board lands "dispatch off": no issue is moved
# into an actionable column here.
# Usage: adopt-reemit.sh <reconciled-plan.json>
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/harness-lib.sh"

plan="${1:?usage: adopt-reemit.sh <reconciled-plan.json>}"
[[ -f "$plan" ]] || { echo "[adopt-reemit] plan file not found: $plan" >&2; exit 1; }

epoch=$(jq -er '.epoch' "$plan") || { echo "[adopt-reemit] plan has no .epoch" >&2; exit 1; }

# Ensure the structural labels adopt attaches exist before use (idempotent).
blacksmith_ensure_label "type/umbrella"   "Area umbrella"                      "5319e7"
blacksmith_ensure_label "delivery/manual" "Manual delivery (no auto-dispatch)" "c5def5"

# Materialize the Epoch milestone (idempotent find-or-create).
blacksmith_create_milestone "$epoch" >/dev/null

area_count=$(jq '.areas | length' "$plan")
for (( ai = 0; ai < area_count; ai++ )); do
  slug=$(jq -er ".areas[$ai].slug"  "$plan")
  atitle=$(jq -er ".areas[$ai].title" "$plan")
  awhat=$(jq -r  ".areas[$ai].what"  "$plan")
  aac=$(jq -r    ".areas[$ai].ac"    "$plan")

  blacksmith_ensure_label "area/${slug}" "Area: ${slug}" "0e8a16"
  abody=$(printf '## What\n\n%s\n\n## AC\n\n%s\n' "$awhat" "$aac")
  umbrella=$(blacksmith_create_issue "$atitle" "$abody" "type/umbrella,area/${slug}" | jq -er '.number') \
    || { echo "[adopt-reemit] failed to create umbrella for $slug" >&2; exit 1; }
  blacksmith_set_milestone "$umbrella" "$epoch"
done
