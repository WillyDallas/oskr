#!/usr/bin/env bash
# Hermetic seam test for the disk-touching workspace verbs: git-init + rehydrate.
# Every verb runs inside a fresh mktemp -d workspace; assertions are on real
# on-disk state (git ls-files, git check-ignore, projects/<name>/.git). No forge
# and no network: git-init sets a remote but never pushes; rehydrate's full-clone
# path targets a LOCAL `git init --bare` fixture inside the tmpdir.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"
SETUP="$REPO_ROOT/bin/oskr-setup.sh"

TMPROOT=$(mktemp -d); trap 'rm -rf "$TMPROOT"' EXIT

# Clear ambient git identity + config so the INJECTED identity is what makes the
# commit succeed (proves git-init works on a bare machine). GIT_CONFIG_GLOBAL/
# SYSTEM=/dev/null removes any user.name/email; the identity env vars are unset.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL 2>/dev/null || true

# ============================ T1: .gitignore contract ========================
WS1="$TMPROOT/ws-gitignore"
"$SETUP" skeleton "$WS1"
"$SETUP" git-init "$WS1"
test -f "$WS1/.gitignore" || { echo "FAIL: git-init wrote no .gitignore" >&2; exit 1; }

# Ignored set — every path git check-ignore must classify as ignored (exit 0).
for p in projects/foo/bar .env secrets/x .DS_Store foo.env x.key y.pem; do
  git -C "$WS1" check-ignore -q "$p" \
    || { echo "FAIL: expected '$p' to be gitignored" >&2; exit 1; }
done
# Tracked set — paths that must NOT be ignored (check-ignore exits non-zero).
for p in .oskr/config.json hjarne/schema.md; do
  if git -C "$WS1" check-ignore -q "$p"; then
    echo "FAIL: '$p' must be tracked, not ignored" >&2; exit 1
  fi
done
echo "test_workspace_gitinit T1 gitignore: PASS"
