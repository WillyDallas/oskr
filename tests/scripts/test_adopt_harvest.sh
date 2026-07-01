#!/usr/bin/env bash
# adopt-harvest.sh: read all existing issues (via the blacksmith) into a markdown
# reconciliation tasklist. Backend-neutral; here proven on GitHub via gh-shim.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FIX="$REPO_ROOT/tests/scripts/fixtures"
source "$SCRIPT_DIR/lib/assert.sh"

SHIM_DIR=$(mktemp -d); OUT=$(mktemp); trap 'rm -rf "$SHIM_DIR" "$OUT"' EXIT
cp "$SCRIPT_DIR/lib/gh-shim.sh" "$SHIM_DIR/gh"; chmod +x "$SHIM_DIR/gh"
LOG="$SHIM_DIR/gh.log"; : > "$LOG"

PATH="$SHIM_DIR:$PATH" \
  HARNESS_CONFIG="$FIX/harness-config.sample.json" \
  GH_SHIM_CALL_LOG="$LOG" \
  GH_SHIM_FIXTURE="$FIX/gh-existing-issues.json" \
  "$REPO_ROOT/bin/adopt-harvest.sh" "$OUT"

grep -qF '<!-- oskr:adopt-harvest -->'              "$OUT" || { echo "FAIL: missing harvest marker" >&2; exit 1; }
grep -qF -- '- [ ] #12 Fix login redirect (open)'   "$OUT" || { echo "FAIL: open issue line missing" >&2; exit 1; }
grep -qF -- '- [ ] #8 CSV export (closed)'          "$OUT" || { echo "FAIL: closed issue line missing" >&2; exit 1; }
if grep -qF '#5' "$OUT"; then echo "FAIL: PR #5 leaked into the tasklist" >&2; exit 1; fi

echo "test_adopt_harvest: PASS"
