#!/usr/bin/env bash
# Hermetic seam test for the hjarne brain skeleton stamp helper.
# Stamps templates/hjarne/ into a throwaway mktemp dir and asserts the FULL
# brain surface (the 6b seam-pin contract T2 inherits), then re-stamps to
# prove it is idempotent and non-clobbering (6c). No forge, no shim.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STAMP="$REPO_ROOT/bin/hjarne-skeleton.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
WS="$TMP/brain"

# --- First stamp: full surface (6b) ---
bash "$STAMP" "$WS"

test -d "$WS/projects"     || { echo "FAIL: missing dir projects" >&2; exit 1; }
test -d "$WS/wiki"         || { echo "FAIL: missing dir wiki" >&2; exit 1; }
test -d "$WS/raw"          || { echo "FAIL: missing dir raw" >&2; exit 1; }
test -d "$WS/raw/research" || { echo "FAIL: missing dir raw/research" >&2; exit 1; }
test -f "$WS/log.md"       || { echo "FAIL: missing file log.md" >&2; exit 1; }
test -f "$WS/schema.md"    || { echo "FAIL: missing file schema.md" >&2; exit 1; }
test -f "$WS/todo.md"      || { echo "FAIL: missing file todo.md" >&2; exit 1; }
test -f "$WS/README.md"    || { echo "FAIL: missing file README.md" >&2; exit 1; }
! test -e "$WS/profile"    || { echo "FAIL: profile/ must not be stamped" >&2; exit 1; }

# --- Idempotent + non-clobbering re-stamp (6c) ---
SENTINEL="hjarne-sentinel-$$"
printf '\n%s\n' "$SENTINEL" >> "$WS/log.md"
bash "$STAMP" "$WS"   # second run must exit 0
grep -qF "$SENTINEL" "$WS/log.md" \
  || { echo "FAIL: re-stamp clobbered log.md (sentinel lost)" >&2; exit 1; }

echo "test_hjarne_skeleton: PASS"
