# Forgejo backend capability — research for the oskr backend adapter

**Date:** 2026-06-22
**Purpose:** Ground the Forgejo backend of oskr's board-operation adapter in verified API facts.
**Verified against:** Forgejo through v15.0.3 (2026-06-10) and Gitea 1.27.0+dev live swagger.

## Verdict

**Forgejo's native Projects/kanban board has no REST API, in any released version or even
unreleased `forgejo`-branch code.** The board exists UI-only; column membership lives in a
`project_issue` DB table (`ProjectColumnID`), reachable only through the web UI. The implementing
PR ([forgejo#9384](https://codeberg.org/forgejo/forgejo/pulls/9384)) is **closed, unmerged**
(`merged_at=null`, last touched 2026-06-16); the work is only at the proposal stage
([forgejo discussions#466](https://codeberg.org/forgejo/discussions/issues/466),
[gitea#36824](https://github.com/go-gitea/gitea/issues/36824), opened 2026-03-04, open).

→ **The adapter must drive board state through issue labels.** Do not build against the proposed
`/api/v1/projects` endpoints. Revisit only if that API actually merges and ships.

## The design: four exclusive scoped-label sets

Forgejo/Gitea **scoped labels** (name contains `/`; scope = text before the last `/`) created with
the **`exclusive` flag** are enforced at the models layer (which backs the REST API): attaching one
label in a scope **automatically removes any other label in the same scope**
([gitea#22585](https://github.com/go-gitea/gitea/pull/22585),
[Forgejo labels docs](https://forgejo.org/docs/latest/user/labels/)). This gives true single-select
semantics for free.

| oskr field | Forgejo representation (exclusive scope) |
|---|---|
| Status (9 columns) | `status/backlog` … `status/done` |
| Priority | `priority/p1` `priority/p2` `priority/p3` |
| Size | `size/xs` … `size/xl` |
| Category | `category/feature` `category/bug` `category/chore` `category/spike` `category/docs` |

An issue ends up with at most one label per scope → exactly single-select per field, **mapping 1:1
onto GitHub Projects v2's Status + three single-select fields** behind a common interface. Define the
taxonomy once at **org level** (`squirrlylabs` org) so it's identical across all repos.

## Adapter operations (stable issues + labels REST API only)

Base path `/api/v1`. The issue **is** the board item — there is no separate card object.

| Operation | Call |
|---|---|
| find board item | `GET /repos/{owner}/{repo}/issues/{index}` (no separate item id) |
| read current column / fields | `GET …/issues/{index}` → scan labels by scope prefix |
| **move to column** | `POST …/issues/{index}/labels` `{"labels":["status/<col>"]}` — exclusivity auto-evicts the old `status/*`; one atomic call |
| set a custom field | `POST …/issues/{index}/labels` with the new scoped label (same auto-evict) |
| list issues in a column | `GET …/issues?labels=status/<col>&type=issues&state=open` |
| create issue | `POST …/issues` with `labels[]` (initial `status/backlog`) |

**Auth:** PAT, header `Authorization: token <pat>`. A repo-scoped least-privilege token only needs
`write:issue` + `write:repository` (labels/milestones fall under these). Mint via
`POST /api/v1/users/{username}/tokens`. ([token scopes](https://forgejo.org/docs/latest/user/token-scope/))

**Use raw REST (curl), not the `tea` CLI.** `tea` is fine for create/list/close but doesn't expose
the `exclusive` flag and only does label add/remove (not exact-set) — raw REST gives the deterministic
control clean column moves need. (This mirrors how the GitHub backend already uses HTTP via `gh api`.)

## Invariants the adapter must enforce

1. **Exclusivity is application-level, not a DB constraint.** Every taxonomy label MUST be created
   with `exclusive:true`; a bootstrap step should create them and periodically assert it. A
   non-exclusive status label silently breaks the one-column invariant.
2. **`POST` (add) vs `PUT` (replace).** Use `POST` for single-field/column changes (exclusivity
   strips the old value). `PUT` replaces the *entire* label set — it would wipe priority/size/category
   too; only use it when intentionally rewriting all labels.
3. **"At most one," not "exactly one."** An issue can have zero `status/*` labels (created outside
   oskr, or label removed). Treat "no status label" as an explicit uncolumned state; always apply
   `status/backlog` on create.
4. **Labels cannot be set via `PATCH` issue** — `EditIssueOption` has no labels field. Column moves go
   through the dedicated label endpoints only. (State open/closed *is* settable via PATCH; optionally
   flip to `closed` at the Done column. Milestone *is* settable via PATCH — reserve milestones for
   sprints/releases, never for columns.)
5. **Create takes label IDs (ints); issue-label endpoints take names (strings).** Maintain a
   name→ID cache (`GET /labels`).
6. **PRs carry labels too** — always filter `type=issues` when listing columns.
7. **The native kanban board will NOT reflect label state** (no API to populate it). Accept this;
   don't couple adapter correctness to the UI board.

## Key sources

- Forgejo labels (scoped + exclusive): https://forgejo.org/docs/latest/user/labels/
- Scoped-label enforcement at models layer: https://github.com/go-gitea/gitea/pull/22585
- Live Gitea OpenAPI (no project paths): https://demo.gitea.com/swagger.v1.json
- Forgejo branch swagger (no project paths): https://codeberg.org/forgejo/forgejo/raw/branch/forgejo/templates/swagger/v1_json.tmpl
- Project API still a proposal: https://codeberg.org/forgejo/discussions/issues/466 · https://github.com/go-gitea/gitea/issues/36824
- Closed implementing PR: https://codeberg.org/forgejo/forgejo/pulls/9384
- API usage / auth / token scopes: https://forgejo.org/docs/latest/user/api-usage/ · https://forgejo.org/docs/latest/user/token-scope/
