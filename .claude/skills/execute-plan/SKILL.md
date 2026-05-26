---
name: execute-plan
description: Use when executing an approved implementation plan for an issue in the Ready column. Orchestrates the implementer/reviewer generator-evaluator loop per task, opens a PR when complete.
argument-hint: "[issue-number]"
allowed-tools: Bash(gh *) Bash(git *) Bash(./scripts/*) BashOutput KillShell Agent
---

You are executing an approved implementation plan from the project board.

## Setup

1. **Load the issue and plan**:
   - If `$ARGUMENTS` is provided, use that issue number. Otherwise ask.
   - Fetch the issue: `gh issue view <NUMBER> --json title,body,comments`
   - Find the plan comment (the one with "## Implementation Plan" and a link to `docs/plans/`)
   - Read the plan file from the linked path

2. **Resolve the base branch.** Defaults to `main`. Override via the `OSKR_BASE_BRANCH` environment variable for projects using a `development → main` two-stage flow (or any other base).

   ```bash
   BASE_BRANCH="${OSKR_BASE_BRANCH:-main}"
   ```

3. **Create the working branch** — must start on the base branch with a clean working tree. The dispatch-loop enforces this, but when running standalone, verify first. After the pre-flight passes, sync with `origin/$BASE_BRANCH` (fast-forward only) so the feature branch is created from the latest base — prevents teammate/dispatcher pushes from causing rebases later.
   ```bash
   # Pre-flight: must be on base branch with no tracked uncommitted changes
   [[ "$(git rev-parse --abbrev-ref HEAD)" == "$BASE_BRANCH" ]] || { echo "ABORT: not on $BASE_BRANCH"; exit 1; }
   git diff --quiet && git diff --cached --quiet || { echo "ABORT: uncommitted tracked changes"; exit 1; }

   # Sync with origin so the feature branch starts from the latest base
   git fetch origin "$BASE_BRANCH" --quiet 2>/dev/null || echo "[sync] fetch failed (offline?) — branching from local state"
   BEHIND=$(git rev-list --count "HEAD..origin/$BASE_BRANCH" 2>/dev/null || echo 0)
   if [[ "$BEHIND" -gt 0 ]]; then
     git merge --ff-only "origin/$BASE_BRANCH" && echo "[sync] fast-forwarded $BEHIND commit(s) from origin/$BASE_BRANCH before branching"
   fi

   git checkout -b feature/<NUMBER>-<short-slug>
   ```

4. **Move the issue to In Progress**:
   ```bash
   ITEM_ID=$(./scripts/find-item.sh <ISSUE_NUMBER>)
   ./scripts/move-issue.sh "$ITEM_ID" "In Progress"
   ```

## Execution: Generator/Evaluator Loop

For each task in the plan, sequentially:

### Step 1: Dispatch Implementer

Spawn an `implementer` subagent (with worktree isolation) for the current task:

```
Agent(
  subagent_type: "implementer",
  prompt: "HARNESS_TOKEN_MARKER role=implementer iteration=<ITER> issue=<NUMBER> kind=execution
           Implement Task N from the plan at docs/plans/<file>.md.
           Read the full plan for context, then implement ONLY Task N.
           The acceptance criteria for this task are: [paste criteria from plan].
           Branch: feature/<NUMBER>-<short-slug>
           Follow TDD: write failing test → verify fail → implement → verify pass.
           Run the project's type-check command (per CLAUDE.md) when done.",
  isolation: "worktree"
)
```

The iteration counter is in-memory in the parent skill's bash loop and resets to 1 at every task boundary. The 3-iteration maximum per task is the source of truth for the counter range.

### Step 2: Dispatch Reviewer

After the implementer reports completion, spawn a `reviewer` subagent:

```
Agent(
  subagent_type: "reviewer",
  prompt: "HARNESS_TOKEN_MARKER role=reviewer iteration=<ITER> issue=<NUMBER> kind=execution
           Review the implementation of Task N from docs/plans/<file>.md.
           Acceptance criteria to evaluate:
           [paste criteria from plan]

           1. Read the implementation changes
           2. Run the project's type-check command (per CLAUDE.md)
           3. Run any test commands from the acceptance criteria
           4. Grade each criterion: PASS / NEEDS_IMPROVEMENT / FAIL
           5. If any criterion is not PASS, provide specific feedback with file:line references"
)
```

### Step 3: Handle Review Result

- **All PASS**: Move to the next task
- **NEEDS_IMPROVEMENT or FAIL**: Pass the reviewer's feedback back to a fresh implementer subagent. Re-review after fixes. Maximum 3 iterations per task — if still failing after 3, stop and report to the user
- Log each review result for the PR summary

## Optional: E2E Foundation Gate

If `harness-config.json` has `e2e_gate.enabled: true`, run the configured gate script after all task reviews pass but before opening the PR:

```bash
GATE_ENABLED=$(jq -r '.e2e_gate.enabled // false' harness-config.json)
GATE_SCRIPT=$(jq -r '.e2e_gate.script // empty' harness-config.json)
if [[ "$GATE_ENABLED" == "true" && -n "$GATE_SCRIPT" && -x "$GATE_SCRIPT" ]]; then
  "$GATE_SCRIPT" || { echo "E2E gate failed — halting PR creation"; exit 1; }
fi
```

The gate script is project-defined. Contract: exit 0 on success, non-zero on failure. Failure halts PR creation and surfaces the script's stderr to the developer. Typical content: typecheck, integration tests, build verification, smoke E2E.

## Completion

When all tasks pass review (and the optional gate is green):

1. **Run the project's final type-check command** (per CLAUDE.md). If it fails, fix before proceeding. Do not open a PR with failing type-check.

2. **Open PR targeting the base branch**:
   ```bash
   gh pr create \
     --base "$BASE_BRANCH" \
     --title "<issue title>" \
     --body "$(cat <<'EOF'
   ## Summary
   [2-3 bullet points of what was implemented]

   ## Tasks Completed
   - [x] Task 1: [name] — PASS (N iterations)
   - [x] Task 2: [name] — PASS (N iterations)

   ## Verification
   - type-check: PASS
   - [test results summary]
   EOF
   )"
   ```

   Use `Closes #<NUMBER>` in the PR body only if your project's flow is a single PR to the production branch (the merge closes the issue and moves it to Done automatically). For two-stage `development → main` flows, use `Related: #<NUMBER>` instead — the issue closes when the second PR to `main` lands.

3. **Post summary to issue**:
   ```bash
   gh issue comment <NUMBER> --body "Implementation complete. PR #<PR_NUMBER> opened targeting \`$BASE_BRANCH\`."
   ```

4. **Move the issue to In Review**:
   ```bash
   ITEM_ID=$(./scripts/find-item.sh <ISSUE_NUMBER>)
   ./scripts/move-issue.sh "$ITEM_ID" "In Review"
   ```
   The agent does this directly rather than relying on a PR-body keyword.

5. **Return to the base branch** — hard requirement:
   ```bash
   git checkout "$BASE_BRANCH"
   ```
   Leaving the repo on the feature branch blocks the next dispatch cycle and can cause subsequent work to branch from the wrong base. Do this even if the PR was just pushed — the branch object persists on the remote; local HEAD doesn't need to stay there.

## Key Rules

- **One task at a time, sequentially.** Never run implementer subagents in parallel (file conflicts).
- **Fresh subagent per attempt.** Each implementer/reviewer invocation gets a clean context.
- **The plan is the contract.** Implement exactly what it says. If you need to deviate, stop and ask the user.
- **No completion claims without evidence.** Every PASS must have a verification command that was actually run.
- **3-iteration maximum per task.** If the review loop isn't converging, stop and surface the issue to the user rather than burning tokens.

## Playwright AC delegation

When a task's AC starts with `Run: npx playwright test`, the reviewer dispatches `playwright-tester` (see `.claude/agents/playwright-tester.md`).
