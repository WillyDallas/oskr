---
name: oskr-setup
description: Bootstrap an oskr workspace — stand up a fresh one (skeleton, workspace CLAUDE.md, global config, credentials, git, publish), or set up a new machine joining an existing workspace (sync, pick projects to clone over ssh, wire project memory). Run from inside the workspace directory.
argument-hint: "(no arguments — interactive)"
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/bin/oskr-setup.sh"*) Bash(git *) Bash(mkdir *) Bash(mktemp *) Bash(jq *) Bash(cat *) Bash(echo *) Bash(test *) Bash(command -v *) Bash(gh auth*) Bash(source "${CLAUDE_PLUGIN_ROOT}/bin/*.sh") Read Write Edit
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

**Guard:** if `$ALREADY = yes`, this directory is **already** an oskr workspace — setup
never clobbers it. Ask: "Is this a **new machine** joining this workspace (you just
cloned it)? I can set up this machine: clone the projects you pick and wire memory."
- **Yes** → skip Phases 1–6 and run **Join: set up this machine** (below).
- **No** → stop: "Re-running setup will not clobber it. To reconfigure, edit
  `.oskr/config.json` by hand or remove it first." Do not proceed.

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

**Reconstructing on a new machine:** clone the workspace repo, then run this skill
from inside it — the Phase 0 guard routes to **Join: set up this machine**, which
calls `rehydrate` to re-clone the projects you pick from `.oskr/registry.json`.
rehydrate is the counterpart to git-init: git-init publishes the control plane,
rehydrate rebuilds the working tree from it.

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

## Join: set up this machine

Reached only from the Phase 0 guard (the workspace repo is cloned, `.oskr/config.json`
exists). Nothing here re-creates the workspace — it syncs it, clones chosen projects,
and reports what the developer must still do by hand. One question at a time.

**J1 — Prerequisites.** Check `command -v git jq` (add `gh` only if the registry has a
`github` entry). Check `.env` by existence only — never read or write `.env`:

```bash
test -f "$WS/.env" && echo ".env present" || echo ".env missing"
```

If missing, tell the developer to create `$WS/.env` themselves with
`FORGEJO_TOKEN=<pat>` (forgejo workspaces), and recommend a separate token for this
machine with only the scopes it needs, not the site-admin one. Wait for a "done".

**J2 — Sync.** Bring the control plane up to date:

```bash
"${CLAUDE_PLUGIN_ROOT}/bin/oskr-setup.sh" pull "$WS"
```

**J3 — Clone protocol (forgejo only).** If `jq -r '.forgejo.ssh_base // ""'
"$WS/.oskr/config.json"` is empty, ask for it. Default: when
`git -C "$WS" remote get-url origin` is `ssh://…`, offer its scheme + user + host +
port (e.g. `ssh://git@git.squirrlylabs.xyz:2222`). Write it with jq, then
`"${CLAUDE_PLUGIN_ROOT}/bin/oskr-setup.sh" save "$WS" -m "set forgejo.ssh_base"`.
With `forgejo.ssh_base` set, rehydrate clones this instance's projects over ssh — the
machine needs an ssh key registered on the forge, not a stored https credential.

**J4 — Choose projects.** Show the plan, then ask which missing projects to clone
(by name; "all" is fine):

```bash
"${CLAUDE_PLUGIN_ROOT}/bin/oskr-setup.sh" rehydrate "$WS" --dry-run
"${CLAUDE_PLUGIN_ROOT}/bin/oskr-setup.sh" rehydrate "$WS" --only <a> --only <b>
```

On a clone failure, say which project failed and that it is usually ssh access
(key not on the forge) — then continue with the rest.

**J5 — Per project, report what is still manual.** For each cloned project:
- `.env.example` present → "copy to `.env` and fill it in yourself".
- The project's `CLAUDE.md` names its toolchain — point at it; don't install anything.
- **Memory.** Read `jq -r '.autoMemoryDirectory // ""' projects/<name>/.claude/settings.json`.
  If set, check it resolves (expand a leading `~/` to `$HOME/`) to `$WS/memory/<name>`;
  if not, warn that the workspace sits at a different path than on the machine that
  linked it, so this machine's sessions write memory elsewhere. If unset, offer
  `"${CLAUDE_PLUGIN_ROOT}/bin/oskr-setup.sh" memory-link "$WS" <name>` — it moves the
  project's auto-memory into `$WS/memory/<name>/` and sets the pointer; the developer
  then commits `projects/<name>/.claude/settings.json` in that project's repo.

**J6 — Close** with the sync habit, since memory now lives in the workspace:

> This machine is set up. Pull at the start of a session
> (`oskr-setup.sh pull "$WS"`), and `save` + push at the end — project memory
> lives in the workspace repo, so unsynced machines drift and can conflict.

