---
name: init
description: Interactive bootstrap for a new oskr-managed project. Creates the GitHub repo (private), provisions a Projects v2 board with oskr's 8-column / Priority+Size+Category schema, writes harness-config.json, registers the project in oskr's local registry, and optionally ingests a requirements markdown doc into seed issues. Run from inside the directory where the new consumer repo should live.
argument-hint: "(no arguments — interactive)"
allowed-tools: Bash(gh *) Bash(git *) Bash(mkdir *) Bash(touch *) Bash(jq *) Bash(cat *) Bash(echo *) Bash(test *) Bash(source "$CLAUDE_PLUGIN_ROOT/bin/*.sh") Bash(registry.sh*) Bash(find-item.sh*) Bash(move-issue.sh*) Bash(adopt-detect.sh*) Bash(adopt-register.sh*) Read Write Edit
---

You are walking the developer through bootstrapping a new oskr-managed project. This is an interactive setup — branch based on detected state, ask only what you can't infer, and surface the impact of each step before doing it.

## Phase 0: Pre-flight detection

Source the init helpers and the blacksmith (portable across the cache vs `--plugin-dir`):

```bash
source "$CLAUDE_PLUGIN_ROOT/bin/harness-lib.sh"
source "$CLAUDE_PLUGIN_ROOT/bin/init-lib.sh"

CWD=$(pwd)
DIR_NAME=$(basename "$CWD")
GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "")

IN_GIT=$([ -d .git ] || git rev-parse --git-dir >/dev/null 2>&1 && echo yes || echo no)
HAS_ORIGIN=$( [ "$IN_GIT" = yes ] && git remote get-url origin >/dev/null 2>&1 && echo yes || echo no)
HAS_CONFIG=$([ -f harness-config.json ] || [ -f .claude/harness-config.json ] && echo yes || echo no)

# Forge-existence probe (clone vs create-new). Ask owner/repo first if not yet known;
# default forge github. The probe is the blacksmith verb — never an inline gh/curl.
REMOTE_EXISTS=$(blacksmith_remote_exists "${OWNER:-$GH_USER}" "${REPO:-$DIR_NAME}" && echo yes || echo no)

MODE=$(init_detect_mode "$IN_GIT" "$HAS_ORIGIN" "$REMOTE_EXISTS" "$HAS_CONFIG")
echo "Detected mode: $MODE"
```

Report each fact on its own line, then branch on `$MODE`:

- **already-init** → Stop: "This directory is already an oskr-managed project (`harness-config.json` present). Re-init would overwrite config; delete it first if that is what you want."
- **create-new** → proceed to Phase 1 (greenfield: create repo + board).
- **clone** → the repo exists on the forge but not here; clone it, then proceed to Phase 1 to write config / verify the board.
- **adopt** → a local repo already wired to a remote; hand off to the **adopt path** (consent gate + register-only / full migration). *Adopt onboarding is built in a separate slice — do not provision over an existing board here.*

## Phase 1: Gather inputs (interactive)

Ask one question at a time. Pre-fill defaults from Phase 0 where possible.

1. **Project name** — short slug for logs and the registry. Default: `$DIR_NAME`. Ask: "Project name? (default: $DIR_NAME)"

2. **GitHub repo coordinates** — owner and repo name.
   - Owner default: `$GH_USER`
   - Repo name default: `$DIR_NAME`
   - Ask: "GitHub repo? (default: $GH_USER/$DIR_NAME)"

3. **Repo description** — one-liner for the GitHub repo. Ask: "Short description for the GitHub repo?"

4. **Tech stack** — free-form string the agents read from harness-config.json for context. Examples: "vite + react + tailwind", "next.js + supabase", "bash + gh CLI". Ask: "Tech stack (free-form, agents reference this)?"

5. **Base branch** — `main` is the default. If the developer wants a `development → main` two-stage flow, they say so here.
   - Ask: "Base branch for feature PRs? (default: main)"

6. **Requirements doc path** — optional. Ask: "Path to a markdown requirements doc to ingest as seed issues? (leave blank to skip)"

7. **Backend (forge)** — `github` (default) or `forgejo`. Ask: "Backend? github (default) or forgejo". Set `FORGE` accordingly (default `github`). For `forgejo`, also gather `BASE_URL` (e.g. `https://git.example.org`) and confirm `$FORGEJO_TOKEN` is set in the workspace `.env`.

Confirm the full input set back to the developer before proceeding:
> Setup plan:
> - Project: `<name>` at `<cwd>`
> - GitHub: `<owner>/<repo>` (private)
> - Tech stack: `<stack>`
> - Base branch: `<branch>`
> - Requirements doc: `<path or none>`
>
> Proceed? (y/N)

Wait for explicit confirmation. If no, stop.

## Phase 2: Create the GitHub repo

```bash
gh repo create "$OWNER/$REPO" \
  --private \
  --description "$DESCRIPTION"
```

(No `--add-readme` flag — we want an empty repo; the initial commit in Phase 8 ships our own files.)

If this fails (e.g., repo already exists under that owner), stop and tell the developer. Don't try to recover automatically.

## Phase 3: Initialize the local git repo

```bash
# Init if not already a git repo, otherwise verify clean state
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  git init
  git branch -m "$BASE_BRANCH"
fi

git remote add origin "https://github.com/$OWNER/$REPO.git"
```

## Phase 4: Provision the GitHub Project v2 board

This is the most fragile step. Three sub-steps: create project, add it to repo's project list, augment the Status field with oskr's 8 columns, create Priority/Size/Category custom fields.

### Step 4a: Create the project

```bash
OWNER_NODE_ID=$(gh api graphql -f query='{ viewer { id } }' --jq '.data.viewer.id')

PROJECT_RESPONSE=$(gh api graphql -f query='
  mutation($ownerId: ID!, $title: String!) {
    createProjectV2(input: { ownerId: $ownerId, title: $title }) {
      projectV2 { id number url }
    }
  }
' -f ownerId="$OWNER_NODE_ID" -f title="oskr — $NAME")

PROJECT_ID=$(echo "$PROJECT_RESPONSE" | jq -r '.data.createProjectV2.projectV2.id')
PROJECT_NUMBER=$(echo "$PROJECT_RESPONSE" | jq -r '.data.createProjectV2.projectV2.number')
PROJECT_URL=$(echo "$PROJECT_RESPONSE" | jq -r '.data.createProjectV2.projectV2.url')

echo "Project created: $PROJECT_URL (number: $PROJECT_NUMBER)"
```

### Step 4b: Link project to repo

```bash
REPO_NODE_ID=$(gh api graphql -f query='
  query($owner: String!, $repo: String!) {
    repository(owner: $owner, name: $repo) { id }
  }
' -f owner="$OWNER" -f repo="$REPO" --jq '.data.repository.id')

gh api graphql -f query='
  mutation($projectId: ID!, $repoId: ID!) {
    linkProjectV2ToRepository(input: { projectId: $projectId, repositoryId: $repoId }) {
      repository { id }
    }
  }
' -f projectId="$PROJECT_ID" -f repoId="$REPO_NODE_ID"
```

### Step 4c: Provision the Status columns (through the board-ops seam)

The default Status field has 3 options (Todo, In Progress, Done). oskr needs the 8
columns: Backlog, Scoping, Planning, Plan Approval, Ready, In Progress, In Review, Done.
Provisioning routes through the blacksmith verb so the column set has one source of truth
(no inline 9-col mutation drift — oskr#52).

```bash
source "$CLAUDE_PLUGIN_ROOT/bin/harness-lib.sh"

# Augments the existing Status field in place; falls back to a separate "Phase" field.
# Echoes the resulting status field name ("Status" or "Phase").
STATUS_FIELD_NAME=$(blacksmith_provision_status_columns "$PROJECT_ID")
echo "Status columns provisioned (field: $STATUS_FIELD_NAME)."
```

If it could neither augment Status nor create Phase, the verb exits non-zero — stop and
surface the failure; do not proceed to Phase 5.

If `STATUS_FIELD_NAME` is not `Status` (the in-place augment failed and the verb created a
separate `Phase` field), add `"status_field_name": "$STATUS_FIELD_NAME"` to the `workflow`
block of `harness-config.json` after Phase 5, so the harness resolves columns against the
right field.

### Step 4d: Create Priority, Size, Category custom fields

```bash
# Priority: P1/P2/P3
gh api graphql -f query='
  mutation($projectId: ID!) {
    createProjectV2Field(input: {
      projectId: $projectId,
      dataType: SINGLE_SELECT,
      name: "Priority",
      singleSelectOptions: [
        { name: "P1", color: RED, description: "Highest" },
        { name: "P2", color: YELLOW, description: "Medium" },
        { name: "P3", color: GREEN, description: "Lowest" }
      ]
    }) { projectV2Field { ... on ProjectV2SingleSelectField { id name } } }
  }
' -f projectId="$PROJECT_ID"

# Size: XS/S/M/L/XL
gh api graphql -f query='
  mutation($projectId: ID!) {
    createProjectV2Field(input: {
      projectId: $projectId,
      dataType: SINGLE_SELECT,
      name: "Size",
      singleSelectOptions: [
        { name: "XS", color: GREEN, description: "< 1hr" },
        { name: "S", color: BLUE, description: "1-4hr" },
        { name: "M", color: YELLOW, description: "Half day" },
        { name: "L", color: ORANGE, description: "Full day" },
        { name: "XL", color: RED, description: "Multi-day" }
      ]
    }) { projectV2Field { ... on ProjectV2SingleSelectField { id name } } }
  }
' -f projectId="$PROJECT_ID"

# Category: Feature / Bug / Chore / Spike / Docs
gh api graphql -f query='
  mutation($projectId: ID!) {
    createProjectV2Field(input: {
      projectId: $projectId,
      dataType: SINGLE_SELECT,
      name: "Category",
      singleSelectOptions: [
        { name: "Feature", color: BLUE },
        { name: "Bug", color: RED },
        { name: "Chore", color: GRAY },
        { name: "Spike", color: PURPLE },
        { name: "Docs", color: GREEN }
      ]
    }) { projectV2Field { ... on ProjectV2SingleSelectField { id name } } }
  }
' -f projectId="$PROJECT_ID"
```

## Phase 5: Write harness-config.json

Emit the config through the init writer — it stamps the `forge` discriminator and
the matching backend block. (`init-lib.sh` was sourced in Phase 0.) The writer emits the
live 8-column dispatcher set — `"actionable_columns": ["scoping", "planning", "ready"]`
(sourced from `bin/init-lib.sh`, the one place that feeds every freshly-init'd config).

```bash
if [[ "${FORGE:-github}" == "forgejo" ]]; then
  init_emit_config forgejo "$NAME" "$TECH_STACK" "$BASE_BRANCH" \
    "$BASE_URL" "$OWNER" "$REPO" > harness-config.json
else
  init_emit_config github "$NAME" "$TECH_STACK" "$BASE_BRANCH" \
    "$OWNER" "$REPO" "${PROJECT_NUMBER:-0}" > harness-config.json
fi

jq . harness-config.json > /dev/null || { echo "ABORT: malformed harness-config.json"; exit 1; }
```

For `create-new`/`clone`, `PROJECT_NUMBER` is the board number captured in Phase 4
(provisioning slice); if Phase 4 has not run yet it defaults to `0` and the
provisioning slice backfills it.

## Phase 5b: Adopt — consent gate & register-only (adopt mode only)

This phase runs ONLY in **adopt** mode (an existing local repo with a remote, classified
by mode-detection). oskr **never auto-migrates** an adopted repo — it detects whether the
repo already has a workflow and asks the developer how to proceed.

1. **Detect existing issues.** With the adopt config already emitted (forge + coords),
   probe the forge through the blacksmith:
   ```bash
   VERDICT=$(adopt-detect.sh)   # "existing <N>"  or  "empty 0"
   ```

2. **Branch on the verdict — never auto-migrate:**
   - **`empty 0`** — the repo has no existing issues. There is nothing to migrate;
     proceed without a migration prompt (register-only, or new-style provisioning if the
     developer asked for it). Do NOT prompt.
   - **`existing <N>`** — the repo already has issues/a board. **Stop and ask:**
     > This repo has N existing issues. How should oskr adopt it?
     > [1] **Register-only** — manage it without changing your board, columns, or issues
     >     (for a shared project that keeps its own structure/skills, e.g. story-spark-child).
     > [2] **Full migration** — harvest → reconcile → re-emit into oskr's Epoch/Area/Task
     >     board (#27 T7).
     > (default: 1)

3. **Register-only (choice 1)** — bring the repo under management with no board changes:
   ```bash
   EXTRA=()
   [ -n "$PROJECT_NUMBER" ] && EXTRA+=(--project-number "$PROJECT_NUMBER")
   [ -n "$BASE_URL" ]       && EXTRA+=(--base-url "$BASE_URL")
   adopt-register.sh --name "$NAME" --forge "$FORGE" \
     --owner "$OWNER" --repo "$REPO" --path "$CWD" "${EXTRA[@]}"
   ```
   This writes `harness-config.json` (if not already emitted) + a registry entry and
   touches **nothing** on the forge — the existing board is left exactly as it was.

4. **Full migration (choice 2)** — hand off to the harvest → reconcile → re-emit flow
   (#27 T7). Out of scope for the register-only path.

## Phase 6: Register in the oskr workspace registry

The registry tracks every project this oskr **workspace** manages. It lives in the
workspace at `<workspace>/.oskr/registry.json`, resolved by `registry.sh` — never in
the plugin source. (The one-time relocation of any legacy in-plugin registry is run by
`/oskr-setup` via `registry.sh migrate`, **before** any project's first `registry.sh add`.)

```bash
registry.sh add \
  --name "$NAME" \
  --path "$CWD" \
  --forge github \
  --owner "$OWNER" \
  --repo "$REPO" \
  --project-number "$PROJECT_NUMBER"

echo "Registered $NAME in the workspace registry (.oskr/registry.json)"
```

## Phase 7: Create starter CLAUDE.md and docs scaffolding

```bash
mkdir -p docs/plans docs/research docs/_local_archive

cat > CLAUDE.md <<EOF
# $NAME

## Overview
[Add a 2-3 sentence project description here.]

## Tech Stack
$TECH_STACK

## Conventions
- Base branch: \`$BASE_BRANCH\`
- Plan files: \`docs/plans/YYYY-MM-DD-<slug>.md\`
- Research files: \`docs/research/YYYY-MM-DD-<slug>.md\`
- Completed plans archived to: \`docs/_local_archive/\`

## Type-check command
[Replace with your project's actual command, e.g., \`npm run typecheck\`, \`tsc --noEmit\`, \`cargo check\`.]

## Run / test
[Replace with your project's actual commands.]
EOF

echo "Created CLAUDE.md scaffold — edit it to add project details."
```

## Phase 8: Initial commit and push

```bash
git add harness-config.json CLAUDE.md docs/
git commit -m "init oskr-managed project: $NAME"
git push -u origin "$BASE_BRANCH"
```

## Phase 9: Smoke verify (optional but recommended)

Create a throwaway issue, find it on the board, move it, then close it:

```bash
TEST_ISSUE=$(gh issue create --title "oskr smoke test (safe to close)" --body "Verifying find-item.sh and move-issue.sh against the freshly provisioned board." 2>&1 | grep -oE 'https://[^ ]+/issues/[0-9]+' | grep -oE '[0-9]+$')

echo "Created smoke issue #$TEST_ISSUE"
ITEM_ID=$(find-item.sh "$TEST_ISSUE")
[[ -n "$ITEM_ID" ]] && echo "find-item.sh OK: $ITEM_ID" || { echo "FAIL: find-item.sh returned nothing"; exit 1; }

move-issue.sh "$ITEM_ID" "Scoping" && echo "move-issue.sh OK: moved to Scoping"
gh issue close "$TEST_ISSUE" --reason "not planned"
echo "Smoke test passed. Board provisioning verified end-to-end."
```

If smoke fails, surface the exact failure to the developer. The most likely culprits: the provisioned Status field options don't match `harness-lib`'s expectations, or the verb fell back to a `Phase` field but `harness-config.json` still resolves against `Status` (set `workflow.status_field_name` to `$STATUS_FIELD_NAME`).

## Phase 9.5: Enable & verify "Auto-add to project" (manual — UI-only)

A fresh Projects v2 board ships with the "Auto-add to project" workflow OFF, and the
GitHub API cannot enable it. Seed issues will NOT land on the board until you flip it.
Instruct the developer, then verify with a probe — never assume.

1. Instruct:
   > Open `<PROJECT_URL>`, then the project's `…` menu → **Workflows** →
   > **Auto-add to project**. Enable it, set the filter to `is:issue`, target this repo
   > (`$OWNER/$REPO`), and Save. Tell me when done.

2. Verify with a probe issue, checking placement through the board-ops seam:
   ```bash
   source "$CLAUDE_PLUGIN_ROOT/bin/harness-lib.sh"
   PROBE=$(gh issue create --repo "$OWNER/$REPO" \
     --title "oskr auto-add probe (safe to close)" \
     --body "Verifying the Auto-add workflow places new issues on the board." \
     | grep -oE '[0-9]+$')
   sleep 3
   if [[ -n "$(blacksmith_find_item "$PROBE")" ]]; then
     echo "Auto-add VERIFIED: issue #$PROBE landed on the board."
   else
     echo "Auto-add NOT working: issue #$PROBE is not on the board — re-check the toggle."
   fi
   gh issue close "$PROBE" --reason "not planned" --repo "$OWNER/$REPO"
   ```

3. If verification fails, repeat step 1 until the probe lands. Only after Auto-add is
   verified may Phase 10 rely on it for seed issues. (If the developer opts to skip the
   toggle, create seed issues with `blacksmith_create_issue` in Phase 10 — it both
   creates the issue and adds it to the board — instead of relying on auto-add.)

## Phase 10: Ingest requirements doc (optional, only if path provided)

If `REQUIREMENTS_PATH` was provided in Phase 1:

1. Read the file. Summarize for the developer: "I see N sections / M apparent work items in this doc."

2. Propose a breakdown: "Here are draft issues I'd create based on the doc. For each, I'll show title + 2-3 line summary + suggested Category. Approve, edit, or skip each."

3. For each confirmed:
   ```bash
   gh issue create --title "<title>" --body "<body — include reference to source doc section>"
   ```
   And set Category via project field mutation (see field IDs captured in Phase 4d).

4. Place each issue in Backlog. With Auto-add verified in Phase 9.5, new issues land on
   the board automatically. If Auto-add was skipped, create each seed issue via
   `blacksmith_create_issue` (creates + adds to the board) rather than bare `gh issue create`.

5. After ingestion, summarize: "Created N issues. They're all in Backlog. Move any to Scoping when you want investigation to start (`gh issue edit` or use the daily-standup skill once ported)."

## Phase 11: Final summary

Print a closing block:

> Done. `$NAME` is now an oskr-managed project.
>
> - Project board: `<PROJECT_URL>`
> - Local path: `$CWD`
> - Registered in: `<workspace>/.oskr/registry.json`
> - Status field: `$STATUS_FIELD_NAME` (augmented `Status`, or `Phase` fallback)
> - Seed issues created: N
>
> Next steps:
> - Edit `CLAUDE.md` to fill in the project description and type-check command
> - Move any seed issue to Scoping when ready: `gh issue edit <N> ...` or via daily-standup (once that skill ships)
> - To run the dispatcher against this project: `cd $CWD && oskr dispatch` (not yet implemented — tracked in oskr roadmap)

## Key Rules

- One project per invocation. To init multiple, re-run.
- Never run Phases 2-9 without explicit developer confirmation in Phase 1.
- If any Phase fails partway through, stop and report what state was reached. Don't try to roll back automatically — the developer may want to inspect.
- Onboarding mode (create-new / clone / adopt / already-init) is detected in Phase 0 via `init_detect_mode`. Adopt onboarding is built in a separate slice.
