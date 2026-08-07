---
name: init-project
description: Onboard a project into the oskr workspace — create a new repo, import an existing local folder (a move), or clone one from the forge (GitHub/Forgejo). One interview gathers every input (location → backend → secrets → shape → adopt choice), then execution provisions repo, 8-column board, config, and registry through the blacksmith. Reach for it when the developer wants oskr to onboard, import, adopt, or manage a project. Run from anywhere inside the workspace.
argument-hint: "(no arguments — interactive)"
allowed-tools: Bash(git *) Bash(jq *) Bash(mkdir *) Bash(mv *) Bash(cat *) Bash(echo *) Bash(test *) Bash(mktemp *) Bash(source "${CLAUDE_PLUGIN_ROOT}/bin/*.sh") Bash("${CLAUDE_PLUGIN_ROOT}/bin/oskr-setup.sh"*) Bash("${CLAUDE_PLUGIN_ROOT}/bin/registry.sh"*) Bash("${CLAUDE_PLUGIN_ROOT}/bin/adopt-detect.sh"*) Bash("${CLAUDE_PLUGIN_ROOT}/bin/adopt-register.sh"*) Bash("${CLAUDE_PLUGIN_ROOT}/bin/adopt-harvest.sh"*) Bash("${CLAUDE_PLUGIN_ROOT}/bin/adopt-reemit.sh"*) Read Write Edit
---

You are walking the developer through onboarding ONE project into the oskr workspace.
The walkthrough is two halves with a hard gate between them:

1. **Interview** — gathers every input and runs every probe. Reads only: nothing on
   disk or on the forge is created or modified (the working config lives in a scratch
   temp file).
2. **Execution** — runs the confirmed arm.

**No input may be discovered mid-execution.** If execution turns out to need an answer
the interview didn't collect, stop and treat it as a bug in this walkthrough.

Prose asks; functions act. Every probe and every forge/disk action below goes through a
named `init-lib.sh` function or blacksmith verb — never an inline `gh`/`curl`/ad-hoc
mutation. Ask **one question per turn** and recommend a default.

## Shell preamble

Env does not persist between shells. Start EVERY bash block with:

```bash
source "${CLAUDE_PLUGIN_ROOT}/bin/harness-lib.sh"
source "${CLAUDE_PLUGIN_ROOT}/bin/init-lib.sh"
export HARNESS_CONFIG="$INTERVIEW_CFG"   # once Step 1c has created it
```

## Step 0: Preflight

```bash
WS=$(blacksmith_workspace_dir) || { echo "Not inside an oskr workspace — run oskr-setup first."; exit 1; }
INTERVIEW_CFG=$(mktemp)
```

Done when: `WS` resolved. Remember `WS` and `INTERVIEW_CFG` for every later block.

## Step 1: Interview

### 1a. Location — the opener

> Where does the project live?
> 1. **Nowhere yet** — create a new repo
> 2. **A folder on this machine** — import it into the workspace (a move)
> 3. **On the forge** — clone it into the workspace

- **[2] import** — ask for the path. It must be the repo *root* (execution re-checks via
  `init_import_local`). Read its remote: `ORIGIN=$(git -C "$SRC" remote get-url origin 2>/dev/null)`.
- **[3] clone** — accept a full clone URL, or `owner/repo` plus the forge question in 1b.

### 1b. Backend — infer and confirm, never silently assume

Pre-fill from the URL when one exists: `init_infer_forge "$URL"` →
`github` · `forgejo <base_url>` · `unknown <input>` · `none`.

- `github` → confirm it.
- `forgejo <base_url>` → confirm: "origin is `<host>` — treat as Forgejo at `<base_url>`?"
  A "no" (GitLab, Bitbucket, anything else) → **unsupported forge: stop** with
  "oskr supports GitHub and Forgejo" — zero writes have happened.
- `none`/`unknown`/new-repo arm → ask outright: GitHub or Forgejo (then base URL).
  Any other answer → the same unsupported-forge stop.

Then gather coordinates: owner (Forgejo: also the base URL if not inferred) and repo name.

### 1c. Project metadata, then the working config

Ask: project name slug (default: repo/folder name), tech stack (free-form), base branch
(default `main`). Then materialize the scratch config every probe below reads:

```bash
# github:  init_emit_config github  "$NAME" "$TECH" "$BASE_BRANCH" "$OWNER" "$REPO" 0
# forgejo: init_emit_config forgejo "$NAME" "$TECH" "$BASE_BRANCH" "$BASE_URL" "$OWNER" "$REPO"
init_emit_config ... > "$INTERVIEW_CFG"
export HARNESS_CONFIG="$INTERVIEW_CFG"
```

### 1d. Secrets gate — instruct-and-verify

```bash
LOGIN=$(blacksmith_forge_reachable)
```

On failure, instruct exactly what to supply and where — GitHub: `gh auth login`;
Forgejo: `FORGEJO_TOKEN` in `<WS>/.env` (and exported for this session) — then wait and
re-probe. Loop until green. Never echo a token value. Done when: `LOGIN` is non-empty.

### 1e. Shape gate

- **New-repo arm**: only a collision probe — `blacksmith_remote_exists "$OWNER" "$REPO"`
  succeeding means the repo already exists: stop and tell the developer to rerun and
  pick *clone*. (No board exists yet; Forgejo's deps unit is asserted at provision time.)
- **Clone arm**: `blacksmith_remote_exists` must succeed — the repo they named has to be there.
- **Import/clone (existing repos)**:
  - Forgejo: `blacksmith_deps_unit_ok` — on failure, instruct (repo Settings → Units →
    enable issue dependencies), re-probe; still off → stop. This is a hard gate.
  - `SCHEMA=$(blacksmith_board_schema_ok)` → `ok` | `none` | `mismatch: …`. **Hold the
    verdict** — it is context for 1f, not a gate: register-only keeps the board whatever
    its shape, and full migration replaces it.

### 1f. Adopt questions (import/clone arms only)

```bash
VERDICT=$("${CLAUDE_PLUGIN_ROOT}/bin/adopt-detect.sh")   # "existing <N>" | "empty 0" — reads through HARNESS_CONFIG
```

- **`existing <N>`** — ask, folding `SCHEMA` in as context when it isn't `ok`:
  > This repo has N existing issues. (Its board: `<SCHEMA>`.)
  > 1. **Register-only** — oskr manages it; board, columns, and issues stay exactly as they are
  > 2. **Full migration** — harvest → reconcile → re-emit onto a freshly provisioned 8-column board
  > (default: 1 — oskr never restructures without consent)
- **`empty 0`** — no prompt (nothing to migrate). Note: "no existing issues — I'll
  provision a fresh oskr board", and take the board-provisioning path in execution.
- Import with **no origin remote**: the forge repo doesn't exist either — this arm also
  creates it (confirmed in 1g); nothing is pushed.

### 1g. Confirm-plan gate

Echo the complete plan and wait for an explicit yes:

> Onboarding plan:
> - Arm: `<new | import | clone>` → `$WS/projects/<name>`
> - **Import moves `<src>` → `$WS/projects/<name>`** (uncommitted/unpushed state travels with it)
> - Forge: `<github | forgejo @ base_url>` as `<owner>/<repo>` (authenticated as `<login>`)
> - Base branch `<base>`, tech stack `<stack>`
> - Board: `<provision fresh 8-column | register-only, untouched | replace via full migration>`
> - Adopt: `<n/a | register-only | full migration (N issues to reconcile)>`
>
> Proceed? (y/N)

No → stop; nothing has been written. Done when: explicit yes.

## Step 2: Execution

Stop at the FIRST failure and report exactly what was created so far. Never roll back
automatically — the developer may want to inspect.

### Arm: new repo

```bash
DIR="$WS/projects/$NAME"; mkdir -p "$DIR"; cd "$DIR"
git init -b "$BASE_BRANCH"
cat "$INTERVIEW_CFG" > harness-config.json
export HARNESS_CONFIG="$DIR/harness-config.json"
blacksmith_repo_create "$OWNER" "$REPO"          # echoes {url}
git remote add origin "<https clone URL for the forge>"
```

Then the shared board-provisioning tail below, then scaffold + first push:

```bash
mkdir -p docs/plans docs/research docs/_local_archive
# Write the starter CLAUDE.md (Overview / Tech Stack / Conventions / Type-check / Run-test
# placeholders, base branch and paths filled in), then:
git add harness-config.json CLAUDE.md docs/ && git commit -m "init oskr-managed project: $NAME"
git push -u origin "$BASE_BRANCH"
```

GitHub only, after provisioning: tell the developer the board's "Auto-add to project"
workflow is OFF and UI-only (project `…` menu → Workflows → Auto-add, filter `is:issue`).
oskr's own verbs add issues to the board explicitly, so this affects only issues created
by hand.

### Arm: import

```bash
init_import_local "$SRC" "$WS/projects/$NAME"    # the confirmed MOVE; refuses an existing dest
cd "$WS/projects/$NAME"
```

Then by the 1f decision (below). Never push — unpushed state stays local. If there was
no origin remote: `blacksmith_repo_create` + `git remote add origin …` first (the 1g plan
said so), still no push.

### Arm: clone

```bash
git clone "<clone URL>" "$WS/projects/$NAME" && cd "$WS/projects/$NAME"
```

A cloned repo that already carries `harness-config.json` is already oskr-shaped:
`"${CLAUDE_PLUGIN_ROOT}/bin/registry.sh" add` only, then the summary. Otherwise proceed by the 1f decision.

### The 1f decision (import/clone)

- **Register-only**:
  ```bash
  "${CLAUDE_PLUGIN_ROOT}/bin/adopt-register.sh" --name "$NAME" --forge "$FORGE" --owner "$OWNER" --repo "$REPO" \
    --path "$PWD" [--project-number N] [--base-url URL]
  ```
  Config (no-clobber) + registry entry; the forge is not touched.

  Then check the new registry entry into the workspace repo and offer a push
  (skip the save with a note if the workspace is not yet a git repo — point at
  `oskr-setup`'s Phase 3b):

  ```bash
  "${CLAUDE_PLUGIN_ROOT}/bin/oskr-setup.sh" save "$WS" -m "register $NAME"
  ```

  Ask before pushing — never push without a yes. On yes: `git -C "$WS" push`
  (if it fails because the remote repo doesn't exist, point at `oskr-setup`'s
  Publish phase). On decline, surface exactly:

  > workspace has unpushed commits; run `git -C "$WS" push` when ready

  Done.
- **Empty (fresh board, no migration)**: `cat "$INTERVIEW_CFG" > harness-config.json`,
  re-point `HARNESS_CONFIG` at it, then the board-provisioning tail.
- **Full migration — strictly this order** (the board exists *before* anything re-emits
  onto it; the real project number closes the `project_number: 0` hole):
  1. `cat "$INTERVIEW_CFG" > harness-config.json` and re-point `HARNESS_CONFIG`.
  2. Board-provisioning tail (below).
  3. `"${CLAUDE_PLUGIN_ROOT}/bin/adopt-harvest.sh" harvest.md` — every existing issue into the reconciliation tasklist.
  4. **Reconcile — manual, by-hand guided**: walk `harvest.md` with the developer per
     `docs/adopt-reintake.md`, producing `reconciled-plan.json`. This is collaborative
     content work, not an onboarding input.
  5. `"${CLAUDE_PLUGIN_ROOT}/bin/adopt-reemit.sh" reconciled-plan.json` — Epoch milestone, umbrellas, `delivery/manual`
     tasks. The board lands dispatch-off; review before any work starts.

### Board-provisioning tail (new / empty-adopt / full-migration)

```bash
BOARD=$(blacksmith_provision_board)              # {project_number, url, status_field}
NUMBER=$(jq -r .project_number <<<"$BOARD"); STATUS_FIELD=$(jq -r .status_field <<<"$BOARD")
init_config_set_project_number harness-config.json "$NUMBER"          # github arms
# STATUS_FIELD != "Status" → record it: workflow.status_field_name in harness-config.json
"${CLAUDE_PLUGIN_ROOT}/bin/registry.sh" add --name "$NAME" --path "$PWD" --forge "$FORGE" --owner "$OWNER" --repo "$REPO" \
  [--project-number "$NUMBER"] [--base-url "$BASE_URL"]
```

The registry is the rehydration artifact — an uncommitted entry is a project a
new machine can't reconstruct. Check it in and offer a push (same decline line
as above):

```bash
"${CLAUDE_PLUGIN_ROOT}/bin/oskr-setup.sh" save "$WS" -m "register $NAME"
```

(Forgejo's `provision_board` echoes nothing today — treat empty output as
`status_field=Status`, no number to backfill.)

Then the forge-neutral smoke — done when all four verbs pass:

```bash
NUM=$(blacksmith_create_issue "oskr smoke test (safe to close)" "Verifying the freshly provisioned board." | jq -r .number)
ITEM=$(blacksmith_find_item "$NUM")
blacksmith_move_issue "$ITEM" "Scoping"
blacksmith_issue_close "$NUM"
```

## Step 3: Final summary

> Done. `<name>` is an oskr-managed project.
> - Path: `$WS/projects/<name>` · Board: `<url | untouched (register-only)>`
> - Registered in `<WS>/.oskr/registry.json` · Status field: `<Status | Phase>`
> - Next: fill in `CLAUDE.md` (description, type-check command); move an issue to
>   Scoping when you want investigation to start.

## Key Rules

- One project per invocation; re-run for the next.
- The interview writes nothing but the scratch config; execution runs only after the
  explicit 1g confirmation.
- Unsupported forge → the clear stop, with zero writes — at whatever interview point it
  surfaces.
- Import is a move: one copy of the truth, destination must not pre-exist, and the move
  was named in the confirmed plan.
