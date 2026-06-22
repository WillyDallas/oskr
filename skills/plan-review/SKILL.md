---
name: plan-review
description: Use when processing an issue in the Approval column. Walks the developer through the plan, collects approve/reject, and either moves to Ready (with an explicit next-action prompt — never auto-executes) or routes the rejection to Re-Plan / Re-Research.
argument-hint: "[issue-number]"
allowed-tools: Bash(gh *) Bash(find-item.sh*) Bash(move-issue.sh*) Skill
---

You are the Approval gate. Your job is to walk the developer through the authored plan, collect a binary approve/reject decision, and move the issue accordingly. You do not start execution — that's `execute-plan`, and it only runs if the developer explicitly opts in.

## Setup

1. Read the issue number from `$ARGUMENTS`. If none provided, ask the developer.
2. Fetch: `gh issue view <NUMBER> --json title,body,comments`
3. Find the plan comment — a comment that opens with `## Implementation Plan` or `## Plan Revised (fast-path)` and links to a file under `docs/plans/`.
4. Read the plan file.

## Phase 1: Present the Plan

Walk the developer through:
- Plan summary (goals, tasks, dependencies)
- Acceptance criteria per task — call out any that look non-mechanical (hard to verify in a test/grep), since those are the common failure mode
- Any open questions or unresolved disagreements noted in the plan header

**End your turn here.** Close the walkthrough with an invitation to ask questions (e.g., "Questions about any part of this, or ready to decide?") and wait for the developer's reply. Do NOT present the approve/reject prompt in the same turn as the walkthrough — bundling them collapses the review into a preamble for the decision dialog and pressures a snap judgment. Phase 2 begins only after the developer has responded, whether with questions (answer them, then re-offer the decision) or with a signal that they're ready.

## Phase 2: Decision Prompt

Only after the developer has engaged with the Phase 1 walkthrough, ask: **"Approve or reject?"**

---

### Option A: Approve

1. Move the issue to Ready:
   ```bash
   ITEM_ID=$(find-item.sh <ISSUE_NUMBER>)
   move-issue.sh "$ITEM_ID" "Ready"
   ```

2. **Stop. Do not invoke `execute-plan`.** Present the next-action gate:

   > Plan approved and moved to Ready.
   >
   > - **(a) Execute this plan now** → invoke `execute-plan <NUMBER>`
   > - **(b) Clear another Approval item** → invoke `plan-review <NEXT>`
   > - **(c) Clear a Needs Input item** → invoke `developer-input <NEXT>`
   > - **(d) End the session**

   Default to **(b)** or **(c)** if the developer has more gate items waiting (ask them which columns have work), else **(d)**. **Never default to (a).** This is the gate that lets the developer clear all approvals in one session and let the dispatcher handle execution afterward.

---

### Option B: Reject

Run two sequential prompts. Do not combine them.

**Prompt 1 — Collect rejection feedback (free-text)**:
> What's wrong with the plan? Describe the issue in your own words — scope, task breakdown, missing context, wrong approach, etc.

Capture verbatim. Do not summarize, paraphrase, or ask follow-up questions at this step.

**Prompt 2 — Choose destination**:
- **Re-Plan** — the research is still valid; the plan itself is the problem. Issue returns to the Planning column.
- **Re-Research** — the research missed something material; re-investigate first. Issue returns to the Research column.

**Action** (two operations, then stop):

1. Post the rejection comment. The header is the routing contract — preserve the exact text:
   ```bash
   gh issue comment <NUMBER> --body "$(cat <<'COMMENT'
   ## Plan Rejected: Re-Plan

   <verbatim feedback from Prompt 1>
   COMMENT
   )"
   ```
   For Re-Research, swap the header to `## Plan Rejected: Re-Research`.

2. Move the issue:
   ```bash
   # Re-Plan:
   move-issue.sh "$ITEM_ID" "Planning"
   # Re-Research:
   move-issue.sh "$ITEM_ID" "Research"
   ```

The next downstream skill (`planning-session` for Re-Plan, `research-session` for Re-Research) reads the rejection header on its next invocation and routes behavior accordingly. Loop-reaction is out of scope here — this skill ends after the move.

## Key Rules

- **Never auto-invoke `execute-plan`.** Approval → Ready is a transition, not a trigger.
- **Phase 1 and Phase 2 are separate turns.** The walkthrough ends with an open invitation for questions; the approve/reject prompt comes only after the developer responds.
- Never skip the Phase 2 Option A next-action gate — it's the reason this skill exists.
- One issue per invocation.
- The rejection-comment headers (`## Plan Rejected: Re-Plan` / `## Plan Rejected: Re-Research`) are routing contracts — do not rewrite them.
