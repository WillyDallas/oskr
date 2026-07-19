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

# ============================ T2: git-init remote + commit ===================
# github default remote
WS2="$TMPROOT/ws-remote-gh"
"$SETUP" skeleton "$WS2"
OSKR_FORGE=github "$SETUP" write-config "$WS2"
"$SETUP" git-init "$WS2"
assert_eq "https://github.com/squirrlylabs/workspace.git" \
  "$(git -C "$WS2" remote get-url origin)" "github default remote" || exit 1

# forgejo default remote
WS2F="$TMPROOT/ws-remote-forgejo"
"$SETUP" skeleton "$WS2F"
OSKR_FORGE=forgejo OSKR_FORGEJO_BASE_URL=https://forge.squirrlylabs.com \
  "$SETUP" write-config "$WS2F"
"$SETUP" git-init "$WS2F"
assert_eq "https://forge.squirrlylabs.com/squirrlylabs/workspace.git" \
  "$(git -C "$WS2F" remote get-url origin)" "forgejo default remote" || exit 1

# full-URL override wins over composition
WS2O="$TMPROOT/ws-remote-override"
"$SETUP" skeleton "$WS2O"; OSKR_FORGE=github "$SETUP" write-config "$WS2O"
OSKR_WORKSPACE_REMOTE=https://example.test/x/y.git "$SETUP" git-init "$WS2O"
assert_eq "https://example.test/x/y.git" \
  "$(git -C "$WS2O" remote get-url origin)" "full-URL override" || exit 1

# initial commit landed with the INJECTED identity (ambient identity is cleared)
test -n "$(git -C "$WS2" rev-parse HEAD 2>/dev/null)" \
  || { echo "FAIL: git-init produced no initial commit" >&2; exit 1; }
assert_eq "oskr <oskr@squirrlylabs.local>" \
  "$(git -C "$WS2" log -1 --format='%an <%ae>')" "injected commit identity" || exit 1

# idempotency: two chained git-init runs both succeed, nothing-to-commit tolerated
if "$SETUP" git-init "$WS2" && "$SETUP" git-init "$WS2"; then :; else
  echo "FAIL: git-init not idempotent (non-zero on re-run)" >&2; exit 1
fi
echo "test_workspace_gitinit T2 git-init: PASS"
