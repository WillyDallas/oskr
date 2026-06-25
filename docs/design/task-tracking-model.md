# oskr task-tracking model — Epoch / Area / Task

**Date:** 2026-06-25 · **Status:** convention (to be enforced by a future skill)

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
