# Workspace as a Version-Controlled Repo (git-init + rehydrate) Implementation Plan

**Goal:** Add two disk-touching verbs to `bin/oskr-setup.sh` — `git-init` (put the workspace under version control with a secrets-safe .gitignore contract, a composed `origin` remote, and an identity-injected initial commit) and `rehydrate` (re-clone managed projects from `.oskr/registry.json` into `projects/`).
**Architecture:** Both verbs are pure local git + jq — they mutate the workspace filesystem/git state but touch NO forge API (no `gh`/`curl`), so they stay outside the backend seam. `git-init` sets a remote but never pushes; `rehydrate --dry-run` clones nothing; the full-clone path targets a LOCAL `git init --bare` fixture. Mirrors the `# --- execution arms (disk-touching)` marker from `init-lib.sh:99`.
**Tech Stack:** Bash (`set -euo pipefail`), `git` CLI, `jq`, the repo's `tests/scripts/lib/assert.sh` harness, auto-discovered by `run-tests.sh`.
**Issue:** #113

---

## Exemptions (stated per agent contract)

- **No Playwright AC.** This issue ships shell verbs plus a shell seam test — zero UI, zero navigation/auth surface. The Playwright tier does not apply.
- **No live-forge AC.** `git-init` sets a remote but never pushes; `rehydrate --dry-run` clones nothing; the full-clone path is exercised against a LOCAL `git init --bare` fixture in the tmpdir, not a network remote. Live Forgejo push + full new-machine round-trip are deferred to a guided checklist / `bin/smoke` and dogfooded live by #91.
- **T4 SKILL.md wiring uses the harness-infra substitution** (write AC → grep check → implement), not TDD red/green — it is a prose doc change with no runtime seam. Explicitly flagged in T4.

## Cross-task dependencies

- **T1** — independent (creates the test file + minimal `git-init` = `git init` + .gitignore).
- **T2 → T1** — extends the same `git-init` function with remote composition + identity commit + idempotency.
- **T3** — independent of T2 (shares only the mktemp fixture style; adds the `rehydrate` verb).
- **T4 → T2, T3** — ls-files hygiene needs a committed workspace (T2) and asserts the whole suite + seam guard green after both verbs land; wires SKILL.md.

## Frozen external contracts (do not re-derive)

- `bin/registry.sh` entry schema: `{name, path, forge, github:{owner,repo,project_number} | forgejo:{base_url,owner,repo}}`.
- `bin/init-lib.sh:99` `# --- execution arms (disk-touching)` marker — the structural precedent to mirror.
- `bin/init-lib.sh` `init_infer_forge` — the forge/URL inverse-mapping precedent.
- `.gitignore` contract (exact): **Ignored** = `.env`, `*.env`, `*.key`, `*.pem`, `secrets/`, `projects/`, `.DS_Store`. **Tracked** = `.oskr/config.json`, `.oskr/registry.json`, `hjarne/**`, `learning/**`, `WORKSPACE.md`/`README.md`.
- Workspace-remote precedence: (1) `OSKR_WORKSPACE_REMOTE` verbatim; (2) else compose `OSKR_WORKSPACE_SLUG` (default `squirrlylabs/workspace`) onto the forge base (`github` → `https://github.com/<slug>.git`; `forgejo` → `<forgejo.base_url without trailing />/<slug>.git`). The workspace slug is DISTINCT from `config.github.owner`.
- Per-project clone URL from each registry entry's OWN coords: github → `https://github.com/<owner>/<repo>.git`; forgejo → `<base_url without trailing />/<owner>/<repo>.git`.
- Git identity injection: `git -c user.email="${OSKR_GIT_EMAIL:-oskr@squirrlylabs.local}" -c user.name="${OSKR_GIT_NAME:-oskr}" commit ...`.

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

## Final verification (all ACs, runnable)

- `bash tests/scripts/test_workspace_gitinit.sh` → exit 0
- `bash tests/scripts/test_backend_no_inline_gh.sh` → exit 0
- `tests/scripts/run-tests.sh` → exit 0
- `bash -n bin/oskr-setup.sh` → exit 0
- `grep -qF 'git-init' skills/oskr-setup/SKILL.md && grep -qF 'rehydrate' skills/oskr-setup/SKILL.md` → exit 0

## Versioning note

Per CLAUDE.md, this is a **child PR within an Area** — do NOT bump `.claude-plugin/plugin.json`. The single deliberate bump happens at land-area.
