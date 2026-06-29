---
name: scope
description: "Scope a goal or Backlog issue into an Area — research → grill → PRD → decomposed tasks, on its own Area branch. The intake front door (GATE 1)."
disable-model-invocation: true
argument-hint: "[issue-number | \"goal text\"]"
allowed-tools: Bash(gh *) Bash(git *) Bash(create-issue.sh*) Bash(set-milestone.sh*) Bash(find-item.sh*) Bash(move-issue.sh*) Read Glob Grep Skill AskUserQuestion
---

The front door. One human-driven gate that takes a raw goal to a board-ready Area: **research → grill → PRD → decompose**. It is **GATE 1 (hard)** — it never runs unattended, because the grill needs you. The phases are model-invoked skills run in sequence; they share this conversation, so each sees the last.

## Phase 0 — anchor the work

- **Resolve the input.** If `$ARGUMENTS` is a number, load it (`gh issue view <n> --json title,body,labels,comments`). Otherwise **Capture first**: `create-issue.sh "<goal text>"` to mint the seed umbrella, then load it. The issue is the durable home the PRD lives in and the anchor for every later step — create it at the **start**, never the end.
- **Move it to Scoping:** `move-issue.sh "$(find-item.sh <n>)" Scoping`.
- **Re-entry:** if the umbrella body already holds the 11-section PRD, or a `## Research Digest` comment is present, resume at the first unfinished phase — do not redo a completed one.
- **Record the Area branch.** `scope` runs inside an **Orca-created worktree**, so the branch already exists — do NOT create one. Capture it (`git branch --show-current`) and record it on the umbrella **two ways**: a human Placement line (`Area branch: <branch>`) **and** the adapter-owned marker `<!-- oskr:area-branch <branch> -->` — the machine source `blacksmith_base_branch` reads (prose alone collides with phrases like "the Area branch: read the base …"). It is the base every child PR will target. The name is Orca's (freeform, e.g. `WillyDallas/area-pipeline-backend`) — captured, never derived from the `area/*` label. *(If not in a worktree — e.g. run from the base branch — note it and skip; child execution falls back to `main`. Orca branching child worktrees off this base is the #19 enhancement, not a blocker.)*

## Phase 1 — Ground

Run the `/research` skill on the umbrella. It posts one cited `## Research Digest`. Skip if a fresh digest is already there. **Done:** the digest is on the issue and in context.

## Phase 2 — Grill

Run the `/grill` skill. It interviews you one question at a time toward shared understanding of the PRD's judgment slots, with **Named Seams the hard exit**. **Done:** every judgment slot settled, seams agreed.

## Phase 3 — PRD (synthesize, no re-interview)

Write the **11-section Area PRD** (below) into the umbrella **body** from the grill — do not re-ask what the grill settled; *expand* the enumerable sections. Then stamp it:
- `set-milestone.sh <umbrella> "<Epoch title>"` (the Placement section's Epoch).
- add labels `area/<slug>` **and** `type/umbrella` (`gh issue edit <umbrella> --add-label "area/<slug>,type/umbrella"`).
- `move-issue.sh "$(find-item.sh <umbrella>)" Planning`.

**Granularity:** if the grill showed the goal is a *single* unit of work, keep it as one scoped task — write a `## What` + `## AC` instead of the full PRD, skip `type/umbrella`, and **skip Phase 4**.

## Phase 4 — Decompose

Run the `/decompose` skill on the umbrella. It cuts tracer-bullet task issues, links them under the umbrella with native deps, and lands them in Planning.

**Done when:** the umbrella body is the 11-section PRD; its Epoch + `area/*` + `type/umbrella` are set; children are created, linked, dep-ordered and in **Planning**; the umbrella is in **Planning**. The autonomous back-end (plan → execute → merge) takes it from there.

---

## Reference — the 11-section Area PRD

The umbrella issue body. Sections 1–3, 5, 8, 9, 11 are settled in the grill; **6**/**7** are grill-keyed then expanded here; **4** and **10** are expanded here / by `decompose`. Scale 6/7/9 down for a small Area.

```markdown
## Problem
The problem, from the user's perspective.

## Solution
The solution, from the user's perspective.

## Definition of Done
The contract for "this Area is done."

## User Stories
A long, numbered list — `As an <actor>, I want <feature>, so that <benefit>` — covering every aspect.

## Named Seams
The seam(s) tests attach to. Existing over new, highest, fewest (ideal: one). Agreed in the grill.

## Implementation Decisions
Modules / interfaces / contracts / schema / API. NO file paths or code (they go stale).

## Testing Decisions
What makes a good test here (external behavior, not implementation); modules tested; prior art.

## Out of Scope
What this Area explicitly does not cover.

## Timeline & Effort
Rough size + sequencing.

## Task DAG
The slice sketch + blocked-by edges — realized into issues by `decompose`.

## Placement
Epoch (milestone): <title> · Area: area/<slug>
```
