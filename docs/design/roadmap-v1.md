# oskr v1 — "squirrlylabs from zero" (the Epoch)

**Date:** 2026-06-25 · **Status:** active Epoch · **Model:** [task-tracking](task-tracking-model.md)

## Definition of Done

A fresh **`squirrlylabs`** workspace where a single `/oskr-setup` run stands up the pillars —
**brain (`hjarne`)**, **oskr (the plugin + project tracking)**, and **learning (`teach`)** — and
**two client projects** are onboarded and driven through oskr's **redesigned intake→delivery
pipeline** (grill→PRD/Area→decompose→plan→execute→merge→cleanup; see
[pipeline-redesign](pipeline-redesign.md)): **`sluice` on self-hosted Forgejo** and
**`coremyotherapy` on GitHub** (adopted from gh-oskr). The two-client split proves a
**mixed-backend workspace** works end-to-end — through the new pipeline, on both backends.

In one line: *start oskr over from zero in squirrlylabs and run real client work across both backends.*

## Areas (ordered)

Order: **1 → (2 ∥ 4) → (3 ∥ 7) → (5 ∥ 6).** (Mirrors `squirrlylabs/WORKSPACE.md`'s migration sequence;
Area 7 depends on Area 2's create/link primitives and gates the Area 5 DoD proof.)

1. **Task-tracking model** — codify Epoch/Area/Task + backend mapping; document; (later) enforce via
   a `/oskr-track` skill. *(This roadmap + the model doc; mostly satisfied by standing up the board.)*
2. **Backend adapter** — board ops behind one interface, GitHub + Forgejo interchangeable.
   - ✅ Step 0: seam consolidation (PR #24)
   - Forgejo backend `_blacksmith_forgejo_*` (exclusive scoped labels) — *research: live-instance smoke*
   - Backend selection layer (`forge` discriminator) + normalize `blacksmith_list_board` shape
   - `init` provisioning consolidation (`blacksmith_*` create_repo/provision) — last inline-`gh` site
   - **Ingest write-ops** (`*_create_issue`, `*_link_parent`, `*_list_children`, `*_read_deps`) on both
     backends — the create/link/deps family Area 7's front-end writes through (move/read already exist)
   - *folds #9*
3. **Workspace & setup** — depends on Area 2.
   - Two-tier config + relocate state into workspace `.oskr/` (registry / global config)
   - `/oskr-setup` workspace bootstrap skill
   - `init` v2: adopt-existing-repo mode + backend choice — *folds #16*
   - dev-vs-installed plugin toggle — *relates #17*
4. **Brain (`hjarne`)** — lift Solvej's Karpathy `raw→distill→wiki` pattern; loose research-output
   coupling (research-session optionally registers a pointer). *research: brain design. folds #7*
5. **Clients — mixed-backend workspace** — the DoD proof; depends on Areas 2 + 3 + 7.
   - Onboard **`sluice`** on Forgejo (new project → board provisioned via the Forgejo backend)
   - Onboard **`coremyotherapy`** on GitHub (adopt-existing, ported from gh-oskr) — *folds #16's adopt path*
   - Drive a real issue end-to-end through the pipeline on **each** backend
6. **Learning domain (`teach`)** — depends on Area 3 (needs the workspace skeleton to host a sandboxed
   learning workspace); independent of the backend adapter (teach never touches a board).
   - Adopt `teach` as the `learning` domain in its own managed workspace (no board/CWD collision)
   - Produce a first lesson end-to-end; extract its techniques (learning-records-as-ADRs, FORMAT compression)
7. **Pipeline redesign** — replace the current per-issue intake with the **ability/stage/gate** pipeline
   (grill→PRD/Area→decompose→per-task plan→execute→merge→cleanup). Depends on Area 2's create/link/deps
   primitives; gates the Area 5 DoD proof. *Design: `docs/design/pipeline-redesign.md`. folds #32.*
   - New front-end skills: `ground`, `grill-scope`, `shape-prd`, `decompose`
   - Vendor `deep-research`; add `hjarne` + `code-exploration` abilities
   - Column reshape (retire Research/Needs Input, add Scoping; cleanup off Done)
   - Soften plan-approval; wire the autonomous queue (`touches:` serialization, normalized blocked-by)

## Parked (future Epochs — explicitly NOT v1)

- **Epoch: Skills adoption (remainder)** — from the [skills audit](../research/2026-06-22-mattpocock-skills-audit.md):
  `diagnosing-bugs` agent (unblocks #15), `tdd` reference, two-axis review, `decision-mapping`.
  *(The ingestion front-end — grilling / PRD / `to-issues` — is no longer parked; it moved into v1 as
  Area 7.)*
- **Existing parked issues:** #6 cross-project dispatch, #8 non-coding validation, #10 workflow shapes,
  #19 Orca spike, and others — each gets an Epoch when reached.

## Scoping decisions (to prevent drift)

- **Two clients, two backends** — `sluice` (Forgejo, new) + `coremyotherapy` (GitHub, adopted)
  deliberately exercise a **mixed-backend workspace** — the strongest v1 proof of the adapter.
- **Forgejo AND GitHub are both v1** — the mixed workspace requires both backends working side by side.
- **Brain AND learning (teach) are v1** — both are named pillars of the from-zero workspace.
- **Cross-project dispatch (#6) is parked** — v1 runs two clients but each on its own board; one loop
  *arbitrating across* projects (shared budget/priority) is a later scaling concern.
- **The intake→delivery redesign is v1** (Area 7) — pulled in 2026-06-26 (#32). The DoD now proves
  client work runs through the *redesigned* pipeline, not just the old one. This reverses the earlier
  "richer ingestion is post-v1" call; the debugger and the rest of skills-adoption stay parked.

## Context map — start here per Area

A cleared-context session can cold-start any Area from these sources (in-repo unless marked *external*):

- **All areas:** `docs/design/platform-reframe.md` (master design) · `docs/design/task-tracking-model.md` ·
  this roadmap · memory `oskr-v1-roadmap` + `oskr-platform-reframe`.
- **#26 Backend adapter:** `docs/research/2026-06-22-forgejo-backend-capability.md` (endpoints,
  scoped-label mapping, the 7 invariants) · the `BACKEND:` section of `bin/harness-lib.sh` (the GitHub
  functions a Forgejo backend must mirror) · `tests/scripts/` (gh-shim + how to test the seam).
- **#27 Workspace & setup:** platform-reframe.md (two-tier config, setup-skill split, state→`.oskr/`,
  dev/installed toggle) · `skills/init/SKILL.md` is the template · issues #16, #17.
- **#28 Brain (hjarne):** *external* `../Solvej` — its `README.md` defines the Karpathy
  raw→distill→wiki pattern to lift · issue #7.
- **#29 Clients (mixed):** *external* `../squirrlylabs/WORKSPACE.md` — the registry of clients
  (sluice, coremyotherapy) + migration sequence · issue #16 (adopt-existing path).
- **#30 Learning (teach):** vendored source `docs/reference/mattpocock-skills/skills/productivity/teach/`
  (SKILL.md + FORMAT files) · audit `docs/research/2026-06-22-mattpocock-skills-audit.md`.
- **#32 Pipeline redesign (Area 7):** `docs/design/pipeline-redesign.md` (ability/stage/gate design,
  the three gates, the altitude contract, the #26 create/link dependency) · memory `oskr-pipeline-redesign`.
- **#33 Skill-creation meta-skill:** `docs/reference/mattpocock-skills/skills/productivity/writing-great-skills/`
  + `docs/reference/mattpocock-skills/docs/invocation.md` (user-invoked vs model-invoked).
