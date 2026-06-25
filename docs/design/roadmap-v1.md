# oskr v1 — "squirrlylabs from zero" (the Epoch)

**Date:** 2026-06-25 · **Status:** active Epoch · **Model:** [task-tracking](task-tracking-model.md)

## Definition of Done

A fresh **`squirrlylabs`** workspace where a single `/oskr-setup` run stands up the three pillars —
**brain (`hjarne`)**, **oskr (the plugin + project tracking)**, and **at least one client project
(`sluice`)** onboarded and driven through the research→plan→implement→review pipeline — working
against **both GitHub and self-hosted Forgejo**.

In one line: *start oskr over from zero in squirrlylabs and get to real client work.*

## Areas (ordered)

Order: **1 → (2 ∥ 4) → 3 → 5.** (Mirrors `squirrlylabs/WORKSPACE.md`'s migration sequence.)

1. **Task-tracking model** — codify Epoch/Area/Task + backend mapping; document; (later) enforce via
   a `/oskr-track` skill. *(This roadmap + the model doc; mostly satisfied by standing up the board.)*
2. **Backend adapter** — board ops behind one interface, GitHub + Forgejo interchangeable.
   - ✅ Step 0: seam consolidation (PR #24)
   - Forgejo backend `_backend_forgejo_*` (exclusive scoped labels) — *research: live-instance smoke*
   - Backend selection layer (`.backend` discriminator) + normalize `harness_list_board` shape
   - `init` provisioning consolidation (`backend_provision_*`) — last inline-`gh` site
   - *folds #9*
3. **Workspace & setup** — depends on Area 2.
   - Two-tier config + relocate state into workspace `.oskr/` (registry / global config)
   - `/oskr-setup` workspace bootstrap skill
   - `init` v2: adopt-existing-repo mode + backend choice — *folds #16*
   - dev-vs-installed plugin toggle — *relates #17*
4. **Brain (`hjarne`)** — lift Solvej's Karpathy `raw→distill→wiki` pattern; loose research-output
   coupling (research-session optionally registers a pointer). *research: brain design. folds #7*
5. **First client (`sluice`)** — the DoD proof.
   - Onboard Sluice (clone/adopt → board provisioned on Forgejo)
   - Drive one real issue end-to-end through the pipeline

## Parked (future Epochs — explicitly NOT v1)

- **Epoch: Learning** — `teach` as the `learning` domain + technique extraction (learning-records-as-ADRs,
  FORMAT compression). *Not on v1's critical path (north star names brain/oskr/tracking, not learning).*
- **Epoch: Skills adoption** — from the [skills audit](../research/2026-06-22-mattpocock-skills-audit.md):
  `diagnosing-bugs` agent (unblocks #15), issue-ingestion `to-issues`, agent-hardening
  (grilling→developer-input, tdd reference, two-axis review). *v1 uses `init`'s existing
  requirements-doc seeding for tracking; richer ingestion is post-v1.*
- **Existing parked issues:** #6 cross-project dispatch, #8 non-coding validation, #10 workflow shapes,
  #19 Orca spike, and others — each gets an Epoch when reached.

## Scoping decisions (to prevent drift)

- **Forgejo IS v1** — squirrlylabs is Forgejo-hosted, so client work runs on Forgejo.
- **Brain IS v1** — the north star names it.
- **Cross-project dispatch (#6) is parked** — v1 is one workspace getting one client going; multi-project
  arbitration is a scaling concern.
- **Full ingestion / debugger / teach are parked** — useful, but not required to hit the DoD.
