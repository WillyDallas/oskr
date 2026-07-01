---
name: init
description: Interactive bootstrap for a new oskr-managed project. Creates the GitHub repo (private), provisions a Projects v2 board with oskr's 9-column / Priority+Size+Category schema, writes harness-config.json, registers the project in oskr's local registry, and optionally ingests a requirements markdown doc into seed issues. Run from inside the directory where the new consumer repo should live.
argument-hint: "(no arguments — interactive)"
allowed-tools: Bash(gh *) Bash(git *) Bash(mkdir *) Bash(touch *) Bash(jq *) Bash(cat *) Bash(echo *) Bash(test *) Bash(registry.sh*) Bash(find-item.sh*) Bash(move-issue.sh*) Read Write Edit
---

You are walking the developer through bootstrapping a new oskr-managed project. This is an interactive setup — branch based on detected state, ask only what you can't infer, and surface the impact of each step before doing it.

## Phase 0: Pre-flight detection

Before asking any questions, gather what you can from the environment.

```bash
CWD=$(pwd)
DIR_NAME=$(basename "$CWD")
GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "")
IN_GIT=$(git rev-parse --git-dir 2>/dev/null && echo yes || echo no)
HAS_REMOTE=$([ "$IN_GIT" = "yes" ] && git remote get-url origin 2>/dev/null && echo yes || echo no)
HAS_CONFIG=$([ -f harness-config.json ] && echo yes || echo no)
```

Report what you found in one line per fact:
- CWD: `<path>`
- GH user: `<login>`
- Git repo: `<yes/no>`, remote: `<yes/no>`
- harness-config.json exists: `<yes/no>`

**Branch:**
- If `harness-config.json` exists → this project is already initialized. Stop and tell the developer: "This directory is already an oskr-managed project. Re-init would overwrite config. If that's what you want, delete harness-config.json first."
- If `IN_GIT=yes` but `HAS_REMOTE=yes` → v1 doesn't support wiring to an existing GitHub remote. Surface this: "v1 supports fresh-repo bootstrap only. Wiring to an existing repo is tracked in oskr#16. To proceed, either rename/remove the existing origin or invoke this skill in a fresh directory."
- Otherwise → proceed to Phase 1.

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

This is the most fragile step. Three sub-steps: create project, add it to repo's project list, augment the Status field with oskr's 9 columns, create Priority/Size/Category custom fields.

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

### Step 4c: Configure the Status field — try Path 1, fall back to Path 2

The default Status field has 3 options (Todo, In Progress, Done). oskr needs 9 columns: Backlog, Research, Needs Input, Planning, Approval, Ready, In Progress, In Review, Done.

**Path 1 (preferred): augment the existing Status field.** Try updating its options to the full 9-column set.

```bash
STATUS_FIELD_ID=$(gh api graphql -f query='
  query($projectId: ID!) {
    node(id: $projectId) {
      ... on ProjectV2 {
        fields(first: 50) {
          nodes {
            ... on ProjectV2SingleSelectField { id name }
          }
        }
      }
    }
  }
' -f projectId="$PROJECT_ID" --jq '.data.node.fields.nodes[] | select(.name == "Status") | .id')

# Try updateProjectV2Field with new options
STATUS_UPDATE=$(gh api graphql -f query='
  mutation($fieldId: ID!) {
    updateProjectV2Field(input: {
      fieldId: $fieldId,
      singleSelectOptions: [
        { name: "Backlog", color: GRAY, description: "Not yet planned" },
        { name: "Research", color: BLUE, description: "Investigation in progress" },
        { name: "Needs Input", color: ORANGE, description: "Waiting on developer Q&A" },
        { name: "Planning", color: PURPLE, description: "Plan being drafted" },
        { name: "Approval", color: YELLOW, description: "Waiting on developer plan review" },
        { name: "Ready", color: GREEN, description: "Plan approved, ready to execute" },
        { name: "In Progress", color: BLUE, description: "Implementation in flight" },
        { name: "In Review", color: PURPLE, description: "PR open, awaiting human merge" },
        { name: "Done", color: GREEN, description: "Shipped" }
      ]
    }) {
      projectV2Field { ... on ProjectV2SingleSelectField { id name options { name } } }
    }
  }
' -f fieldId="$STATUS_FIELD_ID" 2>&1)

if echo "$STATUS_UPDATE" | grep -q '"errors"'; then
  echo "Path 1 (augment Status) failed:"
  echo "$STATUS_UPDATE" | jq -r '.errors[]?.message // .message // .'
  STATUS_PATH_TAKEN="phase"
else
  STATUS_PATH_TAKEN="status"
  echo "Path 1 succeeded — Status field augmented with 9 columns."
fi
```

**Path 2 (fallback): create a "Phase" single-select field with the 9 columns; leave the default Status alone.**

If Path 1 failed:
```bash
if [[ "$STATUS_PATH_TAKEN" == "phase" ]]; then
  gh api graphql -f query='
    mutation($projectId: ID!) {
      createProjectV2Field(input: {
        projectId: $projectId,
        dataType: SINGLE_SELECT,
        name: "Phase",
        singleSelectOptions: [
          { name: "Backlog", color: GRAY, description: "Not yet planned" },
          { name: "Research", color: BLUE, description: "Investigation in progress" },
          { name: "Needs Input", color: ORANGE, description: "Waiting on developer Q&A" },
          { name: "Planning", color: PURPLE, description: "Plan being drafted" },
          { name: "Approval", color: YELLOW, description: "Waiting on developer plan review" },
          { name: "Ready", color: GREEN, description: "Plan approved, ready to execute" },
          { name: "In Progress", color: BLUE, description: "Implementation in flight" },
          { name: "In Review", color: PURPLE, description: "PR open, awaiting human merge" },
          { name: "Done", color: GREEN, description: "Shipped" }
        ]
      }) {
        projectV2Field { ... on ProjectV2SingleSelectField { id name } }
      }
    }
  ' -f projectId="$PROJECT_ID"
  echo "Path 2 succeeded — new 'Phase' field created. Default Status field left untouched."
  echo "harness-config.json will need workflow.status_field_name: Phase"
fi
```

Capture `STATUS_PATH_TAKEN` for later — it determines what goes in `harness-config.json`'s workflow section.

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

Build the config based on inputs and Phase 4 outcomes.

```bash
# workflow.column_names depends on Path 1 vs Path 2 — only Path 2 needs an alias for the status field name
if [[ "$STATUS_PATH_TAKEN" == "phase" ]]; then
  WORKFLOW_BLOCK='"workflow": {
    "kind": "gen-eval-9col",
    "column_names": {},
    "status_field_name": "Phase",
    "actionable_columns": ["research", "planning", "ready"]
  }'
else
  WORKFLOW_BLOCK='"workflow": {
    "kind": "gen-eval-9col",
    "column_names": {},
    "actionable_columns": ["research", "planning", "ready"]
  }'
fi

cat > harness-config.json <<EOF
{
  "name": "$NAME",
  "github": {
    "owner": "$OWNER",
    "repo": "$REPO",
    "project_number": $PROJECT_NUMBER
  },
  $WORKFLOW_BLOCK,
  "paths": {
    "plans": "docs/plans",
    "research": "docs/research",
    "plan_archive": "docs/_local_archive"
  },
  "agent_context": {
    "project_name": "$NAME",
    "tech_stack": "$TECH_STACK"
  },
  "base_branch": "$BASE_BRANCH"
}
EOF

# Validate
jq . harness-config.json > /dev/null || { echo "ABORT: malformed harness-config.json"; exit 1; }
```

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

move-issue.sh "$ITEM_ID" "Research" && echo "move-issue.sh OK: moved to Research"
gh issue close "$TEST_ISSUE" --reason "not planned"
echo "Smoke test passed. Board provisioning verified end-to-end."
```

If smoke fails, surface the exact failure to the developer. The most likely culprits: Status field options don't match `harness-lib`'s expectations (Path 1 vs Path 2 mismatch), or `harness-config.json` has a wrong field.

## Phase 10: Ingest requirements doc (optional, only if path provided)

If `REQUIREMENTS_PATH` was provided in Phase 1:

1. Read the file. Summarize for the developer: "I see N sections / M apparent work items in this doc."

2. Propose a breakdown: "Here are draft issues I'd create based on the doc. For each, I'll show title + 2-3 line summary + suggested Category. Approve, edit, or skip each."

3. For each confirmed:
   ```bash
   gh issue create --title "<title>" --body "<body — include reference to source doc section>"
   ```
   And set Category via project field mutation (see field IDs captured in Phase 4d).

4. Place each issue in Backlog (default; new issues auto-add to the linked project, so this is automatic unless you want a different starting column).

5. After ingestion, summarize: "Created N issues. They're all in Backlog. Move any to Research when you want investigation to start (`gh issue edit` or use the daily-standup skill once ported)."

## Phase 11: Final summary

Print a closing block:

> Done. `$NAME` is now an oskr-managed project.
>
> - Project board: `<PROJECT_URL>`
> - Local path: `$CWD`
> - Registered in: `<workspace>/.oskr/registry.json`
> - Status field strategy: `<Path 1 / Path 2>`
> - Seed issues created: N
>
> Next steps:
> - Edit `CLAUDE.md` to fill in the project description and type-check command
> - Move any seed issue to Research when ready: `gh issue edit <N> ...` or via daily-standup (once that skill ships)
> - To run the dispatcher against this project: `cd $CWD && oskr dispatch` (not yet implemented — tracked in oskr roadmap)

## Key Rules

- One project per invocation. To init multiple, re-run.
- Never run Phases 2-9 without explicit developer confirmation in Phase 1.
- If any Phase fails partway through, stop and report what state was reached. Don't try to roll back automatically — the developer may want to inspect.
- v1 supports fresh-repo bootstrap only. Wiring to an existing repo or board is oskr#16.
