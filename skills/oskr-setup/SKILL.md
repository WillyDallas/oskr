---
name: oskr-setup
description: One-time interactive bootstrap for a fresh oskr workspace. Creates the workspace skeleton (.oskr/, projects/, hjarne/, learning/) via the seam-tested bin/oskr-setup.sh verb, gathers global config (backend + default base branch) into .oskr/config.json, instruct-and-verifies credentials into the workspace .env / gh keychain, delegates brain/teach setup only if those skills are present, and hands off to init for project #1. Run from inside the directory you want to become the workspace control plane.
argument-hint: "(no arguments — interactive)"
allowed-tools: Bash(oskr-setup.sh*) Bash(mkdir *) Bash(jq *) Bash(cat *) Bash(echo *) Bash(test *) Bash(gh auth*) Read Write Edit
---

You are standing up a developer's oskr **workspace** — the control plane that holds
all oskr state, runs once, and is augmented in place. Be interactive: detect what you
can, ask only what you cannot infer, surface the impact of each step before doing it.
Workspace bootstrap happens **once**; project onboarding (`init`) happens many times.

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
  oskr-setup.sh bootstrap "$WS"
```

Confirm the result: `.oskr/config.json` populated, `.oskr/registry.json` is
`{"projects": []}`, and `projects/ hjarne/ learning/` exist.

## Phase 4: Brain / teach — delegate only if present, never block

These belong to later Areas (brain #28, teach #30) and may not exist yet.

- **Brain:** **if present** (a brain-setup skill is discoverable), invoke it to populate
  `hjarne/`; otherwise leave the empty `hjarne/` skeleton and say it can be set up when
  Area #28 lands. This **never blocks** setup.
- **Teach:** same rule — **if present**, invoke the teach/learning setup for `learning/`;
  otherwise **skip cleanly**. Their absence never blocks completion.

## Phase 5: Hand off to init

Close by pointing the developer to the next step:

> Workspace ready at `$WS`. Next, run **`init`** from your project directory to onboard **project #1**.
