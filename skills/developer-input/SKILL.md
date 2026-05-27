---
name: developer-input
description: Use when processing an issue in the Needs Input column. Walks the developer through the research summary and clarifying questions, posts answers as a `## Q&A Complete` comment, moves the issue to Planning (or to Done for spikes whose Q&A hands off to follow-on issues), and stops. Planning itself is handled by `planning-session` (either run now by the developer or picked up later by the dispatcher).
argument-hint: "[issue-number]"
allowed-tools: Bash(gh *) Bash(source *) Bash(find-item.sh*) Bash(move-issue.sh*) Bash(git add docs/research/*) Bash(git commit -m*) Bash(git status) Bash(git diff*) Bash(git rev-parse*) Skill
---

You are the Needs Input gate. Your job is to resolve the Q&A that a researcher left open, post the answers so they survive for later sessions, and move the issue forward. For most issues that's **Needs Input → Planning**; for spike issues whose Q&A hands off to follow-on issues it's **Needs Input → Done**. You do not produce the plan — `planning-session` does that.

## Setup

1. Read the issue number from `$ARGUMENTS`. If none provided, ask the developer.
2. Fetch: `gh issue view <NUMBER> --json title,body,comments`
3. Find the research comment (a comment that opens with `## Research Complete` or contains a `## Clarifying Questions` section).
4. Note whether this is a **spike** — title begins with `Spike:` (case-sensitive). Spikes have a different terminal transition (see Phase 4).

## Phase 1: Present Research Summary

Default to a **fuller overview** before the questions. Issues sit in Needs Input precisely because the developer hasn't gotten to them — context loss is the rule, not the exception. The cost of over-context is a few extra lines of skim; the cost of under-context is the dev answering blind.

The overview must cover, in this order:

1. **User-journey context** — where this feature lives in the broader product flow, including adjacent issues (the trigger surfaces, the downstream handoff, blocked-by relationships). Pull from any `## Flow context` comments and adjacent-issue references.
2. **Scope changes since the issue opened** — if any comment resets or narrows scope (e.g., a `## Scope reset` block), surface it and explicitly call out that earlier `## Q&A Complete` or `## Research Complete` blocks predating the reset are **stale**. Walk the latest research only.
3. **The active research output** — recommendation, key file paths, risks, decomposition. Skip stale Q&A blocks entirely.
4. **The proposed user flow / implementation shape** — a concrete sketch of what the user sees and what code paths run, so the dev can evaluate the questions against a mental model.

End the overview with: *"Skip ahead to questions if you're already up to speed — otherwise let me know if you want to drill into any part of this before we start."* Wait for the developer to either ask for more detail or signal ready.

If the developer asks for more investigation rather than ready-to-answer, stop and tell them to re-run `research-session <NUMBER>`.

## Phase 2: Walk Through Clarifying Questions

1. Present each question **one at a time**.
2. For multiple-choice questions, show options clearly.
3. Wait for the developer's answer before moving on.
4. The developer may elaborate, change their mind, or ask you to investigate further — adapt.
5. If a question becomes irrelevant given earlier answers, skip it and explain why.

## Phase 3: Confirm Answers

Present the full Q&A back to the developer:
> "Here's what I have. Do these look right, or do you want to change any answers?"

Do not proceed until the developer confirms.

## Phase 4: Post and Hand Off

1. Post a `## Q&A Complete` comment to the issue containing the full Q&A verbatim. This comment is the handoff contract — `planning-session` reads it to produce the plan without re-asking:

   ```bash
   gh issue comment <NUMBER> --body "$(cat <<'COMMENT'
   ## Q&A Complete

   **Q1: [question text]**
   [developer's answer]

   **Q2: [question text]**
   [developer's answer]

   <...>
   COMMENT
   )"
   ```

2. **Optional — commit research-doc revisions.** If the Q&A walk-through materially revised a research artifact under `docs/research/` (e.g., the developer's answers overturned assumptions in the spike deliverable and you edited the doc in-place), commit it before moving the issue so the loop-level invariant of a clean tracked tree between dispatches is preserved:

   ```bash
   if ! git diff --quiet -- docs/research/; then
     git add docs/research/<FILENAME>
     git commit -m "<short description of revision>"
   fi
   ```

   This skill's git allowlist is scoped to `docs/research/` only — do not commit anything outside that path. If the revision produced changes outside `docs/research/` (unusual), stop and ask the developer to handle them manually.

3. Pick the terminal transition.

   **Non-spike issues** — move to Planning:

   ```bash
   ITEM_ID=$(find-item.sh <ISSUE_NUMBER>)
   move-issue.sh "$ITEM_ID" "Planning"
   ```

   **Spike issues** — ask the developer first:

   > "This is a spike. Did the Q&A produce plannable work for **this** issue, or did it just hand off to follow-on issues?"
   >
   > - **Hand-off** → move to **Done**.
   > - **Plannable work on this issue** (unusual — usually spikes spawn follow-ons) → move to Planning as normal.

   For the hand-off case, use `"Done"` instead of `"Planning"` in the move command, and additionally close the GitHub issue:

   ```bash
   move-issue.sh "$ITEM_ID" "Done"
   gh issue close <ISSUE_NUMBER> --reason completed
   ```

   Record which transition was taken — Phase 5 branches on it.

## Phase 5: Next-Action Gate

**Stop here. Do not auto-invoke `planning-session`.**

**If the issue was moved to Planning** (non-spike, or spike with plannable work on this issue), present three options and wait:

- **(a) Run `planning-session` now in this session** — invoke via `Skill(name: "planning-session", args: "<NUMBER>")`.
- **(b) Hand off — the dispatcher (or a later session) will pick it up.** The `## Q&A Complete` comment is the contract; `planning-session` reads it autonomously.
- **(c) Tackle another Needs Input issue** — re-invoke this skill for the next issue, or query the board first.

The default is **(b)**. Only proceed to (a) if the developer explicitly says so. This is the gate that lets the developer clear multiple Needs Input issues in one session and let the loop handle the planning work afterward.

**If the issue was moved to Done** (spike hand-off), there is nothing to plan on this issue. Offer:

- **(a) Tackle another Needs Input issue** — re-invoke this skill for the next issue, or query the board first.
- **(b) End the session.**

## Key Rules

- One issue per invocation.
- The `## Q&A Complete` header is the routing contract — preserve the exact text so `planning-session` finds it.
- Never skip Phase 5. The hand-off prompt is the whole point of this skill.
