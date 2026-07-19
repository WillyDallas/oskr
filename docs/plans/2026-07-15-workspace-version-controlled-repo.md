# Workspace as a Version-Controlled Repo (git-init + rehydrate) Implementation Plan

**Goal:** Add three disk-touching verbs to `bin/oskr-setup.sh` — `git-init` (put the workspace under version control with a secrets-safe .gitignore contract, a composed `origin` remote, and an identity-injected initial commit), `rehydrate` (re-clone managed projects from `.oskr/registry.json` into `projects/`), and `save` (identity-injected checkpoint commit, never pushes) — plus confirmed-push publish/save wiring in the two skills.
**Architecture:** All verbs are pure local git + jq — they mutate the workspace filesystem/git state but touch NO forge API (no `gh`/`curl`), so they stay outside the backend seam. `git-init` sets a remote but never pushes; `save` commits but never pushes; `rehydrate --dry-run` clones nothing; the full-clone path targets a LOCAL `git init --bare` fixture. Pushing lives ONLY in the skills, behind an explicit yes: `oskr-setup` gains a final "Publish the workspace" phase (repo-create via the existing `blacksmith_repo_create` seam verb + `push -u origin`), and `init-project` saves the registry after each register path and offers a push. Mirrors the `# --- execution arms (disk-touching)` marker from `init-lib.sh:99`.
**Tech Stack:** Bash (`set -euo pipefail`), `git` CLI, `jq`, the repo's `tests/scripts/lib/assert.sh` harness, auto-discovered by `run-tests.sh`.
**Issue:** #113

**Revision (2026-07-19):** GATE 2 rejection feedback folded in — (1) a confirmed-push final step for both forges (the plan shipped a repo that never reaches a remote), (2) the registry-as-rehydration-artifact stale-registry gap (`registry.sh add` mutates `.oskr/registry.json` but nothing committed it, so a rehydrate on a new machine reconstructed a stale project set), and (3) a mixed-forge doc line. Addressed as new tasks T5 (`save` verb, TDD), T6 (oskr-setup Publish phase), T7 (init-project save-after-register). **T1–T4 are unchanged from the PASSed v1 (99/100)** except one sentence of T4's Phase 3b prose, amended by T6 (noted there).

---

## Exemptions (stated per agent contract)

- **No Playwright AC.** This issue ships shell verbs plus a shell seam test — zero UI, zero navigation/auth surface. The Playwright tier does not apply.
- **No live-forge AC.** `git-init` sets a remote but never pushes; `save` commits but never pushes; `rehydrate --dry-run` clones nothing; the full-clone path is exercised against a LOCAL `git init --bare` fixture in the tmpdir, not a network remote. Live push + live `blacksmith_repo_create` + full new-machine round-trip are deferred to a guided checklist / `bin/smoke` and dogfooded live by #91.
- **Testing tier for the revision:** `save` is the only new *runtime* surface and gets the hermetic seam tier (T5, TDD in `tests/scripts/test_workspace_gitinit.sh`). **T4, T6 and T7 SKILL.md wiring use the harness-infra substitution** (write AC → grep check → implement), not TDD red/green — they are prose doc changes with no runtime seam. Explicitly flagged in each task.
- **No `.claude/rules/` design-rule ACs** — the repo declares no such rules; per contract this class is a no-op.

## Cross-task dependencies

- **T1** — independent (creates the test file + minimal `git-init` = `git init` + .gitignore).
- **T2 → T1** — extends the same `git-init` function with remote composition + identity commit + idempotency.
- **T3** — independent of T2 (shares only the mktemp fixture style; adds the `rehydrate` verb).
- **T4 → T2, T3** — ls-files hygiene needs a committed workspace (T2) and asserts the whole suite + seam guard green after both verbs land; wires SKILL.md.
- **T5 → T2** — `save` extends the same test file and needs a git-init'd workspace (identity-injected baseline commit) as its fixture.
- **T6 → T2, T4, T5** — the Publish phase documents/relies on git-init's remote + save's checkpoint semantics; the `save` verb name is frozen by T5 (it is: `save`); T4 must land first because T6 Step 2b amends a Phase 3b sentence that only exists after T4 writes it.
- **T7 → T5** — init-project calls `oskr-setup.sh save`, so the verb must exist first. D8 prose is written only after D7's verb name is frozen.
- **T6 ⊥ T7** — independent of each other (different SKILL.md files); either order.

## Frozen external contracts (do not re-derive)

- `bin/registry.sh` entry schema: `{name, path, forge, github:{owner,repo,project_number} | forgejo:{base_url,owner,repo}}`.
- `bin/init-lib.sh:99` `# --- execution arms (disk-touching)` marker — the structural precedent to mirror.
- `bin/init-lib.sh` `init_infer_forge` — the forge/URL inverse-mapping precedent.
- `.gitignore` contract (exact): **Ignored** = `.env`, `*.env`, `*.key`, `*.pem`, `secrets/`, `projects/`, `.DS_Store`. **Tracked** = `.oskr/config.json`, `.oskr/registry.json`, `hjarne/**`, `learning/**`, `WORKSPACE.md`/`README.md`.
- Workspace-remote precedence: (1) `OSKR_WORKSPACE_REMOTE` verbatim; (2) else compose `OSKR_WORKSPACE_SLUG` (default `squirrlylabs/workspace`) onto the forge base (`github` → `https://github.com/<slug>.git`; `forgejo` → `<forgejo.base_url without trailing />/<slug>.git`). The workspace slug is DISTINCT from `config.github.owner`.
- Per-project clone URL from each registry entry's OWN coords: github → `https://github.com/<owner>/<repo>.git`; forgejo → `<base_url without trailing />/<owner>/<repo>.git`.
- Git identity injection: `git -c user.email="${OSKR_GIT_EMAIL:-oskr@squirrlylabs.local}" -c user.name="${OSKR_GIT_NAME:-oskr}" commit ...`.
- **`save` contract (D7):** `save <ws> [-m <msg>]` — identity-injected `git add -A` + commit (default message `oskr save`); no-op exit 0 (HEAD unchanged) on a clean tree; dies with `run git-init first` (via `_setup_die`) when `<ws>` is not a git repo; NEVER pushes.
- **Forge-context mechanism for publish (D9, option a — mandatory):** `_blacksmith_forge` reads only the `HARNESS_CONFIG`/`$PWD` config tiers (`bin/harness-lib.sh:113-118` via `blacksmith_config_path`, `:29-43`) and silently defaults to `github` — so the Publish phase synthesizes a minimal harness-config into a temp file (jq-derived from `.oskr/config.json`: `.forge`, `.forgejo.base_url`, `.github.owner`) and `export HARNESS_CONFIG=<tempfile>` before sourcing `harness-lib.sh` and calling `blacksmith_repo_create` (dispatcher `:176`; github arm `:938` takes owner/repo as args, reads no config; forgejo arm `:1284` reads only `.forgejo.base_url` via `_blacksmith_forgejo_curl` `:1157-1159` plus `FORGEJO_TOKEN` from env). **Zero `bin/` change.**
- **Pinned verbatim strings** (grep `-qF` AC targets — copy exactly, one line each):
  - Ask-first: `Ask before pushing — never push without a yes.`
  - Decline/staleness (in BOTH skills' decline branches): ``workspace has unpushed commits; run `git -C "$WS" push` when ready``
- **Comment-wording constraint (D7):** no line in `bin/oskr-setup.sh` may pair whole-word `git` and `push` — the push-free grep AC is `! grep -qE '(^|[^a-z])git([^a-z].*)?[^a-z]push([^a-z]|$)' bin/oskr-setup.sh`. Words like `pushes`/`pushing` are safe (the trailing letter breaks the match).

---

## Task 1: `.gitignore` contract + check-ignore matrix

**Files:**
- Create: `tests/scripts/test_workspace_gitinit.sh`
- Modify: `bin/oskr-setup.sh` (add disk-touching marker, `_oskr_setup_gitignore_body` helper, minimal `oskr_setup_git_init`, dispatcher + usage)

**Acceptance Criteria:**
- [ ] `git-init` writes `<ws>/.gitignore` — `Run: test -f "$WS/.gitignore"` → `Expected: exit 0`.
- [ ] Ignored paths classify as ignored — `Run: git -C "$WS" check-ignore -q projects/foo/bar .env secrets/x .DS_Store foo.env x.key y.pem` (each) → `Expected: exit 0`.
- [ ] Tracked paths are NOT ignored — `Run: ! git -C "$WS" check-ignore -q .oskr/config.json && ! git -C "$WS" check-ignore -q hjarne/schema.md` → `Expected: exit 0`.
- [ ] `Run: bash -n bin/oskr-setup.sh` → `Expected: exit 0`.

**Step 1: Write the failing test** — create `tests/scripts/test_workspace_gitinit.sh`:

```bash
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
```

**Step 2: Run test to verify it fails**
Run: `bash tests/scripts/test_workspace_gitinit.sh`
Expected: FAIL — `oskr-setup.sh git-init` hits the `*)` dispatcher arm and dies with `usage: oskr-setup.sh {skeleton|write-config|bootstrap} ...` (exit 1).

**Step 3: Write minimal implementation** — in `bin/oskr-setup.sh`, insert the marker + helpers between `oskr_setup_bootstrap` (ends line 60) and the dispatcher (`cmd="${1:-}"`, line 62):

```bash
# --- execution arms (disk-touching) -----------------------------------------
# The verbs above scaffold the workspace (dirs + JSON). The two below mutate git
# state and the projects/ tree: git-init puts the workspace under version control
# and sets (never pushes) the origin remote; rehydrate re-clones managed projects
# from the registry. Both stay OUTSIDE the backend seam — `git init`/`remote add`/
# `git clone` touch no forge API (no gh/curl); pushing is a manual/smoke step.

# _oskr_setup_gitignore_body — emit the exact .gitignore contract on stdout.
# Ignored: secrets + the cloned projects/ tree + OS cruft. Everything else stays
# tracked (.oskr/config.json, .oskr/registry.json, hjarne/**, learning/**, docs).
_oskr_setup_gitignore_body() {
  cat <<'GITIGNORE'
# oskr workspace .gitignore — generated by `oskr-setup.sh git-init`.
# Secrets never enter version control.
.env
*.env
*.key
*.pem
secrets/
# Managed projects are cloned, not vendored — `rehydrate` reconstructs them.
projects/
# OS cruft
.DS_Store
GITIGNORE
}

# git-init <workspace_dir> — make the workspace a git repo (idempotent) and write
# the .gitignore contract. (T2 extends this with the origin remote + an initial
# identity-injected commit.)
oskr_setup_git_init() {
  local ws="${1:-$PWD}"
  [[ -d "$ws/.oskr" ]] || _setup_die "no .oskr/ at $ws — run 'skeleton' first"
  git -C "$ws" init -q
  _oskr_setup_gitignore_body > "$ws/.gitignore"
}
```

Then extend the dispatcher case + usage string (lines 63–67):

```bash
case "$cmd" in
  skeleton)     oskr_setup_skeleton "$@" ;;
  write-config) oskr_setup_write_config "$@" ;;
  bootstrap)    oskr_setup_bootstrap "$@" ;;
  git-init)     oskr_setup_git_init "$@" ;;
  *)            _setup_die "usage: oskr-setup.sh {skeleton|write-config|bootstrap|git-init} [workspace_dir]" ;;
esac
```

**Step 4: Run test to verify it passes**
Run: `bash tests/scripts/test_workspace_gitinit.sh`
Expected: PASS (`test_workspace_gitinit T1 gitignore: PASS`).

**Step 5: Commit** — `git add bin/oskr-setup.sh tests/scripts/test_workspace_gitinit.sh && git commit -m "feat(oskr-setup): git-init writes the workspace .gitignore contract (#113)"`

---

## Task 2: `git-init` remote composition + identity commit + idempotency

**Files:**
- Modify: `bin/oskr-setup.sh` (add `_oskr_setup_workspace_remote`, extend `oskr_setup_git_init` with remote + commit)
- Modify: `tests/scripts/test_workspace_gitinit.sh` (append T2 section)

**Depends on:** T1.

**Acceptance Criteria:**
- [ ] github default remote — `Run: git -C "$WS" remote get-url origin` → `Expected: stdout == "https://github.com/squirrlylabs/workspace.git"`.
- [ ] forgejo default remote (config `forgejo.base_url=https://forge.squirrlylabs.com`) → `Expected: stdout == "https://forge.squirrlylabs.com/squirrlylabs/workspace.git"`.
- [ ] full-URL override `OSKR_WORKSPACE_REMOTE=https://example.test/x/y.git` → `Expected: stdout == "https://example.test/x/y.git"`.
- [ ] Initial commit uses the injected identity (ambient identity cleared) — `Run: git -C "$WS" log -1 --format='%an <%ae>'` → `Expected: "oskr <oskr@squirrlylabs.local>"`.
- [ ] Idempotent — `Run: oskr-setup.sh git-init "$WS" && oskr-setup.sh git-init "$WS"` → `Expected: exit 0` (both runs).

**Step 1: Write the failing test** — append to `tests/scripts/test_workspace_gitinit.sh`:

```bash
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
```

**Step 2: Run test to verify it fails**
Run: `bash tests/scripts/test_workspace_gitinit.sh`
Expected: FAIL — first at `git -C "$WS2" remote get-url origin` (no `origin` remote yet; the T1 `git-init` sets none), exit non-zero.

**Step 3: Write minimal implementation** — in `bin/oskr-setup.sh`, add the remote helper just above `oskr_setup_git_init`, then replace the `oskr_setup_git_init` body:

```bash
# _oskr_setup_workspace_remote <workspace_dir> — echo the composed origin URL per
# precedence. Pure string composition; no network. NOTE: the workspace repo slug
# (OSKR_WORKSPACE_SLUG) is DISTINCT from config.github.owner (the default owner
# for NEW PROJECTS, not the workspace repo).
_oskr_setup_workspace_remote() {
  local ws="$1" cfg forge base slug
  # 1. Full-URL escape hatch — used verbatim, before any config read.
  if [[ -n "${OSKR_WORKSPACE_REMOTE:-}" ]]; then
    printf '%s' "$OSKR_WORKSPACE_REMOTE"; return 0
  fi
  slug="${OSKR_WORKSPACE_SLUG:-squirrlylabs/workspace}"
  cfg="$ws/.oskr/config.json"
  forge="github"
  [[ -f "$cfg" ]] && forge="$(jq -r '.forge // "github"' "$cfg")"
  case "$forge" in
    forgejo)
      base="$(jq -r '.forgejo.base_url // ""' "$cfg")"
      [[ -n "$base" ]] || _setup_die "git-init: forge=forgejo but .forgejo.base_url is empty in $cfg"
      printf '%s/%s.git' "${base%/}" "$slug" ;;
    *)
      printf 'https://github.com/%s.git' "$slug" ;;
  esac
}

# git-init <workspace_dir> — make the workspace a git repo (idempotent), write the
# .gitignore contract, configure the `origin` workspace remote, and land an initial
# commit with an INJECTED identity so it works on a bare machine with no ambient
# user.email/user.name. NEVER pushes — that is a manual/smoke step.
oskr_setup_git_init() {
  local ws="${1:-$PWD}" remote
  [[ -d "$ws/.oskr" ]] || _setup_die "no .oskr/ at $ws — run 'skeleton' first"

  git -C "$ws" init -q
  _oskr_setup_gitignore_body > "$ws/.gitignore"

  remote="$(_oskr_setup_workspace_remote "$ws")"
  if git -C "$ws" remote get-url origin >/dev/null 2>&1; then
    git -C "$ws" remote set-url origin "$remote"
  else
    git -C "$ws" remote add origin "$remote"
  fi

  git -C "$ws" add -A
  git -C "$ws" \
    -c user.email="${OSKR_GIT_EMAIL:-oskr@squirrlylabs.local}" \
    -c user.name="${OSKR_GIT_NAME:-oskr}" \
    commit -q -m "chore(workspace): oskr workspace baseline" 2>/dev/null || true
}
```

**Step 4: Run test to verify it passes**
Run: `bash tests/scripts/test_workspace_gitinit.sh`
Expected: PASS (T1 + `test_workspace_gitinit T2 git-init: PASS`).

**Step 5: Commit** — `git add bin/oskr-setup.sh tests/scripts/test_workspace_gitinit.sh && git commit -m "feat(oskr-setup): git-init sets composed origin remote + identity commit (#113)"`

---

## Task 3: `rehydrate` verb — registry-driven clone + `--dry-run`

**Files:**
- Modify: `bin/oskr-setup.sh` (add `oskr_setup_rehydrate`, dispatcher entry, usage)
- Modify: `tests/scripts/test_workspace_gitinit.sh` (append T3 section)

**Independent of T2** (shares only the mktemp fixture style).

**Acceptance Criteria:**
- [ ] `--dry-run` touches no disk — `Run:` capture `ls -A "$WS/projects"` before/after → `Expected:` equal, and `Run: ! find "$WS/projects" -maxdepth 3 -name .git | grep -q .` → `Expected: exit 0`.
- [ ] `--dry-run` prints the composed clone URL — `Run: oskr-setup.sh rehydrate "$WS" --dry-run | grep -qF 'https://github.com/acme/widget.git'` → `Expected: exit 0`.
- [ ] Full clone from a LOCAL bare fixture — `Run: test -d "$WS/projects/widget/.git"` after `rehydrate` → `Expected: exit 0`.

**Step 1: Write the failing test** — append to `tests/scripts/test_workspace_gitinit.sh`:

```bash
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
```

**Step 2: Run test to verify it fails**
Run: `bash tests/scripts/test_workspace_gitinit.sh`
Expected: FAIL — `oskr-setup.sh rehydrate ...` hits the `*)` dispatcher arm and dies (exit 1).

**Step 3: Write minimal implementation** — in `bin/oskr-setup.sh`, add below `oskr_setup_git_init`:

```bash
# rehydrate <workspace_dir> [--dry-run] — reconstruct the managed-project tree by
# cloning each .oskr/registry.json entry into projects/<name>, using coords from
# THAT entry (projects may live on different forges). --dry-run prints the plan and
# touches no disk. Existing projects/<name>/.git are skipped (idempotent; never
# re-clones or overwrites). Clone URLs:
#   github  entry: https://github.com/<owner>/<repo>.git
#   forgejo entry: <base_url without trailing />/<owner>/<repo>.git
oskr_setup_rehydrate() {
  local ws="${1:-$PWD}"; [[ "$#" -gt 0 ]] && shift
  local dry_run=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) dry_run=1; shift ;;
      *) _setup_die "rehydrate: unknown flag '$1'" ;;
    esac
  done
  local reg="$ws/.oskr/registry.json"
  [[ -f "$reg" ]] || _setup_die "rehydrate: no registry at $reg — run 'skeleton' first"

  local n i=0 name forge owner repo base url dest
  n="$(jq '.projects | length' "$reg")"
  while [[ "$i" -lt "$n" ]]; do
    name="$(jq -r ".projects[$i].name" "$reg")"
    forge="$(jq -r ".projects[$i].forge // \"github\"" "$reg")"
    dest="$ws/projects/$name"
    case "$forge" in
      github)
        owner="$(jq -r ".projects[$i].github.owner" "$reg")"
        repo="$(jq -r ".projects[$i].github.repo" "$reg")"
        url="https://github.com/${owner}/${repo}.git" ;;
      forgejo)
        base="$(jq -r ".projects[$i].forgejo.base_url" "$reg")"
        owner="$(jq -r ".projects[$i].forgejo.owner" "$reg")"
        repo="$(jq -r ".projects[$i].forgejo.repo" "$reg")"
        url="${base%/}/${owner}/${repo}.git" ;;
      *) _setup_die "rehydrate: entry '$name' has unknown forge '$forge'" ;;
    esac

    if [[ "$dry_run" -eq 1 ]]; then
      printf 'rehydrate: would clone %s -> projects/%s\n' "$url" "$name"
    elif [[ -d "$dest/.git" ]]; then
      printf 'rehydrate: projects/%s already present; skipping\n' "$name"
    else
      git clone -q "$url" "$dest"
    fi
    i=$((i + 1))
  done
}
```

Then extend the dispatcher + usage:

```bash
  git-init)     oskr_setup_git_init "$@" ;;
  rehydrate)    oskr_setup_rehydrate "$@" ;;
  *)            _setup_die "usage: oskr-setup.sh {skeleton|write-config|bootstrap|git-init|rehydrate} [workspace_dir] [--dry-run]" ;;
```

**Step 4: Run test to verify it passes**
Run: `bash tests/scripts/test_workspace_gitinit.sh`
Expected: PASS (T1 + T2 + `test_workspace_gitinit T3 rehydrate: PASS`).

**Step 5: Commit** — `git add bin/oskr-setup.sh tests/scripts/test_workspace_gitinit.sh && git commit -m "feat(oskr-setup): rehydrate re-clones managed projects from the registry (#113)"`

---

## Task 4: ls-files hygiene + SKILL.md wiring + seam guard

**Files:**
- Modify: `tests/scripts/test_workspace_gitinit.sh` (append T4 hygiene section)
- Modify: `skills/oskr-setup/SKILL.md` (wire git-init + rehydrate)

**Depends on:** T2, T3.

**Note (harness-infra substitution):** the SKILL.md change is a prose doc with no runtime seam — it uses the *write AC → grep check → implement* form, not TDD red/green. The ls-files hygiene change is a real test and follows TDD.

**Acceptance Criteria:**
- [ ] No secret/ephemeral path tracked — `Run: git -C "$WS" ls-files | grep -qE '(^|/)\.env$|^projects/'` → `Expected: exit non-zero` (nothing matches).
- [ ] Workspace config IS tracked — `Run: git -C "$WS" ls-files | grep -q '^.oskr/config.json$'` → `Expected: exit 0`.
- [ ] SKILL.md wires both verbs — `Run: grep -qF 'git-init' skills/oskr-setup/SKILL.md && grep -qF 'rehydrate' skills/oskr-setup/SKILL.md` → `Expected: exit 0`.
- [ ] Seam guard stays green — `Run: bash tests/scripts/test_backend_no_inline_gh.sh` → `Expected: exit 0`.
- [ ] Whole suite green — `Run: tests/scripts/run-tests.sh` → `Expected: exit 0`.

**Step 1: Write the failing test** — append to `tests/scripts/test_workspace_gitinit.sh`:

```bash
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
```

**Step 2: Run test to verify it fails/passes**
Run: `bash tests/scripts/test_workspace_gitinit.sh`
Expected: PASS for the hygiene assertions (T2's contract already excludes these paths) — this section is a regression guard proving the contract holds against real secret files. If it FAILs, the .gitignore contract is wrong; fix T1/T2 before proceeding.

**Step 3: Write the SKILL.md wiring** — in `skills/oskr-setup/SKILL.md`, insert a new phase between the end of the Phase 3 block (line 63) and `## Phase 4` (line 65):

````markdown
## Phase 3b: Put the workspace under version control

The workspace is a git repo — its config, registry, and brain are tracked so the
control plane is reproducible; secrets and cloned `projects/` are not. Run the
seam-tested verb (idempotent; safe to re-run):

```bash
oskr-setup.sh git-init "$WS"
```

This runs `git init`, writes the `.gitignore` contract (ignores `.env`/`*.key`/
`*.pem`/`secrets/`/`projects/`; tracks `.oskr/config.json`, `.oskr/registry.json`,
`hjarne/**`, `learning/**`), sets the `origin` remote, and lands an initial commit
with an injected identity. It **never pushes** — create the remote repo and
`git push -u origin` yourself, or leave it local.

Remote URL: set `OSKR_WORKSPACE_REMOTE` for a full URL, else it composes
`OSKR_WORKSPACE_SLUG` (default `squirrlylabs/workspace`) onto the configured forge.

**Reconstructing on a new machine:** clone the workspace repo, then run
`oskr-setup.sh rehydrate "$WS"` to re-clone every managed project from
`.oskr/registry.json` into `projects/` (add `--dry-run` to preview, cloning
nothing). rehydrate is the counterpart to git-init: git-init publishes the
control plane, rehydrate rebuilds the working tree from it.
````

**Step 4: Run the full verification**
Run: `bash tests/scripts/test_workspace_gitinit.sh && bash tests/scripts/test_backend_no_inline_gh.sh && tests/scripts/run-tests.sh`
Expected: all exit 0 — new test PASSes end to end (T1–T4), the seam guard stays green (new verbs use only local `git`, no `gh`/`curl`; `bash -n` on every bin script passes), and the whole suite is green.

**Step 5: Commit** — `git add tests/scripts/test_workspace_gitinit.sh skills/oskr-setup/SKILL.md && git commit -m "test(oskr-setup): ls-files hygiene guard + wire git-init/rehydrate into SKILL.md (#113)"`

---

## Task 5: `save` verb — identity-injected checkpoint commit (TDD)

**Files:**
- Modify: `bin/oskr-setup.sh` (add `oskr_setup_save`, dispatcher entry, usage)
- Modify: `tests/scripts/test_workspace_gitinit.sh` (append T5 section)

**Depends on:** T2 (fixture is a git-init'd workspace with the identity-injected baseline commit).

**Design notes (required prose, per DoD):**
- The `git add -A` sweep is **DELIBERATE** — untracked non-secret root junk rides along with a save. That is acceptable for a control-plane repo because the `.gitignore` contract (T1) keeps secrets (`.env`/`*.key`/`*.pem`/`secrets/`) and `projects/` out; everything else in the workspace root *is* control-plane state worth checkpointing.
- **Comment-wording constraint:** AC (e) below greps `bin/oskr-setup.sh` for any single line pairing whole-word `git` with whole-word `push`. When writing comments/messages in that file, never put `git` and `push` on the same line — `pushes`/`pushing` are safe (trailing letter breaks the `push([^a-z]|$)` match). The implementation below already complies; keep any new comment lines compliant.

**Acceptance Criteria:**
- [ ] (a) No-op idempotency — `Run: oskr-setup.sh save "$WS" && H=$(git -C "$WS" rev-parse HEAD) && oskr-setup.sh save "$WS" && test "$H" = "$(git -C "$WS" rev-parse HEAD)"` → `Expected: exit 0` (both saves exit 0; HEAD identical across the second run).
- [ ] (b) Registry check-in — after jq-appending an entry named `widget` to `.oskr/registry.json` and `oskr-setup.sh save "$WS" -m "register widget"`: `Run: git -C "$WS" show HEAD:.oskr/registry.json | grep -qF widget` → `Expected: exit 0`, AND `Run: test -z "$(git -C "$WS" status --porcelain)"` → `Expected: exit 0`.
- [ ] (c) Identity — `Run: git -C "$WS" log -1 --format='%an <%ae>'` (ambient identity cleared) → `Expected: stdout == "oskr <oskr@squirrlylabs.local>"`.
- [ ] (d) Guard — `Run: oskr-setup.sh save "$WS_NOREPO" 2>&1 | grep -qF 'run git-init first'` on a skeleton-only (non-repo) workspace → `Expected: grep exit 0 and the save itself exits non-zero`.
- [ ] (e) Push-free — `Run: ! grep -qE '(^|[^a-z])git([^a-z].*)?[^a-z]push([^a-z]|$)' bin/oskr-setup.sh` → `Expected: exit 0`.
- [ ] `Run: bash -n bin/oskr-setup.sh` → `Expected: exit 0`.

**Step 1: Write the failing test** — append to `tests/scripts/test_workspace_gitinit.sh`:

```bash
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
```

**Step 2: Run test to verify it fails**
Run: `bash tests/scripts/test_workspace_gitinit.sh`
Expected: FAIL — `oskr-setup.sh save ...` hits the `*)` dispatcher arm and dies with the usage message (exit 1).

**Step 3: Write minimal implementation** — in `bin/oskr-setup.sh`, add below `oskr_setup_rehydrate`:

```bash
# save <workspace_dir> [-m <msg>] — identity-injected checkpoint commit of the
# workspace control plane (default message "oskr save"). Sweeps everything
# (add -A): the sweep is DELIBERATE — untracked non-secret root junk rides
# along, acceptable for a control-plane repo because the .gitignore contract
# keeps secrets and projects/ out. No-op (exit 0, HEAD unchanged) on a clean
# tree. Local-only: publishing is the skill's confirmed final phase.
oskr_setup_save() {
  local ws="${1:-$PWD}"; [[ "$#" -gt 0 ]] && shift
  local msg="oskr save"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -m) [[ $# -ge 2 ]] || _setup_die "save: -m requires a message"; msg="$2"; shift 2 ;;
      *)  _setup_die "save: unknown flag '$1'" ;;
    esac
  done
  git -C "$ws" rev-parse --git-dir >/dev/null 2>&1 \
    || _setup_die "save: $ws is not a git repo — run git-init first"
  git -C "$ws" add -A
  if [[ -z "$(git -C "$ws" status --porcelain)" ]]; then
    echo "save: nothing to commit"
    return 0
  fi
  git -C "$ws" \
    -c user.email="${OSKR_GIT_EMAIL:-oskr@squirrlylabs.local}" \
    -c user.name="${OSKR_GIT_NAME:-oskr}" \
    commit -q -m "$msg"
}
```

Then extend the dispatcher + usage:

```bash
  git-init)     oskr_setup_git_init "$@" ;;
  rehydrate)    oskr_setup_rehydrate "$@" ;;
  save)         oskr_setup_save "$@" ;;
  *)            _setup_die "usage: oskr-setup.sh {skeleton|write-config|bootstrap|git-init|rehydrate|save} [workspace_dir] [--dry-run|-m <msg>]" ;;
```

**Step 4: Run test to verify it passes**
Run: `bash tests/scripts/test_workspace_gitinit.sh && bash -n bin/oskr-setup.sh`
Expected: PASS (T1–T4 + `test_workspace_gitinit T5 save: PASS`); `bash -n` exit 0.

**Step 5: Commit** — `git add bin/oskr-setup.sh tests/scripts/test_workspace_gitinit.sh && git commit -m "feat(oskr-setup): save verb — identity-injected checkpoint commit, no-op on clean tree (#113)"`

---

## Task 6: oskr-setup SKILL.md — "Publish the workspace" phase + mixed-forge doc line

**Files:**
- Modify: `skills/oskr-setup/SKILL.md` (frontmatter allowed-tools; amend one Phase 3b sentence; append the Publish phase as the new last phase)

**Depends on:** T2, T4, T5 (T4 first — Step 2b amends T4's Phase 3b sentence). Independent of T7.

**Note (harness-infra substitution):** prose/frontmatter doc change with no runtime seam — uses the *write AC → grep check → implement* form, not TDD red/green. Deliberate substitution per the agent contract.

**Acceptance Criteria** (each `Run:` line → `Expected: exit 0`):
- [ ] `Run: grep -qF 'blacksmith_repo_create' skills/oskr-setup/SKILL.md`
- [ ] `Run: grep -qF 'push -u origin' skills/oskr-setup/SKILL.md`
- [ ] `Run: grep -qF 'export HARNESS_CONFIG=' skills/oskr-setup/SKILL.md`
- [ ] `Run: grep -qF '.oskr/config.json' skills/oskr-setup/SKILL.md`
- [ ] `Run: grep -qF 'Ask before pushing — never push without a yes.' skills/oskr-setup/SKILL.md`
- [ ] `Run: grep -qF 'workspace has unpushed commits; run \`git -C "$WS" push\` when ready' skills/oskr-setup/SKILL.md` (literal backticks; use single-quoted grep pattern: `grep -qF 'workspace has unpushed commits; run `git -C "$WS" push` when ready' ...`)
- [ ] `Run: grep -qF 'Bash(git *)' skills/oskr-setup/SKILL.md`
- [ ] `Run: grep -qF 'OSKR_WORKSPACE_REMOTE' skills/oskr-setup/SKILL.md`

**Step 1: Confirm the ACs fail before implementation**
Run: `grep -qF 'blacksmith_repo_create' skills/oskr-setup/SKILL.md; echo $?`
Expected: `1` (and likewise for `export HARNESS_CONFIG=`, the pinned sentences, `Bash(git *)`). (`OSKR_WORKSPACE_REMOTE` and `push -u origin` already hit via T4's Phase 3b — they guard against regression, not novelty.)

**Step 2: Implement** — three edits to `skills/oskr-setup/SKILL.md`:

**(2a) Frontmatter** — widen `allowed-tools` (line 5) to add `Bash(git *)`, `Bash(source "$CLAUDE_PLUGIN_ROOT/bin/*.sh")` (precedent: `skills/init-project/SKILL.md:5`), and `Bash(mktemp *)` (needed for the synthesized config temp file):

```
allowed-tools: Bash(oskr-setup.sh*) Bash(git *) Bash(mkdir *) Bash(mktemp *) Bash(jq *) Bash(cat *) Bash(echo *) Bash(test *) Bash(gh auth*) Bash(source "$CLAUDE_PLUGIN_ROOT/bin/*.sh") Read Write Edit
```

**(2b) Phase 3b harmonization** — replace the T4 sentence

> It **never pushes** — create the remote repo and `git push -u origin` yourself, or leave it local.

with

> It **never pushes** — publishing (repo-create + push) is the confirmed final phase below, or leave it local.

(This is the one deliberate touch to T4's output noted in the revision header.)

**(2c) Append the new final phase** after Phase 5:

````markdown
## Phase 6: Publish the workspace (confirmed push — final phase)

The workspace repo now has local commits and an `origin` remote, but nothing on
the forge. Ask before pushing — never push without a yes.

**Ask:** "Publish the workspace to `<origin URL>` now? This creates the remote
repo (private) if it doesn't exist and pushes the control plane. (yes/no)"

**On decline**, close with exactly this line and stop:

> workspace has unpushed commits; run `git -C "$WS" push` when ready

**On yes**, run the publish block. `_blacksmith_forge` reads only the
`HARNESS_CONFIG`/`$PWD` config tiers and silently defaults to `github`, so the
workspace's forge selection MUST be carried in via a synthesized minimal
harness-config — jq-derived from `.oskr/config.json`. `blacksmith_repo_create`
takes owner/repo as ARGS; from config it reads only `.forge` (dispatch) and, on
the forgejo arm, `.forgejo.base_url` (`.github.owner` rides along for shape
completeness). Forgejo also needs `FORGEJO_TOKEN` in the environment (Phase 2
put it in `$WS/.env`).

```bash
WS="${OSKR_WORKSPACE:-$PWD}"
# forgejo credentials, if any (no-op for github; gh keychain covers it)
[ -f "$WS/.env" ] && set -a && source "$WS/.env" && set +a

# Owner/repo of the WORKSPACE repo: the last two path segments of origin
# (honors OSKR_WORKSPACE_REMOTE / OSKR_WORKSPACE_SLUG, whichever composed it).
ORIGIN=$(git -C "$WS" remote get-url origin)
WS_REPO=$(basename "$ORIGIN" .git)
WS_OWNER=$(basename "$(dirname "$ORIGIN")")

# Synthesize the minimal harness-config the blacksmith dispatch reads.
PUBLISH_CFG=$(mktemp)
jq '{forge: .forge,
     github:  {owner: .github.owner},
     forgejo: {base_url: .forgejo.base_url}}' \
  "$WS/.oskr/config.json" > "$PUBLISH_CFG"
export HARNESS_CONFIG="$PUBLISH_CFG"

source "$CLAUDE_PLUGIN_ROOT/bin/harness-lib.sh"

# Create the remote repo only if origin isn't reachable yet.
if git -C "$WS" ls-remote origin >/dev/null 2>&1; then
  echo "remote repo already exists; skipping create"
else
  blacksmith_repo_create "$WS_OWNER" "$WS_REPO"   # echoes {url}
fi

BRANCH=$(git -C "$WS" symbolic-ref --short HEAD)
git -C "$WS" push -u origin "$BRANCH"
```

Confirm: `git -C "$WS" status -sb` shows the branch tracking `origin/<branch>`
with nothing to push.

**Mixed forges:** projects rehydrate from each registry entry's OWN coords, so
projects on different forges/instances coexist in one workspace. The workspace
repo itself tracks ONE remote — a workspace tracked on a different
forge/instance than `.oskr/config.json`'s forge is the `OSKR_WORKSPACE_REMOTE`
override edge case.
````

**Step 3: Run the grep checks to verify they pass**
Run:
```bash
grep -qF 'blacksmith_repo_create' skills/oskr-setup/SKILL.md \
 && grep -qF 'push -u origin' skills/oskr-setup/SKILL.md \
 && grep -qF 'export HARNESS_CONFIG=' skills/oskr-setup/SKILL.md \
 && grep -qF '.oskr/config.json' skills/oskr-setup/SKILL.md \
 && grep -qF 'Ask before pushing — never push without a yes.' skills/oskr-setup/SKILL.md \
 && grep -qF 'workspace has unpushed commits; run `git -C "$WS" push` when ready' skills/oskr-setup/SKILL.md \
 && grep -qF 'Bash(git *)' skills/oskr-setup/SKILL.md \
 && grep -qF 'OSKR_WORKSPACE_REMOTE' skills/oskr-setup/SKILL.md
```
Expected: exit 0.

**Step 4: Commit** — `git add skills/oskr-setup/SKILL.md && git commit -m "feat(oskr-setup): confirmed-push Publish phase via blacksmith_repo_create + synthesized HARNESS_CONFIG (#113)"`

---

## Task 7: init-project SKILL.md — save-after-register + push offer

**Files:**
- Modify: `skills/init-project/SKILL.md` (frontmatter allowed-tools; save + push-offer after BOTH register paths)

**Depends on:** T5 (the `save` verb must exist; its name is frozen: `save`). Independent of T6.

**Note (harness-infra substitution):** prose/frontmatter doc change with no runtime seam — uses the *write AC → grep check → implement* form, not TDD red/green. Deliberate substitution per the agent contract.

**Acceptance Criteria** (each `Run:` line → `Expected: exit 0`):
- [ ] `Run: grep -qF 'oskr-setup.sh save' skills/init-project/SKILL.md`
- [ ] `Run: grep -qF 'workspace has unpushed commits; run \`git -C "$WS" push\` when ready' skills/init-project/SKILL.md` (literal backticks, single-quoted pattern as in T6)
- [ ] `Run: grep -qF 'Bash(oskr-setup.sh' skills/init-project/SKILL.md`
- [ ] Seam guard + whole suite — `Run: bash tests/scripts/test_backend_no_inline_gh.sh && tests/scripts/run-tests.sh` → `Expected: exit 0`.

**Step 1: Confirm the ACs fail before implementation**
Run: `grep -qF 'oskr-setup.sh save' skills/init-project/SKILL.md; echo $?`
Expected: `1` (likewise for the pinned decline line and `Bash(oskr-setup.sh`).

**Step 2: Implement** — three edits to `skills/init-project/SKILL.md`:

**(2a) Frontmatter** — add `Bash(oskr-setup.sh*)` to `allowed-tools` (line 5):

```
allowed-tools: Bash(git *) Bash(jq *) Bash(mkdir *) Bash(mv *) Bash(cat *) Bash(echo *) Bash(test *) Bash(mktemp *) Bash(source "$CLAUDE_PLUGIN_ROOT/bin/*.sh") Bash(oskr-setup.sh*) Bash(registry.sh*) Bash(adopt-detect.sh*) Bash(adopt-register.sh*) Bash(adopt-harvest.sh*) Bash(adopt-reemit.sh*) Read Write Edit
```

**(2b) Register-only arm (~line 191)** — in "The 1f decision", the **Register-only** bullet currently ends with "Config (no-clobber) + registry entry; the forge is not touched. Done." Replace "Done." with:

````markdown
  Then check the new registry entry into the workspace repo and offer a push
  (skip the save with a note if the workspace is not yet a git repo — point at
  `oskr-setup`'s Phase 3b):

  ```bash
  oskr-setup.sh save "$WS" -m "register $NAME"
  ```

  Ask before pushing — never push without a yes. On yes: `git -C "$WS" push`
  (if it fails because the remote repo doesn't exist, point at `oskr-setup`'s
  Publish phase). On decline, surface exactly:

  > workspace has unpushed commits; run `git -C "$WS" push` when ready

  Done.
````

**(2c) Board-provisioning tail (~line 215)** — immediately after the code block ending in `registry.sh add ...`, insert:

````markdown
The registry is the rehydration artifact — an uncommitted entry is a project a
new machine can't reconstruct. Check it in and offer a push (same decline line
as above):

```bash
oskr-setup.sh save "$WS" -m "register $NAME"
```
````

(The push offer/decline wording is shared with 2b — state it once at 2b and reference it here; the pinned decline line itself must appear at least once in this file, which 2b guarantees.)

**Step 3: Run the grep checks + suite to verify they pass**
Run:
```bash
grep -qF 'oskr-setup.sh save' skills/init-project/SKILL.md \
 && grep -qF 'workspace has unpushed commits; run `git -C "$WS" push` when ready' skills/init-project/SKILL.md \
 && grep -qF 'Bash(oskr-setup.sh' skills/init-project/SKILL.md \
 && bash tests/scripts/test_backend_no_inline_gh.sh \
 && tests/scripts/run-tests.sh
```
Expected: exit 0 — greps hit, seam guard green (skill calls the seam-tested verb, no inline `gh`/`curl`), whole suite green.

**Step 4: Commit** — `git add skills/init-project/SKILL.md && git commit -m "feat(init-project): save registry into the workspace repo after register, offer confirmed push (#113)"`

---

## Final verification (all ACs, runnable)

- `bash tests/scripts/test_workspace_gitinit.sh` → exit 0 (T1–T5 sections)
- `bash tests/scripts/test_backend_no_inline_gh.sh` → exit 0
- `tests/scripts/run-tests.sh` → exit 0
- `bash -n bin/oskr-setup.sh` → exit 0
- `! grep -qE '(^|[^a-z])git([^a-z].*)?[^a-z]push([^a-z]|$)' bin/oskr-setup.sh` → exit 0
- `grep -qF 'git-init' skills/oskr-setup/SKILL.md && grep -qF 'rehydrate' skills/oskr-setup/SKILL.md` → exit 0
- T6 grep battery (Step 3 block above) → exit 0
- T7 grep battery (Step 3 block above) → exit 0

## Versioning note

Per CLAUDE.md, this is a **child PR within an Area** — do NOT bump `.claude-plugin/plugin.json`. The single deliberate bump happens at land-area.
