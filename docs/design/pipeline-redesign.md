# oskr intake → delivery pipeline — redesign

**Date:** 2026-06-26 · **Status:** decided direction (v1) · **blocked on** [#26](https://github.com/WillyDallas/oskr/issues/26) create/link primitives · **spike:** [#32](https://github.com/WillyDallas/oskr/issues/32)
**Model:** [task-tracking](task-tracking-model.md) · **reconciles** mattpocock (`grilling`→`to-prd`→`to-issues`) + story-spark (`scope-milestone`/`create-issue`/`daily-standup`) against oskr's current per-task pipeline.

## The gap this closes

oskr plans and executes a *single board issue* well, but has **no front-end**: nothing turns an idea/goal into a scoped, board-ready tree, and the seam can't even create an issue. We also assume an issue already holds enough to let `research-session` run autonomously — **the wrong default.** The fix is to front-load human collaboration (grilling) before autonomous work, and to give the harness research *abilities* so that collaboration is grounded.

## The organizing idea: ability / stage / gate

Every skill is exactly one of three kinds. This maps onto the #33 invocation rule (user-invoked may call model-invoked, never another user-invoked).

- **Ability** — model-reachable, on-demand, no board column. The harness reaches for it as needed: `deep-research` (web), `hjarne` (brain read/write), `code-exploration`.
- **Stage** — a pipeline step that produces an artifact and (usually) moves a column.
- **Gate** — a human decision. There are **three**, with different hardness (below).

## The pipeline

| # | Stage | Kind | Artifact | Autonomous? | Column |
|---|-------|------|----------|-------------|--------|
| 0 | Capture | stage | seed issue, one-line goal | manual/auto | Backlog |
| 1 | Ground | stage | cited digest (web + brain + code) → lands in `hjarne/raw/`, posted to issue | yes | Scoping |
| 2 | **Grill & Scope** | **GATE 1 — hard** | settled scope, adversarial 1-at-a-time; **takes the issue from Backlog**, creates the milestone/Area, breaks it down | **never auto** | Scoping |
| 3 | Shape PRD → Area | stage | umbrella body: DoD, user stories, *behavioral* impl+test decisions, named seams, timeline, effort, task DAG | semi (drafted in Ground, confirmed at tail of Grill) | Scoping |
| 4 | Decompose | stage | tracer-bullet task issues (`## Parent` / `## What` / `## AC` / `## Blocked by` / `touches:`) + Epoch milestone + `area/*` + parent/child link | yes | → Planning |
| 5 | Per-task TDD plan | stage | `docs/plans/<id>.md`: paths, signatures, assertions, 5-step TDD, AC→test map | yes (parallel, per unblocked task) | Planning |
| 6 | **Plan approval** | **GATE 2 — soft** | approved / `## Plan Rejected: Re-Plan\|Re-Scope`. Proceeds by default; human may intervene | yes (default-proceed) | Approval |
| 7 | Execute | stage | code + tests + PR + `## Implementation Complete` / `## Execution Blocked: Re-Scope` | yes (parallel, worktree) | Ready → In Progress → In Review |
| 8 | **Merge** | **GATE 3 — hard** | merged PR | **never auto** | In Review → Done |
| 9 | Clean up | stage | doc-curator reconcile (reviewer-checked), archive plans, `hjarne/wiki/` page | yes (batched, **triggered off Done**) | Done |
| A | deep-research / hjarne / code-exploration | **ability** | digest / raw→wiki / effect+path map | called by stages 1, 2, 3, 5, 9 | none |

**Proposed columns (8):** Backlog, Scoping, Planning, Approval, Ready, In Progress, In Review, Done.
Retire `Research` + `Needs Input` (folded into Grill). Add `Scoping`. **No separate Clean Up column** — cleanup triggers off `Done`. *(Column reshape is a backend op — see [#26](https://github.com/WillyDallas/oskr/issues/26) + dispatcher `actionable_columns`.)*

## The three gates (decided)

- **Grill (hard).** Always human-driven. The front-end act: Backlog → scoped → milestone/Area created → decomposed into tasks. This is the "wrong default" fix.
- **Plan approval (soft).** A checkpoint, not a blocker. The autonomous queue proceeds through it by default; the developer can step in to approve/reject manually.
- **Merge (hard).** In Review → Done is the load-bearing human checkpoint. Agents build the queue *up to* the PR; the human merges.

## Autonomy model

The autonomous work queue **builds up** between the two hard gates, but **the developer can always drive any step manually.** Autonomy is an opt-in overlay on a manually-drivable pipeline, not a replacement for it.

- **Human anchors:** Grill (front), Merge (back). Everything between can run AFK.
- **After merge:** cleanup runs autonomously, batched, off the Done column.
- **Auto-grab safety must be mechanical, not agent-judged.** A task is auto-grabbable iff: `area/* set ∧ has-ACs ∧ zero-open-blockers ∧ no risk-flag ∧ no path-set intersection with any in-flight task`.
- **Blocked-by is a structured edge**, read via a normalized deps primitive (body-parse on GitHub, native deps on Forgejo) — never trusted from English prose.
- **Path collision is enforced**: Decompose emits `touches:` per task; the dispatcher serializes tasks with intersecting path-sets and re-runs the suite on the merged base before a dependent task auto-grabs (green-on-branch ≠ green-on-base).
- **Escalation paths:** `## Execution Blocked: Re-Scope` halts a task whose PRD assumptions proved wrong and parks it for human grilling; `## Plan Rejected: Re-Scope` routes a plan problem back to Grill.

## Altitude contract (the "collapse," resolved)

The maintainer reframe said collapse `planning-session` into scoping; we **keep** per-task planning (Stage 5) as a deliberate override, because it is a *different altitude*. The boundary that makes this non-redundant:

| | PRD (Area umbrella) — durable, behavioral | Per-task plan (`docs/plans/*`) — ephemeral, code-shaped |
|---|---|---|
| Fixes | **WHAT**: problem, solution shape, user stories, out-of-scope, timeline, effort, task DAG | **HOW**: file paths, TDD step order, verification commands |
| Tests | the **seam** a test attaches to (a behavioral fact) | the **assertions** (what the test checks) |
| Types | behavioral contract + named seam | **signatures** (derived from live code) |
| Approved at | Grill (scope + seams) | Plan approval (paths + assertions + signatures) |

Rule of thumb: **if it can go stale, it's the plan.** Grill and Plan-approval then approve *disjoint* content; neither re-litigates the other. Stage 5 plans and verifies-buildable; it is **forbidden from re-scoping** (it escalates instead).

## What this means for agents

**Nothing new, nothing retired.** oskr's 8 agents are generator+evaluator pairs (researcher/research-reviewer, planner/plan-reviewer, implementer/reviewer) + playwright-tester + doc-curator, and they're altitude-agnostic — they don't care which skill spawns them. The redesign only changes *which skill pulls the trigger*. The two "new abilities" (`deep-research`, `hjarne`) are **skills, not agents**; hjarne's distill step reuses the existing **researcher** agent.

## Transposition — current skills → new pipeline

| Current skill | Verdict | Target |
|---|---|---|
| research-session | **split** | autonomous engine → `code-exploration` ability; skeptic/question loop → Grill; `--spike` → `deep-research` ability; Research/Needs Input columns retired |
| developer-input | **merge** | folded into Grill (GATE 1) |
| planning-session | **keep** | Stage 5 (per-task), + parallel trigger + soft auto-approve path |
| plan-review | **keep → soften** | GATE 2, soft (default-proceed) |
| execute-plan | **keep** | Stage 7, + parallel/worktree + `Re-Scope` abort |
| board-cleanup | **split** | doc-curator/reviewer batch → Stage 9 (off Done) + `hjarne/wiki` write; manual Done-clearing stays a chore |
| init | **keep** | unchanged (still requirements-doc seeding) |
| sync-worktree | **keep** | unchanged util |
| start/end-dispatch | **keep** | drive the autonomous queue via `actionable_columns` |
| — | **new** | skills: `ground`, `grill-scope`, `shape-prd`, `decompose`, `clean-up`; abilities: `deep-research` (vendor), `hjarne`, `code-exploration` |

## Dependency on #26 (why this is blocked)

The front-end (stages 3–4) and the autonomous queue need seam primitives that **do not exist yet**. What's present today (`blacksmith_move_issue`, `blacksmith_find_item`, `blacksmith_list_board`, comment/label ops) covers *move/read*; the redesign needs **create + link + deps**, and every one must render on **both** GitHub (native sub-issues) and Forgejo (umbrella-body task-list + exclusive scoped labels):

| Needed op | Status | GitHub render | Forgejo render |
|---|---|---|---|
| `*_create_issue` (umbrella + task) | **missing** (stub) | `gh issue create` + add to Project | REST create + scoped labels |
| `*_link_parent` (parent↔child) | **missing** | native sub-issue (`sub_issues` header) | umbrella checklist + `## Parent` + `area/*` |
| `*_list_children` | **missing** | sub-issues query | parse umbrella task-list |
| `*_read_deps` (normalized blocked-by) | **missing** | body-parse `## Blocked by` + `blocked` label | native issue deps + `blocked` label |
| `*_move` / `*_find_item` / `*_list_board` | **exists** (`blacksmith_*`) | ✓ | to-build under `_blacksmith_forgejo_*` |

**Canonical-store rule:** keep membership/deps/timeline/effort in the **issue body** (+ `blocked` / `size/*` labels) as the source of truth; mirror to native GitHub features only as a nicety. The dispatcher must **never rank or gate on a field only one backend has.**

## Next steps (paused here, by decision)

1. Land #26's create/link/deps primitives across both backends.
2. Then build the new front-end skills (`ground`, `grill-scope`, `shape-prd`, `decompose`) and the column reshape.
3. Then soften plan-approval, wire the autonomous queue + `touches:` serialization, and move cleanup to trigger off Done.
4. Minimal `hjarne` write in the Ground/landing step so the brain isn't write-dead before Stage 9 exists.
