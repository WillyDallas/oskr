# Board flow — which skill at each state

**Date:** 2026-06-30

The operational runbook for the redesigned pipeline: the eight board states and the
skill you run at each. For the *why* (ability/stage/gate design, branch/merge model),
see [design/pipeline-redesign.md](design/pipeline-redesign.md). For board ops behind
one interface, see [design/blacksmith.md](design/blacksmith.md).

A unit of work flows **Backlog → Scoping → Planning → Plan Approval → Ready → In
Progress → In Review → Done**. Three human gates punctuate it: **scope** (GATE 1),
**plan-approval** (GATE 2), and the **merge** (GATE 3).

## The map

| Board state | What sits here | Run this | Gate |
|---|---|---|---|
| **Backlog** | a raw goal or idea, one issue | `scope <issue# \| "goal">` | — |
| **Scoping** | an Area being scoped: research → grill → PRD → decompose | `scope` (orchestrates `research`, `grill`, `decompose`) | **GATE 1** |
| **Planning** | a decomposed child task needing an implementation plan | `planning-session <child#>` | — |
| **Plan Approval** | a written plan awaiting release | `plan-approval <umbrella# \| child#>` | **GATE 2** |
| **Ready** | an approved task ready to build | `execute-plan <child#>` | — |
| **In Progress** | execution underway in a worktree | `execute-plan` (running); `sync-worktree` to refresh | — |
| **In Review** | child PR open vs the Area branch; umbrella once all children merged | merge child PRs → then `land-area <umbrella#>` | **GATE 3** |
| **Done** | merged to `main` | `clean-up` | — |

## State by state

**Backlog → Scoping — `scope` (GATE 1).** The intake front door. `scope` takes a
Backlog issue or a goal string, cuts an Area branch, and drives research → grill →
PRD → decompose. It calls three abilities along the way: `research` (assemble one
cited digest), `grill` (the one-question-at-a-time PRD interview), and `decompose`
(split the approved PRD into independently-grabbable child task issues under the Area
umbrella). When it finishes, the children land in **Planning**.

**Planning — `planning-session`.** A freshly-decomposed child carries a `## What` /
`## AC` body and an `area/*` label. `planning-session <child#>` runs the planner →
plan-reviewer loop and writes `docs/plans/<id>.md` (paths, signatures, TDD steps,
AC→test map), then moves the task to **Plan Approval**. Re-plan requests
(`## Plan Rejected: Re-Plan`) come back through here.

**Plan Approval → Ready — `plan-approval` (GATE 2).** The soft gate. `plan-approval
<umbrella#>` releases a whole Area's planned children to **Ready** in one step;
`plan-approval <child#>` releases one. It never moves the umbrella itself to Ready.

**Ready → In Progress → In Review — `execute-plan`.** `execute-plan <child#>` resolves
the task's base via `blacksmith_base_branch` (the Area branch, not `main`), branches off
it, and runs the implementer/reviewer generator–evaluator loop. On completion it opens a
child PR **targeting the Area branch** and the card lands in **In Review**. Use
`sync-worktree` before resuming work to merge the latest base in. Because children target
a non-default base, `Closes #N` does **not** fire on their merge — they are closed
explicitly when their PR merges into the Area branch.

**In Review → Done — the merge (GATE 3).** Merge each child PR into the Area branch.
Once every child has landed, `land-area <umbrella#>` rolls the umbrella to In Review and
opens the single **Area → main** PR whose `Closes` directives retire every child *and*
the umbrella. A human reviews that one consolidated diff and merges it — the hard gate.
That merge closes everything → **Done**.

**Done — `clean-up`.** Run by hand after merges land work in Done, one system cluster
per run. It archives the completed cards and reconciles documentation by the **docs/brain
split**: project-scoped docs stay in the repo, permanent systems knowledge routes to the
brain (`hjarne`, #28; staged to `docs/brain-inbox/` until it exists). Per-task plans move
to `docs/_local_archive/`.

## Bootstrap and aux skills

- **`init`** — interactive one-time bootstrap for a new oskr-managed project: creates the
  repo, provisions the board, writes `harness-config.json`. Not a per-state skill.
- **`sync-worktree`** — bring a feature branch up to date with its base before resuming
  work. Used during **In Progress**.
- **`writing-skills`** — meta: use when authoring or editing an oskr skill.

## Known drift

The live board and the delivery skills above use the eight-state model, but the
**provisioning/config layer** still encodes the old nine-column `gen-eval-9col` model:
`harness-config.json` declares a `needs_input` actionable column, `init` provisions the
nine-column board, and the parked autonomous dispatcher routes via retired columns.
Tracked in [#52](https://github.com/WillyDallas/oskr/issues/52).

> The superseded intake skills `research-session` and `developer-input` were removed —
> their function now lives in `research` (the agent loop), `grill` (the Q&A), and `scope`
> (the gate).
