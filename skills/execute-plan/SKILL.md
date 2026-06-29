---
name: execute-plan
description: Use when executing an approved implementation plan for an issue in the Ready column. Orchestrates the implementer/reviewer generator-evaluator loop per task, opens a PR when complete.
argument-hint: "[issue-number]"
allowed-tools: Bash(gh *) Bash(git *) Bash(find-item.sh*) Bash(move-issue.sh*) Bash(base-branch.sh*) Bash(sync-development.sh*) Bash(sync-worktree.sh*) BashOutput KillShell Agent SendMessage
---

You are executing an approved implementation plan from the project board.

## Headless safety (read first)

This skill frequently runs inside a headless (`claude -p`) dispatch session, where **ending your turn terminates the process** and background tasks are killed ~5 seconds later. There is no re-invocation when background work completes — that only exists in interactive sessions. Hard rules:

- Never end your turn while work you need (tests, builds, subagents) is still running.
- Never say "I'll resume when X completes" — you won't. Wait for X in-turn with blocking tool calls.
- Never launch long-running work with `run_in_background` and then end the turn.

## Setup

1. **Load the issue and plan**:
   - If `$ARGUMENTS` is provided, use that issue number. Otherwise ask.
   - Fetch the issue: `gh issue view <NUMBER> --json title,body,comments`
   - Find the plan comment (the one with "## Implementation Plan" and a link to `docs/plans/`)
   - Read the plan file from the linked path

2. **Resolve the base branch — the task's Area branch.** Child PRs target their **Area branch** (the umbrella's recorded `area/<slug>` branch), not `main`. Resolve it with the blacksmith: it walks the task → parent umbrella → the recorded `oskr:area-branch` marker, falling back to the config base / `main` for solo / area-less tasks. `OSKR_BASE_BRANCH` still wins as an explicit override.

   ```bash
   BASE_BRANCH="${OSKR_BASE_BRANCH:-$(base-branch.sh <NUMBER>)}"
   ```

3. **Create the working branch off the Area branch** — clean tree, branched from the resolved base. Check out the resolved base first (it may already be the current Orca worktree branch, or a local-only Area branch cut off `main`).
   ```bash
   git diff --quiet && git diff --cached --quiet || { echo "ABORT: uncommitted tracked changes"; exit 1; }

   # Check out the resolved base (the Area branch).
   git checkout "$BASE_BRANCH" 2>/dev/null || { echo "ABORT: cannot check out base $BASE_BRANCH"; exit 1; }

   # Sync with origin only when the base tracks an upstream (a pushed Area branch or
   # main); skip cleanly for a local-only Area branch not yet pushed.
   if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
     sync-development.sh execute-plan || { echo "ABORT: base $BASE_BRANCH is stale and could not auto-sync"; exit 1; }
   fi

   git checkout -b feature/<NUMBER>-<short-slug>
   ```
   *(Note: `sync-development.sh` / `sync-worktree.sh` were built for a single configured base; driving them against an arbitrary Area branch is a known refinement. The `@{u}` guard keeps a local-only Area branch from aborting the run.)*

   **Resume mode** — if a branch matching `feature/<NUMBER>-*` already exists (typically because the issue carries the `dispatch-incomplete` label from a prior dispatch that died mid-run), do NOT create a new branch or restart from task 1:

   ```bash
   git checkout feature/<NUMBER>-<existing-slug>
   git log --oneline "$BASE_BRANCH"..HEAD   # what already landed
   ```

   Read the issue's `## Dispatch Incomplete` comment (if present) for where the prior run stopped, map the existing commits against the plan's task list, and continue from the first task without a corresponding commit. Re-run the project's type-check command (per CLAUDE.md) before resuming to confirm the inherited state is sound. If the branch exists but has zero commits, treat it as a fresh start on that branch.

   **Sync the worktree** — in both modes (fresh and resume), once the feature branch is checked out and before any implementation work, bring it up to date with the base:

   ```bash
   sync-worktree.sh execute-plan
   ```

   Exit 0 (`in-sync` or `merged`) — proceed. Exit 1 — stop and surface the status token to the developer; a `conflict` means the base moved in a way that needs human merging (the script aborts the merge and leaves the branch unchanged). Fresh branches normally report `in-sync`; the step matters for resume mode, where the branch's base predates the dead dispatch. See the `sync-worktree` skill for the full token table.

4. **Move the issue to In Progress**:
   ```bash
   ITEM_ID=$(find-item.sh <ISSUE_NUMBER>)
   move-issue.sh "$ITEM_ID" "In Progress"
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

### Step 2: Review via the persistent reviewer

One reviewer session reviews every task in this plan. Spawn it once — at the first task needing review — then continue it per task via `SendMessage`. This replaces a fresh-reviewer-per-task dispatch: re-reading the plan N times costs more tokens than it buys in context hygiene.

**Primitive:** when a custom subagent completes, the Agent tool result includes its agent ID; the orchestrator resumes it with the `SendMessage` tool using that ID as the `to` field, and the resumed agent retains its full conversation history. `SendMessage` requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in the consumer project's environment (e.g. `.claude/settings.local.json` env block). If it is not enabled, the **fallback** below keeps the loop correct.

**First review (and after any rotation or fallback respawn) — spawn:**

```
Agent(
  subagent_type: "reviewer",
  prompt: "HARNESS_TOKEN_MARKER role=reviewer iteration=<CHUNK> issue=<NUMBER> kind=execution
           You are the persistent reviewer for the execution of docs/plans/<file>.md (issue #<NUMBER>, branch feature/<NUMBER>-<short-slug>).
           Read the full plan now — it is your evaluation contract for every task. You will receive one review request per task as follow-up messages. Verdicts you issued for earlier tasks are intentional context; grade each request only against its own acceptance criteria.

           <first review request — same template as the SendMessage continuation below>"
)
```

Record the reviewer's agent ID from the Agent tool result. `<CHUNK>` starts at 1 and increments only on rotation or fallback respawn.

**Every subsequent review request — continue:**

```
SendMessage(
  to: "<reviewer-agent-id>",
  message: "Review Task <N> of docs/plans/<file>.md (attempt <A> of 3).
            Commits under review: <sha(s)>; diff: git diff <base-sha>..HEAD
            Implementer's completion narrative:
            <verbatim narrative>
            Acceptance criteria to evaluate:
            [paste criteria from plan]
            <playwright-tester verdict table, when the task has Playwright ACs — see Playwright AC delegation>
            Re-run the verification commands yourself (the project's type-check command + every AC test command). Grade each criterion PASS / NEEDS_IMPROVEMENT / FAIL with file:line evidence, structured per your agent definition."
)
```

Continuation messages carry NO HARNESS_TOKEN_MARKER — the spawn marker attributes the whole session (the transcript parser sums the single `agent-<id>.jsonl` to the spawn key).

**Rotation:** after 12 reviewed tasks, retire the session and spawn a fresh reviewer with the template above (increment `<CHUNK>`). This bounds reviewer context on the largest plans while typical plans (≤ 12 tasks) use exactly one session.

**Fallback:** if `SendMessage` is unavailable, errors, or the reviewer's verdict does not arrive within the current turn, treat the session as dead — spawn a fresh reviewer with the spawn template above for the remaining tasks and continue. Never end the turn waiting for an asynchronous reply (see Headless safety).

**Observability:** record reviewer-session usage in the PR body's Verification section as `reviewer sessions used: N, fallback respawns: M`. If fallback respawns track the task count, batching never engaged — call that out explicitly in the PR summary so the silent degradation to fresh-per-task review is visible rather than read as batched.

### Step 3: Handle Review Result

- **All PASS**: Move to the next task. The reviewer session stays alive for the next task's review request.
- **NEEDS_IMPROVEMENT or FAIL**: Pass the reviewer's feedback to a fresh implementer subagent (attempt <A+1>). After the fix, send the re-review to the SAME reviewer session via SendMessage. The reviewer intentionally accumulates prior verdicts and implementer narratives across retry attempts — that history is a feature (it catches regressions against its own earlier feedback), not stale state. The 3-iteration maximum per task is unchanged — if still failing after 3, stop and report to the user.
- Log each review result for the PR summary.

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
   - reviewer sessions used: N, fallback respawns: M
   - [test results summary]
   EOF
   )"
   ```

   The PR targets the **Area branch** (a non-default branch), so `Closes #<NUMBER>` will NOT auto-close the issue on merge — GitHub/Forgejo only auto-close on the *default* branch. Use `Related: #<NUMBER>`; the child **stays open through staging** and is retired later by `land-area` (#46), which opens the `Area→main` PR whose `Closes` directives close every child + the umbrella on the single human merge. *(A solo / area-less task whose base resolved to `main` instead uses `Closes #<NUMBER>` — it merges straight to the default branch.)*

3. **Post summary to issue**:
   ```bash
   gh issue comment <NUMBER> --body "Implementation complete. PR #<PR_NUMBER> opened targeting \`$BASE_BRANCH\`."
   ```

   If this was a resume run, clear the recovery label now that a PR exists (no-op if absent):
   ```bash
   gh issue edit <NUMBER> --remove-label dispatch-incomplete 2>/dev/null || true
   ```

4. **Move the issue to In Review**:
   ```bash
   ITEM_ID=$(find-item.sh <ISSUE_NUMBER>)
   move-issue.sh "$ITEM_ID" "In Review"
   ```
   The agent does this directly rather than relying on a PR-body keyword.

5. **Return to the base branch** — hard requirement:
   ```bash
   git checkout "$BASE_BRANCH"
   ```
   Leaving the repo on the feature branch blocks the next dispatch cycle and can cause subsequent work to branch from the wrong base. Do this even if the PR was just pushed — the branch object persists on the remote; local HEAD doesn't need to stay there.

## Key Rules

- **One task at a time, sequentially.** Never run implementer subagents in parallel (file conflicts).
- **Fresh implementer per attempt.** Each implementer invocation gets a clean context.
- **Persistent reviewer per plan.** One reviewer session reviews all tasks, rotated after 12 reviewed tasks and respawned on session death. Its accumulated verdict history across tasks and retries is intentional.
- **The plan is the contract.** Implement exactly what it says. If you need to deviate, stop and ask the user.
- **No completion claims without evidence.** Every PASS must have a verification command that was actually run.
- **3-iteration maximum per task.** If the review loop isn't converging, stop and surface the issue to the user rather than burning tokens.

## Playwright AC delegation

When a task's AC starts with `Run: npx playwright test`, the **orchestrator** (this skill) dispatches `playwright-tester` BEFORE sending the review request, then pastes the verdict table (`| AC | Status | Evidence |`) into that SendMessage request. The reviewer cannot dispatch subagents — its tool list has no Agent tool — it only folds the verdict table into its per-AC grading. See `agents/playwright-tester.md` for the runner contract.
