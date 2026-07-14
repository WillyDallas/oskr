#!/usr/bin/env bash
# _blacksmith_github_provision_board (#103): full board provisioning through the
# seam — create project (owner node id from the REPOSITORY, so org-owned repos
# work), link to repo, 8 status columns, Priority/Size/Category taxonomy — and
# the backend-neutral {project_number, url, status_field} echo the caller uses
# to backfill harness-config.json. Shim replay; asserts request shape + output
# contract, never internals.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FIX="$REPO_ROOT/tests/scripts/fixtures"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"

SHIM_DIR=$(mktemp -d); trap 'rm -rf "$SHIM_DIR"' EXIT
LOG="$SHIM_DIR/gh-calls.log"; : > "$LOG"
cp "$SCRIPT_DIR/lib/gh-shim.sh" "$SHIM_DIR/gh"; chmod +x "$SHIM_DIR/gh"

out=$(PATH="$SHIM_DIR:$PATH" \
  HARNESS_CONFIG="$FIX/harness-config.sample.json" \
  GH_SHIM_CALL_LOG="$LOG" \
  GH_SHIM_FIXTURE="$FIX/gh-provision-fields.json" \
  GH_SHIM_REPO_IDS_FIXTURE="$FIX/gh-repo-ids.json" \
  GH_SHIM_CREATE_PROJECT_FIXTURE="$FIX/gh-create-project.json" \
  bash -c "source '$REPO_ROOT/bin/harness-lib.sh'; blacksmith_provision_board")

# Neutral output contract: the real number/url from the create response, and the
# status field name from the columns provisioner.
assert_eq "7"      "$(jq -r '.project_number' <<<"$out")" "echoes the real project number" || exit 1
assert_eq "Status" "$(jq -r '.status_field'   <<<"$out")" "echoes the status field name"   || exit 1
jq -e '.url | startswith("https://")' <<<"$out" >/dev/null || { echo "FAIL: no project url in output" >&2; exit 1; }

# Request shape: title from config .name, owner id from the repository owner,
# the repo link, all 8 columns, and the three taxonomy fields.
grep -qF 'oskr — oskr-test'            "$LOG" || { echo "FAIL: project title not built from config .name" >&2; exit 1; }
grep -qF 'ownerId=O_owner1'            "$LOG" || { echo "FAIL: createProjectV2 not using the repository owner node id" >&2; exit 1; }
grep -qF 'linkProjectV2ToRepository'   "$LOG" || { echo "FAIL: project never linked to the repo" >&2; exit 1; }
grep -qF 'repoId=R_repo1'              "$LOG" || { echo "FAIL: link not targeting the repo node id" >&2; exit 1; }
for c in "Backlog" "Scoping" "Planning" "Plan Approval" "Ready" "In Progress" "In Review" "Done"; do
  grep -qF "name: \"$c\"" "$LOG" || { echo "FAIL: column '$c' not provisioned" >&2; exit 1; }
done
for f in Priority Size Category; do
  grep -qF "name: \\\"$f\\\"" "$LOG" || grep -qF "name: \"$f\"" "$LOG" \
    || { echo "FAIL: taxonomy field '$f' not created" >&2; exit 1; }
done

echo "test_blacksmith_github_provision_board: PASS"
