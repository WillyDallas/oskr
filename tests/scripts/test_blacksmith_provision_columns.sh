#!/usr/bin/env bash
# blacksmith_provision_status_columns (GitHub, #27 T5): augment the project's Status
# field with the 8 canonical columns through the board-ops seam (shim replay).
# Verifies the mutation carries the live 8 columns, omits the retired 3, and that the
# verb echoes the resulting status field name.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/lib/assert.sh"

SHIM_DIR=$(mktemp -d); trap 'rm -rf "$SHIM_DIR"' EXIT
LOG="$SHIM_DIR/gh-calls.log"; : > "$LOG"
cp "$SCRIPT_DIR/lib/gh-shim.sh" "$SHIM_DIR/gh"; chmod +x "$SHIM_DIR/gh"

out=$(PATH="$SHIM_DIR:$PATH" \
  HARNESS_CONFIG="$REPO_ROOT/tests/scripts/fixtures/harness-config.sample.json" \
  GH_SHIM_CALL_LOG="$LOG" \
  GH_SHIM_FIXTURE="$REPO_ROOT/tests/scripts/fixtures/gh-provision-fields.json" \
  bash -c "source '$REPO_ROOT/bin/harness-lib.sh'; blacksmith_provision_status_columns 'PVT_kwTEST123'")

# Augment path: existing Status field is updated in place and its name echoed.
assert_eq 'Status' "$out" "verb echoes resulting status field name" || exit 1
grep -qF 'updateProjectV2Field' "$LOG" || { echo "FAIL: did not augment the Status field" >&2; exit 1; }

# All 8 live columns are provisioned.
for c in "Backlog" "Scoping" "Planning" "Plan Approval" "Ready" "In Progress" "In Review" "Done"; do
  grep -qF "name: \"$c\"" "$LOG" || { echo "FAIL: column '$c' not provisioned" >&2; exit 1; }
done

# The retired 9-column options are gone. (name: "Plan Approval" does not match name: "Approval".)
for c in "Research" "Needs Input" "Approval"; do
  ! grep -qF "name: \"$c\"" "$LOG" || { echo "FAIL: retired column '$c' still provisioned" >&2; exit 1; }
done

echo "test_blacksmith_provision_columns: PASS"
