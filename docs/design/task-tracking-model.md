# oskr task-tracking model — Epoch / Area / Task

**Date:** 2026-06-25 (model confirmed 2026-06-29 — Epoch=milestone / Area=label held against the
flat-milestone constraint) · **Status:** convention (to be enforced by a future skill)

How oskr structures its own work, and the work of every project it manages. Three levels,
designed to render identically on GitHub **and** self-hosted Forgejo (it is the same
lowest-common-denominator discipline as the [backend adapter](platform-reframe.md)).

## The three levels

- **Epoch** — a major phase with a single Definition of Done (e.g. `oskr v1`). One Epoch is "in
  flight" at a time per project. Rendered as a **milestone**.
- **Area** — an "actual milestone" / workstream inside an Epoch, owned by an **umbrella issue**
  whose body holds the Area's DoD and a checklist of its Tasks. Rendered as: the umbrella issue +
  a scoped label `area/<slug>` carried by every Task in it.
- **Task** — a concrete unit of work, ≤ ~1 agent session. Rendered as an **issue** carrying its
  Epoch milestone + `area/*` label, listed under its Area umbrella, and flowing through the normal
  board Status columns.

## Backend rendering

The **portable core** is `milestone + area/* label + umbrella issue + task-list`. Everything else
is a per-backend nicety the adapter maps onto:

| Level | GitHub Projects v2 | Forgejo |
|---|---|---|
| Epoch | Milestone | Milestone |
| Area | Umbrella issue + `area/*` label (+ native **sub-issues**) | Umbrella issue + `area/*` **exclusive scoped** label + body task-list |
| Task | Issue: milestone + `area/*` label, **sub-issue** of umbrella | Issue: milestone + `area/*` label, listed in umbrella task-list |
| Order | `blocked-by` via sub-issue deps / `blocked/*` label | issue **dependencies** / `blocked/*` label |

Epoch (milestone) and Area (label) are **orthogonal to the board Status columns** — an issue has a
milestone, an `area/*` label, *and* a Status column simultaneously.

## Why milestone + label (the constraint that decides this)

**Milestones are flat and single-valued on both backends** — an issue has exactly one milestone and
milestones don't nest. We have **three** altitudes and **one** milestone field, so at most *one*
altitude can be a native milestone; the other two must ride a label + the issue hierarchy. We spend
the milestone on the **Epoch** (so release progress is task-granular and one-hop: every task is *in*
the milestone) and make **Area a label** (free, composable, and a catch-all costs nothing).

Crucially, **milestone and labels are both native, repo-level fields on GitHub *and* Forgejo** — they
live on the issue, not on a project — which is exactly why they carry the hierarchy portably. The
**Status** column is the lone project-scoped field (a GitHub Projects v2 field; faked with exclusive
`status/*` labels on Forgejo).

*(Rejected: Area-as-milestone. It splits each Area across a milestone + an umbrella issue kept in
sync, proliferates flat milestones, makes "all work in a release" a two-hop query, and makes release
progress count Areas not tasks — for a native progress-bar that sub-issue rollup already gives the
umbrella.)*

## Board views are filters, not objects

The two altitudes you actually look at are **views**, not new board objects:

- **The rocks** (Areas in an Epoch) → filter `milestone:"<epoch>" label:type/umbrella`. Umbrellas carry a
  `type/umbrella` discriminator label because "is a parent issue" isn't a native filter on either backend.
- **Tasks within an Area** → filter `label:area/<slug>`. On **Forgejo `area/*` is an exclusive scoped
  label**, so "one Area per task" is enforced natively; on GitHub it's convention.

GitHub renders these as saved Project views (grouped by Status = columns); Forgejo renders them as the
issues list with the same query params. `blacksmith_list_board` normalizes both.

## Solo tasks & delivery mode

- **Every task has an Area.** A solo task from scoping that needs no decomposition still gets an
  `area/*` — a real one if it fits, else a catch-all (`area/loose`) — so the auto-grab `area/* set`
  predicate stays uniform.
- **`delivery/manual`** (per-issue label, optional project default) marks work with no PR. It rides
  the same front-end but bypasses the autonomous back-end (plan→execute→merge) and is never
  auto-grabbed. See [pipeline-redesign.md](pipeline-redesign.md).

## Enforcement

For now this is a documented convention applied by hand. The intended end state is a `/oskr-track`
skill (and `backend_*` epoch/area/task operations) that creates and maintains this structure against
whichever backend a project uses — so the hierarchy is created the same way everywhere. Until then:
create the milestone, the `area/*` labels, and one umbrella issue per Area; tag Tasks with their
milestone + area label; keep each umbrella's checklist current.

## Why this exists

To stop scope drift. An Epoch's DoD is the contract for "this phase is done"; Areas are the only
places work may live; a Task that fits no Area is either out of scope or a missing Area. New ideas
that aren't on the current Epoch become *parked* (a future Epoch), not silent additions.
