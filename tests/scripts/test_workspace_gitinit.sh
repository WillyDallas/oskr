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
for p in projects/foo/bar .env secrets/x .DS_Store foo.env x.key y.pem hjarne/raw/x.md; do
  git -C "$WS1" check-ignore -q "$p" \
    || { echo "FAIL: expected '$p' to be gitignored" >&2; exit 1; }
done
# Tracked set — paths that must NOT be ignored (check-ignore exits non-zero).
for p in .oskr/config.json hjarne/schema.md hjarne/wiki/x.md memory/p/MEMORY.md; do
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

# ============================ T3: rehydrate ==================================
# --- dry-run: composes the plan, touches no disk (github-shaped entry) ---
WS3="$TMPROOT/ws-rehydrate-dry"
"$SETUP" skeleton "$WS3"
jq -n '{projects: [{name:"widget", path:"projects/widget", forge:"github",
        github:{owner:"acme", repo:"widget", project_number:0}}]}' \
  > "$WS3/.oskr/registry.json"

BEFORE=$(ls -A "$WS3/projects")
DRY=$("$SETUP" rehydrate "$WS3" --dry-run)
AFTER=$(ls -A "$WS3/projects")
assert_eq "$BEFORE" "$AFTER" "dry-run leaves projects/ untouched" || exit 1
if find "$WS3/projects" -maxdepth 3 -name .git | grep -q .; then
  echo "FAIL: dry-run created a clone" >&2; exit 1
fi
grep -qF "https://github.com/acme/widget.git" <<<"$DRY" \
  || { echo "FAIL: dry-run plan missing composed clone URL" >&2; exit 1; }

# --- full clone from a LOCAL bare fixture (forgejo-shaped entry, no network) ---
WS3C="$TMPROOT/ws-rehydrate-clone"
"$SETUP" skeleton "$WS3C"
BARE="$TMPROOT/forge/acme/widget.git"
mkdir -p "$(dirname "$BARE")"
git init --bare -q "$BARE"
# base_url is the local forge root; owner/repo compose onto it -> the bare path.
jq -n --arg b "$TMPROOT/forge" \
  '{projects: [{name:"widget", path:"projects/widget", forge:"forgejo",
    forgejo:{base_url:$b, owner:"acme", repo:"widget"}}]}' \
  > "$WS3C/.oskr/registry.json"
"$SETUP" rehydrate "$WS3C"
test -d "$WS3C/projects/widget/.git" \
  || { echo "FAIL: rehydrate did not clone projects/widget/.git" >&2; exit 1; }
echo "test_workspace_gitinit T3 rehydrate: PASS"

# ============================ T4: ls-files hygiene ===========================
# Drop real secret/ephemeral files BEFORE git-init so the commit would capture
# them if the ignore contract failed — this makes the hygiene assertion a guard.
WS4="$TMPROOT/ws-hygiene"
"$SETUP" skeleton "$WS4"; OSKR_FORGE=github "$SETUP" write-config "$WS4"
echo "SECRET=1" > "$WS4/.env"
mkdir -p "$WS4/secrets"; echo tok > "$WS4/secrets/token"
mkdir -p "$WS4/projects/foo"; echo x > "$WS4/projects/foo/README"
"$SETUP" git-init "$WS4"

if git -C "$WS4" ls-files | grep -qE '(^|/)\.env$|^projects/'; then
  echo "FAIL: secret or projects/ path tracked" >&2
  git -C "$WS4" ls-files | grep -E '(^|/)\.env$|^projects/' >&2; exit 1
fi
git -C "$WS4" ls-files | grep -q '^.oskr/config.json$' \
  || { echo "FAIL: .oskr/config.json not tracked" >&2; exit 1; }
echo "test_workspace_gitinit T4 hygiene: PASS"

# ============================ T5: save =======================================
WS5="$TMPROOT/ws-save"
"$SETUP" skeleton "$WS5"; OSKR_FORGE=github "$SETUP" write-config "$WS5"
"$SETUP" git-init "$WS5"

# (a) no-op idempotency: clean tree -> exit 0 twice, HEAD unchanged on re-run
"$SETUP" save "$WS5" || { echo "FAIL: save on clean tree exited non-zero" >&2; exit 1; }
HEAD_BEFORE=$(git -C "$WS5" rev-parse HEAD)
"$SETUP" save "$WS5" || { echo "FAIL: second no-op save exited non-zero" >&2; exit 1; }
assert_eq "$HEAD_BEFORE" "$(git -C "$WS5" rev-parse HEAD)" \
  "no-op save leaves HEAD unchanged" || exit 1

# (b) registry check-in: append an entry, save, the commit carries it, tree clean
jq '.projects += [{name:"widget", path:"projects/widget", forge:"github",
    github:{owner:"acme", repo:"widget", project_number:0}}]' \
  "$WS5/.oskr/registry.json" > "$WS5/.oskr/registry.json.tmp" \
  && mv "$WS5/.oskr/registry.json.tmp" "$WS5/.oskr/registry.json"
"$SETUP" save "$WS5" -m "register widget"
git -C "$WS5" show HEAD:.oskr/registry.json | grep -qF widget \
  || { echo "FAIL: saved commit does not carry the registry entry" >&2; exit 1; }
test -z "$(git -C "$WS5" status --porcelain)" \
  || { echo "FAIL: working tree not clean after save" >&2; exit 1; }

# (c) identity: the save commit used the injected identity (ambient cleared at top)
assert_eq "oskr <oskr@squirrlylabs.local>" \
  "$(git -C "$WS5" log -1 --format='%an <%ae>')" "save commit identity" || exit 1

# (d) guard: save on a non-repo workspace dies pointing at git-init
WS5N="$TMPROOT/ws-save-norepo"
"$SETUP" skeleton "$WS5N"
if OUT=$("$SETUP" save "$WS5N" 2>&1); then
  echo "FAIL: save on a non-repo workspace succeeded" >&2; exit 1
fi
grep -qF "run git-init first" <<<"$OUT" \
  || { echo "FAIL: guard message missing 'run git-init first'" >&2; exit 1; }

# (e) push-free: no line in the verb file pairs whole-word git with whole-word push
if grep -qE '(^|[^a-z])git([^a-z].*)?[^a-z]push([^a-z]|$)' "$REPO_ROOT/bin/oskr-setup.sh"; then
  echo "FAIL: a line in bin/oskr-setup.sh pairs 'git' with 'push'" >&2; exit 1
fi
echo "test_workspace_gitinit T5 save: PASS"

# ============================ T7: rehydrate --only + present/missing ==========
WS7="$TMPROOT/ws-only"
"$SETUP" skeleton "$WS7"
for r in a b; do git init --bare -q "$TMPROOT/forge7/acme/$r.git"; done
jq -n --arg b "$TMPROOT/forge7" \
  '{projects: [
     {name:"a", path:"projects/a", forge:"forgejo", forgejo:{base_url:$b, owner:"acme", repo:"a"}},
     {name:"b", path:"projects/b", forge:"forgejo", forgejo:{base_url:$b, owner:"acme", repo:"b"}}]}' \
  > "$WS7/.oskr/registry.json"

# unknown name dies before any clone
if OUT=$("$SETUP" rehydrate "$WS7" --only b --only nope 2>&1); then
  echo "FAIL: --only with an unknown name succeeded" >&2; exit 1
fi
grep -qF "no project 'nope' in registry" <<<"$OUT" \
  || { echo "FAIL: unknown --only message missing; got: $OUT" >&2; exit 1; }
test -z "$(ls -A "$WS7/projects")" \
  || { echo "FAIL: --only validation cloned before dying" >&2; exit 1; }

# only the selected project is cloned
"$SETUP" rehydrate "$WS7" --only b
test -d "$WS7/projects/b/.git" || { echo "FAIL: --only b did not clone b" >&2; exit 1; }
test ! -e "$WS7/projects/a" || { echo "FAIL: --only b also cloned a" >&2; exit 1; }

# dry-run reports present vs missing
DRY7=$("$SETUP" rehydrate "$WS7" --dry-run)
grep -qF "rehydrate: projects/b present" <<<"$DRY7" \
  || { echo "FAIL: dry-run did not report b present; got: $DRY7" >&2; exit 1; }
grep -qF "rehydrate: would clone $TMPROOT/forge7/acme/a.git -> projects/a" <<<"$DRY7" \
  || { echo "FAIL: dry-run did not report a missing; got: $DRY7" >&2; exit 1; }
echo "test_workspace_gitinit T7 rehydrate --only: PASS"

# ============================ T8: forgejo.ssh_base clone preference ===========
WS8="$TMPROOT/ws-ssh"
"$SETUP" skeleton "$WS8"
OSKR_FORGE=forgejo OSKR_FORGEJO_BASE_URL=https://forge.test "$SETUP" write-config "$WS8"

# no ssh_base -> today's https composition
jq -n '{projects: [{name:"w", path:"projects/w", forge:"forgejo",
        forgejo:{base_url:"https://forge.test/", owner:"acme", repo:"w"}}]}' \
  > "$WS8/.oskr/registry.json"
grep -qF "would clone https://forge.test/acme/w.git -> projects/w" <<<"$("$SETUP" rehydrate "$WS8" --dry-run)" \
  || { echo "FAIL: no-ssh_base composition changed" >&2; exit 1; }

# with ssh_base: same-instance entry clones via ssh_base (https is unreachable)
git init --bare -q "$TMPROOT/ssh8/acme/w.git"
jq --arg s "$TMPROOT/ssh8/" '.forgejo.ssh_base = $s' "$WS8/.oskr/config.json" \
  > "$WS8/.oskr/config.json.tmp" && mv "$WS8/.oskr/config.json.tmp" "$WS8/.oskr/config.json"
jq '.projects += [{name:"other", path:"projects/other", forge:"forgejo",
     forgejo:{base_url:"https://elsewhere.test", owner:"acme", repo:"o"}}]' \
  "$WS8/.oskr/registry.json" > "$WS8/.oskr/registry.json.tmp" \
  && mv "$WS8/.oskr/registry.json.tmp" "$WS8/.oskr/registry.json"
DRY8=$("$SETUP" rehydrate "$WS8" --dry-run)
grep -qF "would clone https://elsewhere.test/acme/o.git -> projects/other" <<<"$DRY8" \
  || { echo "FAIL: other-instance entry did not keep https; got: $DRY8" >&2; exit 1; }
"$SETUP" rehydrate "$WS8" --only w
test -d "$WS8/projects/w/.git" || { echo "FAIL: ssh_base clone did not land" >&2; exit 1; }
echo "test_workspace_gitinit T8 ssh_base: PASS"

# ============================ T9: memory-link =================================
HOME9="$TMPROOT/home9"
WS9="$HOME9/ws"
"$SETUP" skeleton "$WS9"
git init -q "$WS9/projects/p"
mkdir -p "$WS9/projects/p/.claude"
echo '{"permissions":{"allow":["Bash(ls)"]}}' > "$WS9/projects/p/.claude/settings.json"
SRC9="$TMPROOT/old-mem"; mkdir -p "$SRC9"
echo "- index" > "$SRC9/MEMORY.md"; echo "fact" > "$SRC9/a.md"

HOME="$HOME9" "$SETUP" memory-link "$WS9" p --from "$SRC9"
test -f "$WS9/memory/p/MEMORY.md" && test -f "$WS9/memory/p/a.md" \
  || { echo "FAIL: memory-link did not copy the old memory" >&2; exit 1; }
assert_eq "~/ws/memory/p" "$(jq -r .autoMemoryDirectory "$WS9/projects/p/.claude/settings.json")" \
  "autoMemoryDirectory is ~/-relative" || exit 1
assert_eq "Bash(ls)" "$(jq -r '.permissions.allow[0]' "$WS9/projects/p/.claude/settings.json")" \
  "other settings keys preserved" || exit 1

# re-run never clobbers a non-empty target
echo "edited" > "$WS9/memory/p/a.md"
HOME="$HOME9" "$SETUP" memory-link "$WS9" p --from "$SRC9"
assert_eq "edited" "$(cat "$WS9/memory/p/a.md")" "memory-link does not clobber" || exit 1

# uncloned project dies
if OUT=$(HOME="$HOME9" "$SETUP" memory-link "$WS9" missing 2>&1); then
  echo "FAIL: memory-link on an uncloned project succeeded" >&2; exit 1
fi
grep -qF "not cloned" <<<"$OUT" || { echo "FAIL: missing 'not cloned' message" >&2; exit 1; }

# workspace outside $HOME -> absolute path; no settings.json yet -> created
WS9B="$TMPROOT/ws-abs"
"$SETUP" skeleton "$WS9B"; git init -q "$WS9B/projects/q"
HOME="$HOME9" "$SETUP" memory-link "$WS9B" q --from "$TMPROOT/does-not-exist"
assert_eq "$(cd "$WS9B" && pwd)/memory/q" \
  "$(jq -r .autoMemoryDirectory "$WS9B/projects/q/.claude/settings.json")" \
  "absolute path outside HOME" || exit 1
test -d "$WS9B/memory/q" || { echo "FAIL: memory dir not created" >&2; exit 1; }
echo "test_workspace_gitinit T9 memory-link: PASS"

# ============================ T10: pull =======================================
ORIGIN10="$TMPROOT/ws10.git"
git init --bare -q "$ORIGIN10"
G=(git -c user.email=t@t -c user.name=t)
"${G[@]}" clone -q "$ORIGIN10" "$TMPROOT/A10" 2>/dev/null
echo "one" > "$TMPROOT/A10/f.txt"
"${G[@]}" -C "$TMPROOT/A10" add f.txt
"${G[@]}" -C "$TMPROOT/A10" commit -qm one
BR10=$(git -C "$TMPROOT/A10" symbolic-ref --short HEAD)
"${G[@]}" -C "$TMPROOT/A10" push -q origin "$BR10"
"${G[@]}" clone -q "$ORIGIN10" "$TMPROOT/B10"

# a new upstream commit arrives; an uncommitted edit in B survives (autostash)
echo "two" > "$TMPROOT/A10/g.txt"
"${G[@]}" -C "$TMPROOT/A10" add g.txt
"${G[@]}" -C "$TMPROOT/A10" commit -qm two
"${G[@]}" -C "$TMPROOT/A10" push -q origin "$BR10"
echo "local" > "$TMPROOT/B10/f.txt"
"$SETUP" pull "$TMPROOT/B10"
test -f "$TMPROOT/B10/g.txt" || { echo "FAIL: pull did not bring the upstream commit" >&2; exit 1; }
assert_eq "local" "$(cat "$TMPROOT/B10/f.txt")" "autostash kept the local edit" || exit 1

# conflicting commits -> pull dies with the rebase-stopped message
git -C "$TMPROOT/B10" checkout -q -- f.txt
echo "from-A" > "$TMPROOT/A10/f.txt"
"${G[@]}" -C "$TMPROOT/A10" commit -qam three
"${G[@]}" -C "$TMPROOT/A10" push -q origin "$BR10"
echo "from-B" > "$TMPROOT/B10/f.txt"
"${G[@]}" -C "$TMPROOT/B10" commit -qam local
if OUT=$("$SETUP" pull "$TMPROOT/B10" 2>&1); then
  echo "FAIL: conflicting pull succeeded" >&2; exit 1
fi
grep -qF "rebase stopped" <<<"$OUT" || { echo "FAIL: missing 'rebase stopped'; got: $OUT" >&2; exit 1; }

# non-repo dies pointing at git-init
if OUT=$("$SETUP" pull "$TMPROOT/ws-abs" 2>&1); then
  echo "FAIL: pull on a non-repo succeeded" >&2; exit 1
fi
grep -qF "run git-init first" <<<"$OUT" || { echo "FAIL: pull guard message missing" >&2; exit 1; }
echo "test_workspace_gitinit T10 pull: PASS"
