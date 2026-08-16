---
name: oskr-setup
description: One-time interactive bootstrap for a fresh oskr workspace. Creates the workspace skeleton (.oskr/, projects/, hjarne/, learning/, CLAUDE.md) via the seam-tested bin/oskr-setup.sh verb, gathers global config (backend + default base branch) into .oskr/config.json, instruct-and-verifies credentials into the workspace .env / gh keychain, delegates brain/teach setup only if those skills are present, and hands off to init-project for project #1. Run from inside the directory you want to become the workspace control plane.
argument-hint: "(no arguments — interactive)"
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/bin/oskr-setup.sh"*) Bash(git *) Bash(mkdir *) Bash(mktemp *) Bash(jq *) Bash(cat *) Bash(echo *) Bash(test *) Bash(gh auth*) Bash(source "${CLAUDE_PLUGIN_ROOT}/bin/*.sh") Read Write Edit
---

You are standing up a developer's oskr **workspace** — the control plane that holds
all oskr state, runs once, and is augmented in place. Be interactive: detect what you
can, ask only what you cannot infer, surface the impact of each step before doing it.
Workspace bootstrap happens **once**; project onboarding (`init-project`) happens many times.

## Phase 0: Pre-flight detection

```bash
WS="${OSKR_WORKSPACE:-$PWD}"
ALREADY=$([ -f "$WS/.oskr/config.json" ] && echo yes || echo no)
GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "")
```

Report in one line each: workspace dir (`$WS`), already-configured (`$ALREADY`), gh user.

**Guard:** if `$ALREADY = yes`, stop: "This directory is **already** an oskr workspace
(`$WS/.oskr/config.json` exists). Re-running setup will not clobber it. To reconfigure,
edit `.oskr/config.json` by hand or remove it first." Do not proceed.

## Phase 1: Gather global config (the only manual part)

Ask one question at a time; pre-fill defaults.

1. **Backend** — "Which forge backend? `github` (default) or `forgejo`?" → `OSKR_FORGE`.
2. **Default base branch** — "Default base branch for new projects? (default: `main`)" → `OSKR_BASE_BRANCH`.
3. If backend is `github`: **owner default** — "Default GitHub owner? (default: `$GH_USER`)" → `OSKR_GITHUB_OWNER`.
4. If backend is `forgejo`: **base URL** — "Forgejo base URL? (e.g. `https://sluice.example`)" → `OSKR_FORGEJO_BASE_URL`.

## Phase 2: Credentials — instruct and verify (never written to config)

Secrets live in the workspace `.env` / the `gh` keychain, **never** in the tracked
`.oskr/config.json`. Gather then verify presence:

- **GitHub:** run `gh auth status`. If not authenticated, instruct `gh auth login`
  (scopes: `repo`, `project`, `read:org`). Verify it returns success before continuing.
- **Forgejo:** instruct the developer to put `FORGEJO_TOKEN=<pat>` in `$WS/.env`, then
  verify: `test -n "$FORGEJO_TOKEN"` (after they `source $WS/.env`). Do not echo the token.

State plainly: credentials are **captured into `.env` / gh**, not into `.oskr/config.json`.

## Phase 3: Create the workspace (seam-tested verb)

Export the gathered values and call the bin verb — this is the seam-tested,
non-interactive core (dirs + empty registry + config in one shot):

```bash
OSKR_FORGE="$OSKR_FORGE" \
OSKR_BASE_BRANCH="${OSKR_BASE_BRANCH:-main}" \
OSKR_GITHUB_OWNER="${OSKR_GITHUB_OWNER:-}" \
OSKR_FORGEJO_BASE_URL="${OSKR_FORGEJO_BASE_URL:-}" \
  "${CLAUDE_PLUGIN_ROOT}/bin/oskr-setup.sh" bootstrap "$WS"
```

Confirm the result: `.oskr/config.json` populated, `.oskr/registry.json` is
`{"projects": []}`, `projects/ learning/` exist, and `hjarne/` is stamped
(`hjarne/schema.md` present — the verb runs `bin/hjarne-skeleton.sh`).

The verb also stamps a workspace-root `CLAUDE.md` — the ambient blacksmith
context that keeps free-form sessions (ones that never invoke an oskr skill)
off raw forge API calls. It is non-clobbering: an existing file is never
overwritten, so re-running setup preserves the developer's edits. Tell the
developer it is theirs to extend with workspace-specific conventions.

## Phase 3b: Put the workspace under version control

The workspace is a git repo — its config, registry, and brain are tracked so the
control plane is reproducible; secrets and cloned `projects/` are not. Run the
seam-tested verb (idempotent; safe to re-run):

```bash
"${CLAUDE_PLUGIN_ROOT}/bin/oskr-setup.sh" git-init "$WS"
```

This runs `git init`, writes the `.gitignore` contract (ignores `.env`/`*.key`/
`*.pem`/`secrets/`/`projects/`; tracks `.oskr/config.json`, `.oskr/registry.json`,
`hjarne/**`, `learning/**`), sets the `origin` remote, and lands an initial commit
with an injected identity. It **never pushes** — publishing (repo-create + push)
is the confirmed final phase below, or leave it local.

Remote URL: set `OSKR_WORKSPACE_REMOTE` for a full URL, else it composes
`OSKR_WORKSPACE_SLUG` (default `squirrlylabs/workspace`) onto the configured forge.

**Reconstructing on a new machine:** clone the workspace repo, then run
`"${CLAUDE_PLUGIN_ROOT}/bin/oskr-setup.sh" rehydrate "$WS"` to re-clone every managed project from
`.oskr/registry.json` into `projects/` (add `--dry-run` to preview, cloning
nothing). rehydrate is the counterpart to git-init: git-init publishes the
control plane, rehydrate rebuilds the working tree from it.

## Phase 4: Brain / teach — delegate only if present, never block

These belong to later Areas (brain #28, teach #30) and may not exist yet.

- **Brain:** the skeleton verb already stamped `hjarne/` (Phase 3). **If present** (a
  brain-setup skill is discoverable), invoke it for any further population; otherwise the
  stamped skeleton stands on its own. This **never blocks** setup.
- **Teach:** same rule — **if present**, invoke the teach/learning setup for `learning/`;
  otherwise **skip cleanly**. Their absence never blocks completion.

## Phase 5: Hand off to init-project

Close by pointing the developer to the next step:

> Workspace ready at `$WS`. Next, run **`init-project`** (from anywhere inside the workspace) to onboard **project #1** — new repo, imported local folder, or clone.

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

source "${CLAUDE_PLUGIN_ROOT}/bin/harness-lib.sh"

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
