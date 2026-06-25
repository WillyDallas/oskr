# oskr as a developer workspace platform — architecture reframe

**Date:** 2026-06-22 · **Status:** design, pre-implementation

oskr is moving from a single-project, GitHub-only delivery harness to **the AI entrypoint for a
developer's whole working life** — one plugin that manages many projects, self-hosted services, a
dev knowledge brain, and learning, across GitHub *and* self-hosted Forgejo. This note records the
settled decisions and the design that follows from them.

## Decisions (settled)

| # | Decision | Rationale |
|---|---|---|
| 1 | **Backend abstraction, not a fork.** One plugin; GitHub Projects v2 and Forgejo are interchangeable backends behind a board-operation interface. | The `bin/` scripts are already a de-facto seam. A fork (`oskr-forgejo`) means two codebases that drift forever — contradicting the one-entrypoint vision. Forgejo as the *second* backend is what proves the seam is real. |
| 2 | **`hjarne` = dev brain**, built by lifting Solvej's Karpathy LLM-wiki pattern. **Solvej stays personal/separate.** | Solvej (`raw/` → agent distills → `wiki/`, `log.md`, `profile/constraints.md` hard-filter) is a working reference implementation. Reuse the pattern, don't entangle the vaults. |
| 3 | **`teach` is adopted as the `learning` domain**, run in its own managed workspace. | The super-folder model makes teach's "CWD == workspace" assumption native rather than a collision (see [skills audit](../research/2026-06-22-forgejo-backend-capability.md) sibling discussion). |

## The workspace model

The **workspace** (`willy/squirrlylabs`) is the super-folder / control plane — "the operator's home
base where the harness is driven from" (`squirrlylabs/WORKSPACE.md`). It is augmented in place, never
moved. oskr-the-plugin lives at `projects/oskr` *as a managed project* and is consumed by the
workspace — a deliberate self-hosting recursion.

```
squirrlylabs/                  # workspace = control plane (a git repo)
├── .oskr/                     # workspace state (NEW — see "State location")
│   ├── config.json            # global config: backends, defaults
│   └── registry.json          # the projects/domains registry
├── projects/                  # managed project repos (gitignored — separate repos)
│   ├── oskr/                  # oskr develops itself here
│   ├── sluice/
│   └── …
├── hjarne/                    # dev brain (lifts Solvej's pattern)
├── learning/<topic>/          # teach workspaces
├── mail/  proxy/  git/        # self-hosted services (already live)
```

Two config tiers, mapping onto the two setup skills:

- **Global / workspace tier** — `squirrlylabs/.oskr/config.json` + `registry.json`. Backends and
  credentials, default base branch, the list of managed projects/domains.
- **Project tier** — today's `harness-config.json`, one per project, now carrying a `backend`
  discriminator (`github` | `forgejo`).

### State location (a fix the recursion forces)

Today `init` writes its registry to `$HOME/WillyDev/oskr/repos/projects.json` — *inside the plugin
source*. That's backwards. **The plugin must be stateless** (it gets installed/replaced); **all state
belongs to the workspace** (`.oskr/`). This is a prerequisite for the recursion to work and for a
clean global/project split.

### Dev-vs-installed plugin toggle (also forced by the recursion)

oskr lives at `projects/oskr` *and* is the plugin the workspace loads, so "I edited a skill" must not
silently change every workspace operation. Default to the **installed/pinned** plugin; when working
*on* oskr, launch with an explicit dev override (`--plugin-dir projects/oskr`). Deliberate, not
ambient. (Also: add `oskr` itself to the `WORKSPACE.md` registry — it's a managed project too.)

## The backend adapter

This is the keystone. Today the board layer is a **leaky seam**: `harness_move_issue()` is cleanly in
`harness-lib.sh`, but `find-item.sh`, `board-dispatcher.sh`, and `init/SKILL.md` embed `gh api graphql`
**inline**. The adapter work is therefore two steps:

1. **Consolidate** every `gh api graphql` call behind a backend interface in `harness-lib.sh`. The
   GitHub backend becomes a refactor-in-place. This also makes the board layer testable — worth doing
   regardless of Forgejo.
2. **Implement** a `forgejo` backend of that same interface.

### The interface (canonical board operations)

```
backend_find_item    <issue>                  → item handle
backend_read_column  <item>                    → canonical column slug
backend_move         <item> <column-slug>      → (atomic)
backend_read_field   <item> <field>            → value      # priority|size|category
backend_set_field    <item> <field> <value>
backend_list_column  <column-slug> [filters]   → issues
backend_create_issue <title> <body> [labels]   → issue
```

`harness-config.json` already has the hooks: `workflow.column_names` (slug→display-name) and
`workflow.status_field_name`. A `backend` discriminator slots in alongside them; the interface speaks
canonical slugs (`in_progress`), each backend resolves them.

### Backend mappings

| Canonical | GitHub Projects v2 | Forgejo |
|---|---|---|
| Status column | single-select Status field option | exclusive scoped label `status/<col>` |
| Priority/Size/Category | single-select fields | exclusive scoped labels `priority/* size/* category/*` |
| move column | `updateProjectV2ItemFieldValue` mutation | `POST …/issues/{i}/labels` (exclusivity auto-evicts old) |
| board item | distinct project item (`PVTI_…`) | the issue itself |
| transport | `gh api graphql` | raw REST `/api/v1` + PAT |

The Forgejo design is fully verified and detailed — endpoints, auth, invariants — in
[`docs/research/2026-06-22-forgejo-backend-capability.md`](../research/2026-06-22-forgejo-backend-capability.md).
Headline: native Forgejo kanban has **no REST API**, so columns are **exclusive scoped labels**, which
give server-enforced single-select that maps 1:1 onto the GitHub fields.

## Setup skills: split in two

`/oskr-setup` and `init` are different jobs at different tiers. Onboarding happens many times; workspace
bootstrap happens once.

- **`/oskr-setup`** *(new — workspace tier, run once)*: establish the control plane. Gather global
  config (backends + credentials for GitHub and/or Forgejo), create the skeleton (`projects/`,
  `hjarne/`, `learning/`, `.oskr/`), stand up the brain, register the workspace. End by handing off to
  ↓ for project #1.
- **`init` v2** *(exists, ~80% there — project tier, repeatable)*: onboard one project. Two gaps to
  close: the **adopt-existing-repo** mode (currently fresh-repo-only — `oskr#16`) and the **backend
  choice** (`github` | `forgejo`, writing the discriminator into `harness-config.json`). Brings a repo
  in via move / clone / new.

**Test `/oskr-setup` against a throwaway clean workspace dir, then run the real thing against
`squirrlylabs`** — which holds live mail + git infra you don't want a skill-under-development touching.

## Brain integration (loosely coupled)

`hjarne` lifts Solvej's pattern: `raw/` (sources, agent never rewrites) → agent distills → `wiki/`,
with `log.md` and a `profile/` hard-filter. If research outputs should point into the brain, `hjarne`
must exist with a known structure before delivery skills run — so **brain-before-projects is a real
dependency in `/oskr-setup`'s ordering.** Keep coupling loose: `research-session` writes
`docs/research/` *and optionally* registers a pointer in the brain, so a project with no brain still
works.

## Migration sequence (reconciles `WORKSPACE.md`)

0. **Consolidate the backend seam** in `harness-lib.sh` (GitHub adapter = refactor-in-place). *New
   prerequisite the original plan didn't name.*
1. **Two-tier config + state relocation** — `.oskr/` in the workspace; `backend` discriminator in
   `harness-config.json`.
2. **Forgejo adapter** — exclusive scoped labels; proves the seam. *(= WORKSPACE.md step 2, as adapter
   not fork. Autonomous dispatch loop stays deferred — human-triggered first.)*
3. **`/oskr-setup` + `init` v2** (adopt-existing + backend choice). **Issue-ingestion** can ride here,
   in parallel — it's in-domain today and doesn't block on the platform work.
4. **`hjarne` brain** (lift Solvej pattern), loosely coupled. *(∥ with 2–3 per WORKSPACE.md.)*
5. **Onboard Sluice** — first real Forgejo consumer; the end-to-end test.
6. **Port coremyotherapy** off gh-oskr.

## Open questions

- **Issue-ingestion shape:** which intake skill(s) to build — the audit flagged `to-issues`
  (plan→board issues, "tracer-bullet vertical slices"), `qa` (conversational bug→issue), and `triage`
  (front-door classification). Pick the first slice.
- **Brain coupling depth:** exactly how/when research artifacts register pointers into `hjarne`.
- **Label taxonomy scope:** org-level (`squirrlylabs` org, defined once) confirmed as the default.
