#!/usr/bin/env bash
# Hermetic seam test for the workspace-root CLAUDE.md provisioning (#117).
# Every case runs inside a fresh mktemp -d workspace; assertions are on real
# on-disk bytes. Pure filesystem — no forge, no network.
#
# The file is ambient blacksmith context for free-form sessions, so the tests
# assert BOTH that bootstrap stamps it with the four content points AND that a
# developer's edits survive every subsequent run (non-clobbering).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"
SETUP="$REPO_ROOT/bin/oskr-setup.sh"

TMPROOT=$(mktemp -d); trap 'rm -rf "$TMPROOT"' EXIT

# ============================ T1: bootstrap writes it ========================
WS1="$TMPROOT/squirrlylabs"
OSKR_FORGE=forgejo OSKR_FORGEJO_BASE_URL=https://forge.example "$SETUP" bootstrap "$WS1"
test -f "$WS1/CLAUDE.md" || { echo "FAIL: bootstrap wrote no CLAUDE.md" >&2; exit 1; }

# the workspace dir name is substituted; no placeholder survives
grep -qF 'squirrlylabs workspace' "$WS1/CLAUDE.md" \
  || { echo "FAIL: workspace name not substituted into CLAUDE.md" >&2; exit 1; }
if grep -qF '{{' "$WS1/CLAUDE.md"; then
  echo "FAIL: unsubstituted template placeholder left in CLAUDE.md" >&2; exit 1
fi
echo "test_workspace_claude_md T1 bootstrap: PASS"

# ============================ T2: the four content points ====================
# Each grep is one required point from #117 — the file is worthless as ambient
# context if any of them drops out of the template.
grep -qF 'sort -V | tail -1' "$WS1/CLAUDE.md" \
  || { echo "FAIL: CLAUDE.md missing the latest-version bin resolution" >&2; exit 1; }
grep -qF 'oskr-marketplace/oskr/*/bin' "$WS1/CLAUDE.md" \
  || { echo "FAIL: CLAUDE.md missing the version-keyed plugin cache path" >&2; exit 1; }
grep -qiE 'cd .*BEFORE sourcing|BEFORE sourcing' "$WS1/CLAUDE.md" \
  || { echo "FAIL: CLAUDE.md missing the cd-before-source rule" >&2; exit 1; }
grep -qF "The target couldn't be found" "$WS1/CLAUDE.md" \
  || { echo "FAIL: CLAUDE.md missing the Forgejo 404-means-auth note" >&2; exit 1; }
grep -qF '/oskr:scope' "$WS1/CLAUDE.md" \
  || { echo "FAIL: CLAUDE.md missing the pointer to the oskr skills" >&2; exit 1; }
echo "test_workspace_claude_md T2 content: PASS"

# ============================ T3: never clobbers user edits ==================
# Modify the provisioned file, then re-run the stamping verb: the bytes must be
# untouched. `skeleton` is the re-runnable verb (bootstrap's write-config arm
# refuses a configured workspace), and it is what tops up an existing workspace.
printf '%s\n' '# hand-edited by the developer' > "$WS1/CLAUDE.md"
BEFORE=$(cat "$WS1/CLAUDE.md")
"$SETUP" skeleton "$WS1"
assert_eq "$BEFORE" "$(cat "$WS1/CLAUDE.md")" "re-run leaves an edited CLAUDE.md alone" || exit 1

# an empty file counts as present too — never silently refilled
WS2="$TMPROOT/ws-empty"
mkdir -p "$WS2"; : > "$WS2/CLAUDE.md"
"$SETUP" skeleton "$WS2"
assert_eq "" "$(cat "$WS2/CLAUDE.md")" "empty CLAUDE.md is left empty" || exit 1
echo "test_workspace_claude_md T3 no-clobber: PASS"

# ============================ T4: tracked, not ignored =======================
# Ambient context is part of the reproducible control plane, so the .gitignore
# contract must not swallow it.
WS3="$TMPROOT/ws-tracked"
OSKR_FORGE=github "$SETUP" bootstrap "$WS3"
GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null "$SETUP" git-init "$WS3"
git -C "$WS3" ls-files | grep -qx 'CLAUDE.md' \
  || { echo "FAIL: workspace CLAUDE.md is not tracked after git-init" >&2; exit 1; }
echo "test_workspace_claude_md T4 tracked: PASS"
