---
name: planning-session
description: Use when producing or revising an implementation plan for an issue in the Planning column. Reads either a `## Q&A Complete` comment (from developer-input) or a `## Plan Rejected: Re-Plan` comment (from plan-review) and runs the planner→plan-reviewer loop. Does not run Q&A — `developer-input` owns that.
argument-hint: "[issue-number]"
allowed-tools: Bash(gh *) Bash(find-item.sh*) Bash(move-issue.sh*) Bash(git add docs/plans/*) Bash(git commit -m*) Bash(git status) Bash(git diff*) Bash(git rev-parse*) Agent Skill
---

You are running agent-only plan generation. A developer has already resolved any Q&A (via `developer-input`), OR rejected a prior plan with feedback (via `plan-review`). Your job is to spawn the planner/evaluator loop, post the plan, and move the issue to Approval. You do not ask clarifying questions — if you find none of the expected input comments, stop and surface the error.

## Phase 0: Input Detection

Fetch comments:
```bash
gh issue view <NUMBER> --json title,body,comments
```

Scan the most recent comments for one of these headers (most recent wins):

- `## Plan Rejected: Re-Plan` → rejection re-entry. Capture the verbatim feedback below the header. Go to **Phase 0a: Re-Plan Triage**.
- `## Plan Rejected: Re-Research` → routing error. This skill should not be running — `research-session` handles Re-Research. Surface the problem to the developer and stop.
- `## Q&A Complete` → fresh plan. Capture the Q&A block. Go to **Phase 1: Fresh Plan Generator/Evaluator Loop**.

If none of these headers are present, stop and tell the developer:
> This issue is missing the input contract (no `## Q&A Complete` or `## Plan Rejected: Re-Plan` comment was found). Run `developer-input <NUMBER>` first, or move the issue back to Needs Input.

## Phase 0a: Re-Plan Triage (DoD Validity Check)

Read the frozen DoD posted by the prior planning-session's Phase 1 Step 5 audit-trail comment. Compare the rejection feedback against the DoD:

- **DoD still valid** — feedback is about execution details (wrong task breakdown, missing step, bad anchor, unclear prose). Fast-path: skip scoping and update the existing plan file in place. See **Fast-Path Revision** below.
- **DoD invalid** — feedback reveals the contract itself is wrong (wrong deliverables, wrong testing tier, wrong scope). Re-run the full Phase 1 generator/evaluator loop from Step 1 (scoping round), incorporating the rejection feedback as additional planner context.

Present the triage decision in one sentence ("I read the feedback as X → fast-path / re-scope") before proceeding. If a developer is present they may override; if the skill is running autonomously via the dispatcher, proceed with your read.

### Fast-Path Revision

When DoD is still valid, update the existing plan file in place rather than creating a new dated file. The existing file is linked from the prior `## Implementation Plan` comment on the issue (path `docs/plans/YYYY-MM-DD-<feature>.md`).

1. Read the existing plan file.
2. Spawn the planner subagent in execution round, passing the frozen DoD, the rejection feedback, and the path of the existing plan file. Instruct it to revise the same file (not write a new dated one).
3. Spawn plan-reviewer for the execution round as usual.
4. Commit the revised plan file:
   ```bash
   BASE_BRANCH="${OSKR_BASE_BRANCH:-main}"
   [[ "$(git rev-parse --abbrev-ref HEAD)" == "$BASE_BRANCH" ]] || { echo "ABORT: not on $BASE_BRANCH"; exit 1; }
   git add docs/plans/<PLAN_FILE>
   git commit -m "revise plan for #<NUMBER> <short-slug>"
   ```
5. Post a short update comment on the issue: `## Plan Revised (fast-path)` followed by a one-line diff summary (use `git diff HEAD~1 docs/plans/<PLAN_FILE>` to summarize).
6. Move the issue back to Approval:
   ```bash
   ITEM_ID=$(find-item.sh <ISSUE_NUMBER>)
   move-issue.sh "$ITEM_ID" "Approval"
   ```
7. Skip Phase 1 and Phase 2.

## Phase 1: Fresh Plan — Generator/Evaluator Loop

The Q&A answers from the `## Q&A Complete` comment are input to a `planner` → `plan-reviewer` loop. You orchestrate; you do not write the plan yourself.

### Step 1: Spawn planner for scoping round

```
Agent(
  subagent_type: "planner",
  prompt: "HARNESS_TOKEN_MARKER role=planner iteration=<ITER> issue=<NUMBER> kind=scoping
           Scoping round for issue #<NUMBER>.
           Issue body: [issue body]
           Research findings: [paste research comment]
           Developer Q&A answers: [paste verbatim ## Q&A Complete block]

           Produce a Definition of Done checklist for the plan you will write.
           Output per the Scoping Round format in your agent definition."
)
```

### Step 2: Spawn plan-reviewer for scoping round

```
Agent(
  subagent_type: "plan-reviewer",
  prompt: "HARNESS_TOKEN_MARKER role=plan-reviewer iteration=<ITER> issue=<NUMBER> kind=scoping
           Scoping round for issue #<NUMBER>.
           Planner DoD proposal:
           [paste DoD from Step 1]

           Evaluate per the Scoping Round Review format in your agent definition."
)
```

If verdict is REVISE, loop back to Step 1 with reviewer's feedback. Max 2 iterations. After iteration 2, accept the current DoD and note unresolved disagreements in the plan header.

### Step 3: Spawn planner for execution round

```
Agent(
  subagent_type: "planner",
  prompt: "HARNESS_TOKEN_MARKER role=planner iteration=<ITER> issue=<NUMBER> kind=execution
           Execution round for issue #<NUMBER>.
           Frozen DoD:
           [paste accepted DoD]

           Research + Q&A context:
           [paste as before]

           Write the plan file to docs/plans/YYYY-MM-DD-<feature>.md per the structure in your agent definition. Use the Skill tool to invoke context7 for any library API references."
)
```

### Step 4: Spawn plan-reviewer for execution round

```
Agent(
  subagent_type: "plan-reviewer",
  prompt: "HARNESS_TOKEN_MARKER role=plan-reviewer iteration=<ITER> issue=<NUMBER> kind=execution
           Execution round for issue #<NUMBER>.
           Frozen DoD:
           [paste accepted DoD]

           Plan file: docs/plans/YYYY-MM-DD-<feature>.md

           Evaluate per the Execution Round Review format in your agent definition."
)
```

If Overall is NEEDS_IMPROVEMENT or FAIL, loop back to Step 3 with reviewer's feedback. Max 3 iterations. After iteration 3, stop and surface the unresolved issues to the developer.

### Step 5: Post DoD + review summary to issue

As an audit trail, post a comment containing the frozen DoD, iteration count for both rounds, and a one-line final verdict. This is what future fast-path runs read to assess DoD validity.

### Step 6: Commit the plan file

The plan file is now accepted. Commit it to the base branch so plan-review reads from git rather than a dirty working tree, and so subsequent dispatches aren't blocked by uncommitted changes.

```bash
# Must be on the base branch — the dispatch-loop guarantees this, but verify
BASE_BRANCH="${OSKR_BASE_BRANCH:-main}"
[[ "$(git rev-parse --abbrev-ref HEAD)" == "$BASE_BRANCH" ]] || { echo "ABORT: not on $BASE_BRANCH"; exit 1; }
git add docs/plans/<PLAN_FILE>
git commit -m "add plan for #<NUMBER> <short-slug>"
```

The allowlist restricts `git add` to paths under `docs/plans/`, so any other modified files in the working tree are left alone.

## Phase 2: Post Plan and Move to Approval

1. Post the plan summary comment:
   ```bash
   gh issue comment <NUMBER> --body "$(cat <<'COMMENT'
   ## Implementation Plan
   **Plan file**: [`docs/plans/YYYY-MM-DD-<feature>.md`](link)

   ### Summary
   - [key points from the plan]

   ### Tasks
   N tasks with M total acceptance criteria

   ### Dependencies
   [any cross-task dependencies]
   COMMENT
   )"
   ```

2. Move the issue to Approval:
   ```bash
   ITEM_ID=$(find-item.sh <ISSUE_NUMBER>)
   move-issue.sh "$ITEM_ID" "Approval"
   ```

3. **Stop.** Do not invoke `plan-review` or `execute-plan`. If a developer ran this interactively, tell them: "Plan is in Approval. Run `plan-review <NUMBER>` when you're ready to review it." If the skill ran autonomously via the dispatcher, that's the end of this cycle.

## Optional: Project test-tier reference

If the consumer project ships a `.claude/skills/planning-session/test-reference.md` documenting its testing tiers (frontend / backend / e2e, with example commands and helpers), the planner should read it before writing the plan so test ACs match the project's conventions. If the file is absent, the planner defers to `CLAUDE.md` and the project's existing test patterns.

## Key Rules

- **This skill does not run Q&A.** If the input contract is missing, stop and redirect to `developer-input`.
- One issue per invocation.
- Fresh subagent per iteration (no shared context across iterations).
- DoD is frozen after scoping — execution round cannot amend the contract.
- Never chain into `plan-review` or `execute-plan` — those are separate human-gated skills.
