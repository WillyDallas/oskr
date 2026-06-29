# oskr intake → delivery pipeline — redesign

**Date:** 2026-06-29 · **Status:** front-end + data model + branch/merge model + **v1 scope
solidified**; the autonomous loop is **deferred to v2** · **spike:** [#32](https://github.com/WillyDallas/oskr/issues/32) (v1 Area 7)
**#26 create/link/deps primitives:** ✅ **DONE** (PR #41) — this redesign is **unblocked**.
**Model:** [task-tracking](task-tracking-model.md) · **anchor consumer:** **oskr dogfooding its own
next feature** (sluice is unseeded; coremyotherapy is non-code). **Reconciles** mattpocock
(`grilling`→`to-prd`→`to-issues`) + story-spark (`scope-milestone`/`create-issue`/`daily-standup`)
against oskr's current per-task pipeline.

## The gap this closes

oskr plans and executes a *single board issue* well, but has **no front-end**: nothing turns an
idea/goal into a scoped, board-ready tree. We also assumed an issue already holds enough to let
research run autonomously — **the wrong default.** The fix is to front-load human collaboration
(grilling) before autonomous work, and to give the harness research *abilities* so that
collaboration is grounded.

## Two halves (the load-bearing reframe)

The pipeline is really **two halves**, and a project can adopt one without the other:

- **Front-end — intake/tracking.** Capture → Scope (grill → PRD → decompose). Produces a structured
  board. **Code-agnostic.** Every consumer uses this.
- **Back-end — autonomous delivery.** Plan → Execute → Merge → Cleanup. **Code-specific**: TDD plans
  with file paths, worktrees, PRs, the merge gate, the dispatch loop. Only code projects use it.

This split is what lets a **non-code** project (coremyotherapy on Squarespace) ride the front-end and
do delivery by hand, and lets a code project mark an individual chore `delivery/manual` to bypass the
back-end for just that issue. See **delivery mode** below.

> **The autonomous back-end is proven by code projects** — oskr dogfooding itself (GitHub) and sluice
> (Forgejo). coremyotherapy proves the **front-end + manual tracking**, not the back-end.

## The organizing idea: ability / stage / gate

Every skill is exactly one of three kinds. This maps onto the #33 invocation rule (user-invoked may
call model-invoked, never another user-invoked).

- **Ability** — model-reachable, on-demand, no board column. The harness reaches for it as needed:
  `research` (web+brain+code digest), `deep-research` (web, vendored), `code-exploration`, `hjarne`
  (brain read/write).
- **Stage** — a pipeline step that produces an artifact and (usually) moves a column.
- **Gate** — a human decision. There are **three**, with different hardness (below).

## The pipeline

| # | Stage | Kind | Artifact | Autonomous? | Column |
|---|-------|------|----------|-------------|--------|
| 0 | Capture | stage | seed issue, one-line goal | manual/auto | Scoping (active) / Backlog (parked) |
| 1 | Precursor-research | stage (ability wrapper) | cited digest posted as a comment; **card stays put** | **yes (loop)** | Scoping |
| 2 | **Scope** (`scope`) | **GATE 1 — hard** | settled scope → Area umbrella PRD + decomposed task tree | **never auto** (grill needs the human) | Scoping → Planning |
| 3 | Per-task TDD plan | stage | `docs/plans/<id>.md`: paths, signatures, assertions, 5-step TDD, AC→test map | yes (parallel, per unblocked task) | Planning |
| 4 | **Plan approval** | **GATE 2 — soft** | approved / `## Plan Rejected: Re-Plan\|Re-Scope` | v1: human (batchable) · v2: auto | Plan Approval |
| 5 | Execute | stage | code + tests + PR + `## Implementation Complete` / `## Execution Blocked: Re-Scope` | yes (parallel, worktree) | Ready → In Progress → In Review |
| 6 | **Merge** | **GATE 3 — hard** | merged PR | **never auto** | In Review → Done |
| 7 | Clean up | stage | doc reconcile: **systems/tech docs → brain (hjarne)**, **project docs + plans stay in repo**; archive plans | yes (batched, **off Done**) | Done |
| A | `research` / `deep-research` / `code-exploration` / `hjarne` | **ability** | digest / raw→wiki / effect+path map | called by stages 1, 2, 3, 7 | none |

**Columns (8):** Backlog, Scoping, Planning, Plan Approval, Ready, In Progress, In Review, Done.
Retire `Research` + `Needs Input` (folded into Scope). `Scoping` is the **ingestion point** — new
active-Epoch issues land and sit there; `Backlog` holds **parked** ideas (off the current Epoch). No
separate Clean Up column — cleanup triggers off `Done`.

**v1 is developer-driven; the "Autonomous?" column above is the *v2* target.** The autonomous loop
(auto-grab, the plan-approval auto-proceed bypass, `touches:` path-collision serialization,
`precursor-research`) is **deferred to v2** — the loop is stale and gets its own update, *adapted to
this flow, not the reverse*. In v1 the dev runs each stage's skill by hand; only `research` runs
without further prompting once invoked.

**Umbrella on the board (decided — it flows through, derived):** the Area umbrella **flows through the
columns** with a *derived* coarse status (a reconcile pass cross-refs its children), but **skips
Ready** (Ready is the single-task dispatch column) and is **never executed** (hard-excluded via
`type/umbrella`). Flow: Scoping → Planning (PRD published + children linked) → Plan Approval (every child
has a plan) → In Progress (first child reaches Ready) → In Review (**all** children closed) → Done
(human close). `/plan-approval <umbrella#>` is batch sugar (each child still in Plan Approval →
Ready); `<child#>` moves one child. Neither ever puts the umbrella in Ready.

## The front-end in detail (Capture → Scope)

The whole front-end collapses into **one human-initiated orchestrator plus one autonomous prep
skill**, sharing a research ability. This is the "collapse research/developer-input/planning into one
multi-phase collaborative step" the roadmap called for.

### Topology — the front-end skills, one user-facing command (decided; v1 built in v0.3.0)

Multiple skills driven by an orchestrator, **not** a monolith. The decider is `research`: both the
gate and the loop need it, so it must be a shared component — and once it's separate, the rest follow
the same grain as the existing back-end (planning-session / plan-review / execute-plan are already
separate).

| Component | Invocation | Role |
|---|---|---|
| **`scope`** (`/oskr:scope`) | **user-invoked** (the gate) | thin orchestrator: research → grill → to-prd → decompose; re-entry detection resumes at a phase |
| `research` | model-invoked **ability** | cited digest (deep-research + code-exploration + hjarne); spawns researcher/research-reviewer — **shared** with precursor |
| `grill` | model-invoked | relentless interview → shared understanding of the PRD judgment slots (reuse/adapt mattpocock `grilling`) |
| `to-prd` | **folded into `scope` Phase 3** | the 11-section PRD synthesis runs inline in `scope` (no scoping-less PRD scenario) — not a separate skill |
| `decompose` | model-invoked | slice → task issues: native deps, `link_parent`, `area/*`+`type/umbrella`, slim contract (flip of `to-issues`) |
| `precursor-research` | **v2 (deferred)** | the loop runs `research` ahead of time, posts the digest, leaves the card in Scoping — not built in v1 |

Two facts make this work:
- **Skills share the live conversation context (subagents don't).** `to-prd` invoked after `grill`
  still sees the entire grill Q&A — that's why it can synthesize without re-interviewing. (Phases are
  *skills*, deliberately, not agents.)
- **The #33 invocation rule forces a flip.** mattpocock's `to-prd`/`to-issues` are *user-invoked*
  (`disable-model-invocation: true`); a user-invoked skill can't call another. So they become
  **model-invoked** oskr skills the `scope` orchestrator can call. `grilling` is already
  model-invoked.

**Two paths, one shared `research`:**

```
AFK prep:  loop → precursor-research → research → comment           (stops at the gate)
The gate:  dev  → scope → [research] → grill → to-prd → decompose   (crosses it)
```

**`scope` mechanics (decided):**

- **Invocation:** `/oskr:scope [issue-number | "goal"]`. A number loads the issue. **Free text
  Captures first** — `scope` creates the seed issue in Scoping *at the start*, then runs the identical
  path. The issue is created **at the start**, not the end: it's the durable **Area umbrella** that the
  PRD lives inside and the anchor for the digest comment, `area/*` label, and resume state.
  (mattpocock's `to-issues` creates issues *last* because its issues are leaf tasks; ours is inverted.)
- **Re-entry detection** (existing-PRD / existing-digest) resumes at a phase, exactly like today's
  `planning-session` Phase 0.
- **Granularity is an outcome of the grill.** Many units → an **Area umbrella** (PRD in body,
  `area/*` + `type/umbrella` labels, children linked). One unit → a **bare scoped task** (no PRD; just
  `## What`/`## AC`). Either way the task gets an `area/*` (real, or catch-all `area/loose`) so the
  auto-grab `area/* set` gate stays uniform.

### The grill phase — drives toward the PRD (decided)

The grill is the relentless one-at-a-time interview, but its **exit condition is the PRD**: it runs
until there's shared understanding sufficient to fill every PRD slot, with **Named Seams as the hard
checkpoint** (the grill doesn't end until dev + agent agree on the seams). The grill settles the
*judgment* slots; `to-prd`/`decompose` *expand* the enumerable ones — so you're never interviewed
about a list a synthesis step can generate.

### The Area PRD — 11 sections (decided)

The umbrella issue body. mattpocock's `to-prd` template (7) + four oskr additions. **Solo tasks skip
the PRD**; sections scale down for small Areas.

| # | Section | Owner phase |
|---|---|---|
| 1 | **Problem** (user's view) | grill |
| 2 | **Solution** (user's view) | grill |
| 3 | **Definition of Done** | grill |
| 4 | **User Stories** (long numbered list) | to-prd (expand) |
| 5 | **Named Seams** (existing > new, highest, fewest) | grill — **hard checkpoint** |
| 6 | **Implementation Decisions** (modules/interfaces/contracts, *no paths*) | grill (key) → to-prd |
| 7 | **Testing Decisions** (what's a good test, prior art) | grill (key) → to-prd |
| 8 | **Out of Scope** | grill |
| 9 | **Timeline & Effort** | grill |
| 10 | **Task DAG** (slice sketch + blocked-by) | decompose (realizes into issues) |
| 11 | **Placement** — Epoch (milestone) + `area/<slug>` | grill |

## The three gates (decided)

- **Scope / Grill (hard).** Always human-driven; realized by the `scope` skill, whose core `grill`
  phase *is* the gate. Capture → scoped → Area/PRD created → decomposed. This is the "wrong default"
  fix.
- **Plan approval (soft).** In **v1, human-driven but batchable** — the dev runs `/plan-approval
  <umbrella#>` (every child → Ready) or `<child#>` (one). "Soft" = the *v2* loop auto-proceeds through
  it via a fail-closed bypass predicate (`bin/plan-approve-gate.sh`); that bypass is deferred to v2.
- **Merge (hard).** The **Area branch → main PR** is the load-bearing human checkpoint — one
  consolidated gate per Area (see Branch & merge model). Agents build the queue *up to* the PR; the
  human merges.

## Branch & merge model (decided — worktree-based Area branch)

The back-end is **developer-driven** (v1) and **worktree-based**:

- **Orca opens the Area worktree + branch; `scope` runs inside it and *records* that branch** on the
  umbrella (Placement: `Area branch: <branch>`). It does **not** create a branch — Orca owns naming,
  and the name is freeform (`WillyDallas/area-pipeline-backend`, *not* derivable from the `area/*`
  label), so the branch is **captured, never derived**.
- **Child task PRs target the recorded Area branch, not main** — base is **per-Area configurable**.
  Resolution: `blacksmith_base_branch <child#>` reads the child's parent umbrella → its recorded Area
  branch (fallback `main` for solo / area-less tasks). Orca branching child worktrees off that base is
  the **#19** enhancement — not a blocker (without it, children branch off main).
- **Two merge points, one gate.** child → Area branch is a **light staging merge** (dev clicks merge;
  auto-on-green in v2 — *not* a review gate). The **Area branch → main PR is the single hard human
  gate (GATE 3) per Area** — the consolidated Area diff is what you review. This concentrates scrutiny
  into one place; the cost is one larger diff instead of N small ones (revisit per-child review only
  if an Area gets unwieldy).
- **The invariant refines:** "merge is never auto" means **never auto-merge to *main***. Staging
  merges into the Area branch may be light or (v2) automatic-on-green.
- **`Closes #N` does NOT auto-close on merge to a non-default branch** (GitHub & Forgejo). Children
  merge into the Area branch, so the flow must **explicitly close** each child on its staging merge.
  That explicit close is the portable trigger for *umbrella → In Review* (all children
  `state==closed`) — no PR-base detection needed (no op reads a PR's target anyway).
- **Drift is managed** by merging main *into* the Area branch as main moves, so the final Area→main PR
  is cut from an up-to-date branch. `sync-worktree.sh` covers the worktree mechanics (extend for
  Area-branch teardown after the Area→main merge).
- **Rejected: the integration branch as a default *autonomous* feature** — under v2 auto-merge it is
  N+1 hard gates; the worktree/dev-driven framing is what makes it pay off. Per-Area `area/atomic`
  opt-in stays possible later.

## Autonomy model (v2 — deferred; v1 is developer-driven)

**v1 ships the pipeline as a developer-driven flow** (the dev runs each skill). Everything below is the
**v2** target — the stale autonomous loop, adapted to the flow above. The refined invariant still
holds whenever the loop lands: **nothing autonomous *crosses* a hard gate.** Research is autonomous
prep; producing the PRD (Scope) and merging the PR (Merge) are human. The autonomous queue **builds up
between the two hard gates**, but the developer can always drive any step manually.

- **Human anchors:** Scope (front), Merge (back). Everything between can run AFK.
- **Before Scope:** only `precursor-research` runs (prep, posts a comment, never advances the card).
- **After Merge:** cleanup runs autonomously, batched, off the Done column.
- **Auto-grab safety is mechanical, not agent-judged.** A task is auto-grabbable iff: `area/* set ∧
  has-ACs ∧ zero-open-blockers ∧ no risk-flag ∧ not delivery/manual ∧ no path-set intersection with
  any in-flight task`.
- **Blocked-by is a structured edge**, read via `blacksmith_read_deps` (native deps on both
  backends) — never trusted from English prose.
- **Path collision is enforced**: decompose emits `touches:` per task; the dispatcher serializes
  tasks with intersecting path-sets and re-runs the suite on the merged base before a dependent task
  auto-grabs (green-on-branch ≠ green-on-base).
- **Escalation:** `## Execution Blocked: Re-Scope` halts a task whose PRD assumptions proved wrong
  and parks it for human grilling; `## Plan Rejected: Re-Scope` routes a plan problem back to Scope.

## Delivery mode (`delivery/manual`)

Some work has no PR (a Squarespace edit; "rotate the API key"; "email the client"). Delivery mode is
**per-issue, with a project default**:

- **Source of truth: an issue label `delivery/manual`.** Optional `harness-config.json` default
  (`"delivery": "manual"`) just sets the default for new issues.
- **No separate pipeline.** Same board, same front-end. It only **bypasses the back-end**
  (plan→execute→merge): the card goes Ready → In Progress (human does it) → Done by hand, and the
  dispatcher **never auto-grabs it** (it's in the auto-grab predicate above).
- **coremyotherapy is the degenerate case** — project-default `delivery/manual`, so *every* issue is
  manual and the dispatch loop is off. One mechanism covers both.

## Data model (settled: Option 1)

See [task-tracking-model.md](task-tracking-model.md). The constraint that decides it: **milestones
are flat and single-valued on both GitHub and Forgejo** — three altitudes, one milestone field, so
only one altitude can be a native milestone.

- **Epoch = milestone.** **Area = umbrella issue + `area/*` label** (+ `type/umbrella` discriminator).
  **Task = issue** in the Epoch milestone, `area/*`-labelled, linked under its umbrella.
- **Milestone and labels are native, repo-level fields on both backends** (not project-scoped) —
  that's why they carry the hierarchy. Only the **Status** column is a project-scoped field on GitHub
  (faked with exclusive `status/*` labels on Forgejo).
- **"Area boards" are filters, not objects.** GitHub: a Project *view* filtered `milestone:"…"`
  and/or `label:area/…`. Forgejo: the issues list with the same query params. The rocks view =
  `label:type/umbrella`.

## Altitude contract (the "collapse," resolved)

We **keep** per-task planning (Stage 3) as a deliberate override, because it is a *different
altitude*:

| | PRD (Area umbrella) — durable, behavioral | Per-task plan (`docs/plans/*`) — ephemeral, code-shaped |
|---|---|---|
| Fixes | **WHAT**: problem, solution shape, user stories, out-of-scope, timeline, effort, task DAG | **HOW**: file paths, TDD step order, verification commands |
| Tests | the **seam** a test attaches to (a behavioral fact) | the **assertions** (what the test checks) |
| Types | behavioral contract + named seam | **signatures** (derived from live code) |
| Approved at | Scope (scope + seams) | Plan approval (paths + assertions + signatures) |

Rule of thumb: **if it can go stale, it's the plan.** Scope and Plan-approval approve *disjoint*
content; neither re-litigates the other. Stage 3 plans and verifies-buildable; it is **forbidden from
re-scoping** (it escalates instead).

## What this means for agents

**Nothing new, nothing retired.** oskr's 8 agents are generator+evaluator pairs
(researcher/research-reviewer, planner/plan-reviewer, implementer/reviewer) + playwright-tester +
doc-curator, and they're altitude-agnostic. The redesign only changes *which skill pulls the
trigger*. The new abilities (`research`, `deep-research`, `hjarne`, `code-exploration`) are
**skills/abilities, not agents**; `research` reuses the existing **researcher/research-reviewer**
pair, and cleanup reuses **doc-curator**.

## Transposition — current skills → new pipeline

| Current skill | Verdict | Target |
|---|---|---|
| research-session | **split** | autonomous engine → `code-exploration`/`research` ability; skeptic/question loop → `grill`; `--spike` → `deep-research`; Research/Needs Input columns retired |
| developer-input | **merge** | folded into `scope` (GATE 1) |
| planning-session | **keep** | Stage 3 (per-task); v2: parallel trigger + auto-approve path |
| plan-review → `plan-approval` | **modify** | GATE 2; v1 human + batch sugar (`/plan-approval <umbrella#>`/`<child#>`); v2 fail-closed auto-proceed bypass |
| execute-plan | **modify** | Stage 5: **per-Area configurable base** (child PR → Area branch), **explicit child close** on staging merge, Area worktree; `Re-Scope` abort; v2: parallel |
| board-cleanup | **split** | doc reconcile → Stage 7 (off Done) with the **docs/brain split**; manual Done-clearing stays a chore |
| init | **extend** | + **adopt-existing** mode (brownfield re-intake; see coremyotherapy below) |
| sync-worktree / start-end-dispatch | **keep** | unchanged utils; dispatcher drives the queue via `actionable_columns` |
| — | **new** | skills: `precursor-research`, `scope` (orchestrator), `grill`, `to-prd`, `decompose`, `clean-up`; abilities: `research`, `deep-research` (vendor), `hjarne`, `code-exploration` |

## Blacksmith op mapping (#26 landed — abstract names → real verbs)

The pipeline composes these existing `blacksmith_*` verbs (all in `bin/harness-lib.sh`, both
backends live-validated):

| Pipeline need | Real verb |
|---|---|
| Capture / create issue | `blacksmith_create_issue <title> [body] [labels_csv]` → `{number,url}` |
| Move column | `blacksmith_move_issue <item> <Status>` |
| Find board item | `blacksmith_find_item <number>` |
| Read board | `blacksmith_list_board` (neutral shape) |
| Link Area↔Task | `blacksmith_link_parent <parent> <child>` |
| List children | `blacksmith_list_children <parent>` |
| Blocked-by (typed edge) | `blacksmith_read_deps <number>` |
| Labels (`area/*`, `type/umbrella`, `delivery/manual`) | `blacksmith_ensure_label` / `blacksmith_issue_add_label` |
| Post digest / Q&A / PRD comment | `blacksmith_issue_comment <number> <body>` |
| Status read | `blacksmith_issue_status` / `blacksmith_item_status` |
| Cleanup archive / PR check | `blacksmith_archive_item` / `blacksmith_pr_open_count` |

**Seam ops — `set_milestone` + `add_dep` shipped (v0.2.12); one gap remains:**
- ✅ **`blacksmith_set_milestone <issue> <title>`** — Epoch assignment, both backends (resolves
  title→number on GitHub / title→id on Forgejo; **never creates** — that stays a manual setup step,
  and an unknown title fails loudly). Skills **compose** `create_issue` + `set_milestone` rather than a
  `create_issue` milestone param (matches the existing "callers compose by number" rule). Test:
  `test_blacksmith_set_milestone.sh`.
- ✅ **`blacksmith_add_dep <blocked> <blocker>`** — native blocked-by write, both backends (GitHub
  resolves blocker→db id then POSTs `/dependencies/blocked_by`; Forgejo POSTs `IssueMeta{index}` to
  `/dependencies`). Test: `test_blacksmith_add_dep.sh`.
- ⏳ **Per-Area configurable base** (Track C) — `base_branch` is read as a single scalar at ~5 sites
  (execute-plan PR base, `sync-worktree`, `sync-development`, the dispatch-incomplete `$BASE..$b`
  count, board-cleanup's `baseRefName==base` check). Each must resolve the Area branch (`area/<slug>`).

**Canonical-store rule** still holds: membership/deps live in native fields + the issue body; never
gate on a field only one backend has.

## Cleanup & the docs/brain split (decided 2026-06-29)

Stage 7 routes documentation two ways:

- **Permanent systems/tech documentation → the brain (hjarne, #28)** — the distilled-knowledge home
  (Karpathy raw→distill→wiki, loose-coupling index).
- **Project-scoped docs + versioned per-task plans → stay in the project repo** (`docs/`,
  `docs/plans/`).

The brain is **not** the canonical home for every skill output. The cleanup skill needs an explicit
**distill-to-brain vs keep-in-repo** rule.

## coremyotherapy — brownfield adopt (the init story)

coremyotherapy is on GitHub (Project #3, 35 issues seeded flat from `coremyotherapy-build-plan.md`,
no Areas, no `area/*`, 2-level phase-milestone → task). It's **Squarespace — non-code, front-end +
manual tracking only.** A weird fit for the coding workflow, but a real near-term need.

Adopt = a **one-time brownfield re-intake** (the new `init` adopt-existing mode), *not* the
steady-state grill:

1. **Harvest** the 35 issues into a single tasklist doc.
2. **Reconcile** with the developer — a lot of real work has happened off the board; get current
   state.
3. **Re-emit** in oskr style: 1 Epoch milestone; the phases (R/F/B/P/L/H) become **Areas**
   (`area/*` + `type/umbrella` umbrellas); tasks linked under them. Project-default `delivery/manual`;
   dispatch loop off.
4. Issues carry `## Parent` / `## What` / `## AC` — **no `touches:` / TDD-ACs** (those are
   back-end/delivery-side). ACs become human-checkable acceptance, not test assertions.

This exercises the **adopt path**, not the autonomous proof. The workflow proof lives on oskr
(GitHub) and sluice (Forgejo).

## Build plan (v1)

The goal: construct the skills/agents/scripts that make this flow runnable. **Agents are unchanged**
(none new, none retired). Two delivery tracks; the foundation unblocks both.

**Track 0 — shared foundation (do first; unblocks A + B + C):**
1. ✅ **Seam ops** in `bin/harness-lib.sh`: `blacksmith_set_milestone` + `blacksmith_add_dep`, both
   backends + hermetic fixtures — **done (v0.2.12), suite green (16/16)**.
2. ✅ **Board reshape (oskr Project #2)** — 8 columns live (added Scoping, renamed Approval→Plan
   Approval, dropped Research/Needs Input via in-place `updateProjectV2Field` with id-preservation, no
   orphaned assignments); `delivery/manual` label created; `type/umbrella` + `area/*` already existed
   (adopted `type/umbrella` as the umbrella discriminator instead of the invented `kind/area`).
   **Roadmap triaged**: 11 stale/done closed + cards archived; v1 milestone curated to 15 issues.
   Remaining: a repeatable `workflow.kind` + the same reshape as a setup step for *new* projects (#27).

**Track A — coremyotherapy (near-term; tracking-only, needs no back-end):**
3. `init` **adopt-existing** mode: harvest → reconcile → re-emit (1 Epoch, phases → Areas, slim
   `## What`/`## AC` issues, project-default `delivery/manual`, loop off). Then run it on coremyotherapy.

**Track B — the coded front-end (dogfooded on oskr): ✅ BUILT (v0.3.0)**
4. ✅ **`research` ability** — reuses researcher/research-reviewer + `WebSearch` over the synced tree;
   posts one cited `## Research Digest`. (Vendored `deep-research` + `hjarne`/`code-exploration`
   enrichment deferred to v2.)
5. ✅ **Front-end skills:** `scope` (user-invoked orchestrator — Area branch, research→grill→PRD→
   decompose, re-entry; **`to-prd` folded in** as Phase 3); `grill` (mattpocock `grilling` → the
   11-section PRD, Named-Seams hard exit); `decompose` (flip `to-issues`: `area/*`+`type/umbrella`,
   `link_parent`, `add_dep`, slim `## What`/`## AC` contract). Plus 5 `bin` wrappers
   (create-issue/set-milestone/link-parent/add-dep/list-children).

**Track C — the coded back-end (oskr):**
6. `execute-plan` **modify**: per-Area configurable base (child PR → Area branch), explicit child
   close on staging merge, Area worktree (+ teardown).
7. `plan-review` → **`plan-approval`**: v1 human + the batch/individual `/plan-approval` sugar.
8. `board-cleanup` → **`clean-up`**: off Done, with the docs/brain split rule.

**Deferred to v2 (explicitly out of v1):** the autonomous loop update (run without `-p`), the
auto-grab predicate, the plan-approval auto-proceed bypass (`bin/plan-approve-gate.sh`), `touches:`
path-collision serialization, `precursor-research`, auto-merge-on-green, full `hjarne`. Each gets its
own issue off #32.

**This build is itself v1 Area 7 (#32):** bootstrap Track 0 + the front-end skills the current way,
then use the new `scope` to decompose Track C against oskr — the first real dogfood.
