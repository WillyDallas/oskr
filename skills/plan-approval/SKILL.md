---
name: plan-approval
description: "Release planned tasks into Ready — a whole Area at once (umbrella#) or one child. The plan-approval gate (GATE 2)."
disable-model-invocation: true
argument-hint: "[umbrella# | child#]"
allowed-tools: Bash(gh *) Bash(find-item.sh*) Bash(move-issue.sh*) Bash(list-children.sh*) Read Grep AskUserQuestion
---

**GATE 2 — soft, batchable.** You release planned tasks from **Plan Approval** into **Ready**. You do **not** execute — approval → Ready is a *transition*, not a trigger; `/execute-plan` (or the dispatcher) runs the code afterward. "Soft" means an Area's children clear in one pass; the v2 auto-proceed bypass is deferred.

## Resolve the target

Read the issue number from `$ARGUMENTS` (ask if missing). Discriminate by label:

```bash
gh issue view <n> --json labels
```

- Carries **`type/umbrella`** → **Area batch path** (`<n>` is the umbrella).
- Otherwise → **single-child path**.

## Area batch path — `/plan-approval <umbrella#>`

1. **Enumerate.** `list-children.sh <umbrella#>` → children (`number`, `state`, `title`, `url`). Drop `state == closed` (already delivered).

2. **Walk the batch.** For each open child, read its plan — the `## Implementation Plan` / `## Plan Revised` comment (`gh issue view <child#> --json comments`) and the `docs/plans/<id>.md` it links. Present **one line per child**: title · the seam/AC that carries risk · the **board column** it sits in · any **blockedBy** the board shows. Call out non-mechanical ACs (hard to verify in a test/grep) and any child still blocked — those are the ones not to release. **End the turn here** with an open invitation for questions; do not bundle the decision into the walkthrough (bundling collapses review into a snap judgment). The developer's board is the source of truth for each child's column and blockedBy.

3. **Decide** (next turn, after the developer engages): which children to release? Default = every open child **in Plan Approval with no open blocker**.

4. **Release.** For each approved child:
   ```bash
   move-issue.sh "$(find-item.sh <child#>)" Ready
   ```
   **Idempotent** — a child already in Ready or beyond is a harmless re-set; the walkthrough simply won't list it as pending. **Leave blocked children** where they are — the board's native blockedBy already parks them, and the dispatcher's zero-open-blockers gate keeps a blocked Ready card un-grabbed.

5. **Advance the umbrella.** The umbrella flows through the columns but **skips Ready and is never executed**. Once any child reaches Ready it advances to **In Progress**:
   ```bash
   move-issue.sh "$(find-item.sh <umbrella#>)" "In Progress"
   ```
   Only if it still sits in Plan Approval (or earlier). Skip if it is already In Progress / In Review / Done. **Never move the umbrella to Ready.**

**Done when:** every approved child is in Ready; blocked and unplanned children are left in place; the umbrella is at least In Progress. Execution is the dispatcher's job, not yours.

## Single-child path — `/plan-approval <child#>`

1. Walk that child's plan (its `## Implementation Plan` comment + `docs/plans/<id>.md`); flag non-mechanical ACs. **End the turn**, invite questions.
2. On approval: `move-issue.sh "$(find-item.sh <child#>)" Ready`.
3. The parent umbrella advances on its **first** child reaching Ready. If you know the umbrella and it still sits in Plan Approval, run `/plan-approval <umbrella#>` — it reconciles the umbrella (and clears the rest of the Area in one pass).

## Reject — route back (either path)

Two sequential prompts. Do not combine them.

**Prompt 1 — feedback (free-text):** What's wrong with the plan? Scope, task breakdown, missing context, wrong approach. Capture **verbatim** — no summary, no follow-up.

**Prompt 2 — destination:**
- **Re-Plan** — scope/research still valid; the plan itself is the problem → child returns to **Planning**.
- **Re-Scope** — the PRD/scope is wrong; the Area needs re-grilling → child returns to **Scoping**.

Then two ops on the child, then stop:

1. Post the rejection comment — the header is the **routing contract**, preserve it exactly:
   ```bash
   gh issue comment <child#> --body "$(cat <<'COMMENT'
   ## Plan Rejected: Re-Plan

   <verbatim feedback from Prompt 1>
   COMMENT
   )"
   ```
   For Re-Scope, swap the header to `## Plan Rejected: Re-Scope`.

2. Move the child: Re-Plan → `move-issue.sh "$(find-item.sh <child#>)" Planning`; Re-Scope → `move-issue.sh "$(find-item.sh <child#>)" Scoping`.

Then tell the developer the next step **in prose** — both targets are user-invoked processes, so never a `Skill()` call:
- **Re-Plan** → "Run `/planning-session <child#>` to re-plan." It reads the `## Plan Rejected: Re-Plan` header and routes accordingly.
- **Re-Scope** → "Run `/scope <umbrella#>` to re-grill the Area." Re-entry resumes at the grill.

## Key rules

- **Never execute.** Releasing to Ready hands off to the dispatcher / `/execute-plan` — this skill never runs code.
- **Walkthrough and decision are separate turns.** The walkthrough ends on an open invitation; the approve/reject prompt comes only after the developer responds.
- **The umbrella skips Ready and is never executed** — advance it to In Progress, never Ready.
- **Idempotent.** Re-running on the same Area only moves what is still pending.
- The rejection headers (`## Plan Rejected: Re-Plan` / `## Plan Rejected: Re-Scope`) are routing contracts — never rewrite them.
