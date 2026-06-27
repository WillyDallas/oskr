# Backend capability — GitHub + Forgejo, for the oskr #26 adapter

**Date:** 2026-06-27
**Supersedes/extends:** [docs/research/2026-06-22-forgejo-backend-capability.md](2026-06-22-forgejo-backend-capability.md)
**Purpose:** Ground both backends of oskr's create/link/deps seam (#26) in verified API facts, and settle the canonical-store question.
**Verified against:** Forgejo through v15.0.3 (2026-06-10) + LTS v11.0.15; Gitea 1.27.0+dev live swagger; GitHub.com / GHEC changelogs through 2026-03.

## What changed since 2026-06-22

The prior doc covered the **board/move** seam (label-driven columns) and proved Forgejo has **no Projects REST API**. Both findings still hold. This doc adds the **create/link/deps** seam and overturns one design assumption:

1. **`*_read_deps` is native on BOTH backends, not body-parse on GitHub.** GitHub shipped a first-class issue-dependencies REST API (GA 2025-08-21); Forgejo has had one since v1.20 (2023-07). The `## Blocked by` prose-parse path is retired.
2. **Parent/child is the ONLY primitive that forces body-parse — and only on Forgejo.** Forgejo/Gitea have no sub-issue feature in any release or dev branch. GitHub has native sub-issues (GA 2025-04-09).
3. **The "canonical-store-in-issue-body" default flips** to native-as-source-of-truth, body-as-human-mirror, with body-canonical surviving only as a narrow exception for Forgejo hierarchy.

## Capability matrix (the #26 seam)

| Primitive | GitHub | Forgejo | Canonical store |
|---|---|---|---|
| `*_create_issue` | Native `POST /issues` + Project v2 via GraphQL | Native `POST /api/v1/.../issues` + scoped labels | native both |
| `*_link_parent` | **Native sub-issues** (GA) | **No native — body-parse forced** (+ dep-edge backstop) | GH native / FJ body |
| `*_list_children` | **Native** `GET .../sub_issues` | **No native — body-parse forced** | GH native / FJ body |
| `*_read_deps` (blocked-by) | **Native dependencies** (GA) | **Native dependencies** (GA) | **native both** |

Reads on Forgejo's forced body-parse are deterministic (raw markdown always returned); only writes carry integrity risk, bounded to an adapter-owned region.

## Forgejo — native primitives (use these, drop the parse)

### Issue dependencies / blocked-by — NATIVE, GA since v1.20

The primitive `*_read_deps` wants is the **blocked-by** read:

- `GET /repos/{owner}/{repo}/issues/{index}/dependencies` — *"all issues that block this issue"* = the blocked-by edges. **This is the one to use.**
- `GET /repos/{owner}/{repo}/issues/{index}/blocks` — the **reverse** (issues this one blocks). Do **not** use `/blocks` for blocked-by.
- Mutations: `POST` / `DELETE` on either path; body `IssueMeta { owner: string, repo: string, index: int64 }` — **cross-repo capable**.

**Read shape:** `200` returns an array of full `Issue` objects. On Forgejo this is `IssueListWithoutPagination` — the whole set comes back in one array, no Link-header paging to chase. Each element carries load-bearing fields the adapter reads directly: `number` (the index, use as edge id), `state` (`open`|`closed`), `title`, `html_url`, `repository` (`{id, name, owner, full_name}`), `pull_request` (non-null if the dep is a PR). So **open-blocker count and cross-repo target are free from the edge list** — no extra fetch, no prose.

**Versions:** REST endpoints shipped in **Gitea 1.20.0 / Forgejo 1.20.0 (2023-07)** and are present in **every deployable line (7.x–15.x)**. Only long-EOL Forgejo 1.18/1.19 lack the REST surface (they have the DB feature). Confirmed by parsing the live Gitea demo swagger (1.27.0+dev) and the Forgejo `forgejo`-branch swagger template — identical paths/operationIds.

**Gate (must enforce):** issue dependencies are a per-repo unit toggle (`enable_issue_dependencies`; admin default `DEFAULT_ENABLE_DEPENDENCIES=true`; cross-repo via `ALLOW_CROSS_REPOSITORY_DEPENDENCIES`). If disabled, the endpoints 404/empty. **Bootstrap must assert the dependencies unit is enabled** on managed repos, alongside the exclusive-label assertion.

### Exclusive scoped labels — NATIVE, GA since v1.19 (unchanged, still true)

Single-select board fields (status/priority/size/category) ride on scoped labels (`scope/value`, scope = text before the last `/`) created with `exclusive:true`. Eviction is enforced at the **models layer** (`RemoveDuplicateExclusiveIssueLabels` inside `NewIssueLabel`, in a `db.WithTx`), so it applies to the REST path, not just the UI. Assigning one label in a scope auto-evicts the prior same-scope label — true single-select. (Full board mapping + POST-vs-PUT invariants: see the 2026-06-22 doc, which still stands.)

- Create label: `POST /repos/{owner}/{repo}/labels` (or `/orgs/{org}/labels`) — `CreateLabelOption { name, exclusive, color, description, is_archived }`.
- Assign (additive, triggers eviction): `POST /repos/{owner}/{repo}/issues/{index}/labels` — `IssueLabelsOption { labels: []id|name }`.
- Edit: `PATCH .../labels/{id}` (`EditLabelOption.exclusive *bool`; path param is the numeric **ID**).

## Forgejo — the genuine gaps (body-parse forced)

### No parent/child hierarchy — in any version

The `Issue` schema has no `parent`, `children`, `sub_issues`, `tracked_in`, or summary field — verified by inspecting both swaggers. The only issue-to-issue relation is the dependency/blocking DAG above, whose semantics are *blocks/depends*, not *contains*. go-gitea#13642 (Hierarchical issue tracking) is still an **open proposal**; no merged PR in Gitea or Forgejo. **Hierarchy on Forgejo is a convention the adapter maintains.**

### No structured task-list

The Issue object exposes `body` as one opaque string. The UI "3 of 5" count is computed server-side by regex (`GetTasks` / `GetTasksDone` over `issue.Content`, patterns `^\s*[-*]\s\[[\sxX]\]\s.`) **at render time and never returned by REST**. To list umbrella children you must parse the raw body. Good news: `GET /repos/{owner}/{repo}/issues/{index}` returns **raw unrendered markdown deterministically**, so reads are stable; bad news: zero referential integrity (human edits, renumbering, whitespace, cross-repo refs silently break links).

### Hardening the forced parse (the maintainer's distrust is correct here — mitigate, don't pretend)

1. **Own a machine-delimited region.** Write the dash-bracket-`#N` child list inside HTML-comment-fenced markers the adapter owns; put a parent marker / `## Parent` on each child. Parse only inside the fence, so human edits elsewhere can't corrupt the relation. Write-integrity risk is bounded to the owned region.
2. **Backstop with a native dependency edge.** On link, also `POST .../issues/{parent}/dependencies` (IssueMeta). This is structured, API-queryable, and survives body edits — use it to **reconcile/repair** the body markers. Its semantics are blocks, not contains, so it's a redundant integrity check, never the displayed hierarchy. Gate on `enable_issue_dependencies`; degrade to body-only if disabled.
3. **`area/*` labels** are a coarse many-to-one index for cheap `*_list_children`-by-area queries (`GET issues?labels=area/x`), **not** an authoritative parent pointer.

## GitHub — native parity (body-parse needed for neither hierarchy nor deps)

### Sub-issues (parent/child) — NATIVE, GA 2025-04-09

- `GET /repos/{owner}/{repo}/issues/{issue_number}/sub_issues` (list children)
- `POST .../sub_issues` body `{ sub_issue_id, replace_parent? }` (add)
- `DELETE .../sub_issue` body `{ sub_issue_id }` (remove)
- `PATCH .../sub_issues/priority` body `{ sub_issue_id, after_id|before_id }` (reorder)
- `GET .../parent` (backlink, added 2025-09-11)
- GraphQL: `addSubIssue` / `removeSubIssue` / `reprioritizeSubIssue`; `Issue.subIssues`, `Issue.parent`.

**GOTCHA:** `sub_issue_id` is the issue **DATABASE ID (int64, ~10 digits), NOT the issue number.** Sub-issues auto-inherit the parent's Project + Milestone; cross-org supported.

### Issue dependencies / blocked-by — NATIVE, GA 2025-08-21 (separate from sub-issues)

- `GET /repos/{owner}/{repo}/issues/{issue_number}/dependencies/blocked_by` (what blocks this)
- `POST .../dependencies/blocked_by` body `{ issue_id }`; `DELETE .../dependencies/blocked_by/{issue_id}`
- `GET .../dependencies/blocking` (reverse)
- GraphQL: `addBlockedBy` / `removeBlockedBy`. Search: `is:blocked` / `is:blocking`.

**This is a distinct first-class relationship — not sub-issue deps, not body text.** `issue_id` = database id. Limits: **≤50 issues per relationship per direction**; **EMU cross-enterprise `addBlockedBy` can return FORBIDDEN** — fall back to body mirror in that edge case.

### Projects v2 — GraphQL is GA; REST is preview

Membership + single-select fields: GraphQL `addProjectV2ItemById(input:{projectId, contentId})` → `updateProjectV2ItemFieldValue(input:{projectId, itemId, fieldId, value})` (two calls; can't add+set in one). **Both GA — use this for production writes.** The projectsV2 REST API (`GET|POST /orgs/{org}/projectsV2/{number}/items`, `.../fields`) is **public preview since 2025-09-11** (`X-GitHub-Api-Version: 2026-03-10`) — do not depend on it.

### Task-lists — body-text only (same as Forgejo)

Markdown `- [ ]` checkboxes render a progress count but have no enumerate/mutate API; the experimental `[tasklist]` block was sunset in favor of sub-issues. On GitHub, "task-list" = pure body-parse, and its structured replacement is sub-issues.

### Enterprise Server caveat

GHES ships these on a lag (sub-issues ~3.16–3.17, dependencies later, **not pinned in changelogs**). Feature-detect the GHES minor and fall back to body-mirror if the target predates the feature.

## The canonical-store rule, revised

> **Native features are the source of truth wherever they exist and are GA. The issue body is a generated, human-readable MIRROR. Body-parse is the canonical store for exactly one case: Forgejo parent/child hierarchy (`*_link_parent` / `*_list_children`).**

Rationale: GitHub has native + GA for hierarchy AND dependencies — making body canonical there silently discards structured state the GitHub UI/board already render (sub-issue progress, dependency badges, Project fields). Forgejo needs body-canonical only for containment; its dependencies and single-select fields are native. The old body-canonical-everywhere rule was a Forgejo-shaped concession that over-generalized.

The dispatcher rule still holds and is now easier to honor: **never rank or gate on a field only one backend has.** With deps native on both, the `zero-open-blockers` auto-grab gate reads typed edge `state` on both backends — never from English prose.

## Endpoint quick-reference

| Op | GitHub | Forgejo |
|---|---|---|
| create issue | `POST /repos/{o}/{r}/issues` | `POST /api/v1/repos/{o}/{r}/issues` (labels[] = IDs) |
| add to board | GraphQL `addProjectV2ItemById` + `updateProjectV2ItemFieldValue` | `POST .../issues/{i}/labels` (exclusive scoped) |
| link parent | `POST .../issues/{n}/sub_issues {sub_issue_id=DB id}` | body fence + backstop `POST .../issues/{i}/dependencies` |
| list children | `GET .../issues/{n}/sub_issues` | parse umbrella body (raw markdown) |
| read deps (blocked-by) | `GET .../issues/{n}/dependencies/blocked_by` | `GET .../issues/{i}/dependencies` |
| write dep | `POST .../dependencies/blocked_by {issue_id=DB id}` | `POST .../issues/{i}/dependencies` IssueMeta{owner,repo,index} |

**ID model:** GitHub sub-issues + dependencies take the **database id (int64)**; resolve number→id. Forgejo dependency writes take `IssueMeta{owner,repo,index}` where `index` = the issue number.

## Bootstrap & invariants (additions to 2026-06-22)

1. Assert the **issue-dependencies unit is enabled** on every managed Forgejo repo (else `/dependencies` 404s and `*_read_deps` silently degrades). Assert `ALLOW_CROSS_REPOSITORY_DEPENDENCIES` if cross-repo deps are used.
2. (Carried) Create every taxonomy label with `exclusive:true`; periodically re-assert. Use `POST` (not `PUT`) for single-field moves. Maintain a name→ID label cache.
3. GitHub: gate native sub-issues/dependencies behind a version/feature probe for GHES; fall back to body-mirror when unavailable. Use GraphQL (not preview REST) for Project field writes.

## Auth

PAT, `Authorization: token <pat>`. Forgejo: `read:issue` for the dependency GET, `write:issue` for POST/DELETE — same token model as the label board ops; `write:repository` covers labels/milestones. GitHub: `gh api` with issues + projects scopes.

## Sources

**Forgejo / Gitea**
- Live Gitea swagger (1.27.0+dev, all six dependency/blocks paths; Issue schema has no parent/children): https://demo.gitea.com/swagger.v1.json
- Forgejo `forgejo`-branch swagger template (identical; no sub-issue paths): https://codeberg.org/forgejo/forgejo/raw/branch/forgejo/templates/swagger/v1_json.tmpl
- Dependency REST shipped in 1.20: https://blog.gitea.com/release-of-1.20.0/ · https://docs.gitea.com/api/1.20/
- Dependency feature origin (Gitea 1.6): https://github.com/go-gitea/gitea/pull/2531 · https://github.com/go-gitea/gitea/issues/2196
- Hierarchical issue tracking still open: https://github.com/go-gitea/gitea/issues/13642
- Exclusive scoped labels (PR + docs): https://github.com/go-gitea/gitea/pull/22585 · https://forgejo.org/docs/latest/user/labels/
- Task-list count is render-time regex: modules/structs/issue.go, models/issues/issue.go (GetTasks/GetTasksDone)
- Dependency config gates: https://docs.gitea.com/administration/config-cheat-sheet
- Version landscape (v15.0.3 / v11.0.15 LTS): https://codeberg.org/api/v1/repos/forgejo/forgejo/releases

**GitHub**
- Sub-issues REST (GA 2025-04-09): https://docs.github.com/en/rest/issues/sub-issues · https://github.blog/changelog/2025-04-09-evolving-github-issues-and-projects/
- Issue dependencies REST (GA 2025-08-21): https://docs.github.com/en/rest/issues/issue-dependencies · https://github.blog/changelog/2025-08-21-dependencies-on-issues/
- Projects v2 GraphQL: https://docs.github.com/en/issues/planning-and-tracking-with-projects/automating-your-project/using-the-api-to-manage-projects
- Projects v2 REST (preview 2025-09-11): https://docs.github.com/en/rest/projects/items · https://github.blog/changelog/2025-09-11-a-rest-api-for-github-projects-sub-issues-improvements-and-more/

## Repo creation (`backend_create_repo`)

**Headline:** Forgejo's and Gitea's `CreateRepoOption` / `GenerateRepoOption` are **field-for-field identical** at the verified versions — Forgejo has not diverged the repo-create API. So for *this* primitive there are **two backend classes, not three: `github` vs `gitea-family`.** (The board seam still treats `forgejo` as its own impl; the collapse is specific to repo-create.)

### Endpoints (all three paths exist on both, identical templates)

| Purpose | GitHub | gitea-family |
|---|---|---|
| Create for user | `POST /user/repos` (NOT GitHub-App-enabled) | `POST /user/repos` |
| Create in org | `POST /orgs/{org}/repos` | `POST /orgs/{org}/repos` |
| From template | `POST /repos/{template_owner}/{template_repo}/generate` | same (gitea: `owner` **required** in body) |
| Server-side import | `POST /repos/{owner}/{repo}/import` (legacy, retiring) | `POST /repos/migrate` (first-class) |

### Canonical param set — only `name` is ever required

`{ name (req), owner, private, description, auto_init, gitignore, license, default_branch }`

| Canonical | GitHub field | gitea-family field |
|---|---|---|
| `private` | `private` | `private` |
| `description` / `auto_init` | same | same |
| `gitignore` | `gitignore_template` (single) | `gitignores` (comma list) |
| `license` | `license_template` | `license` |
| `default_branch` | **— not at create; PATCH after first commit** | `default_branch` (at create) |

**Two caveats to encode:** (1) `default_branch` is gitea-family-only at create → on GitHub, reconcile via `PATCH /repos/{owner}/{repo}` post-create. (2) Use boolean `private` as canonical, not GitHub's `visibility` string (`internal` is enterprise-only, absent on gitea-family). Every non-canonical field (GitHub: `has_issues`/merge-policy/`team_id`; gitea: `issue_labels`/`trust_model`/`object_format_name`/`readme`) is optional and silently dropped or routed to a post-create PATCH — **never required by the dispatcher.**

### Three onboarding modes

- **create-new** — `POST …/repos`. Then provision board (GitHub: Projects v2 GraphQL link; Forgejo: exclusive scoped labels).
- **clone-then-push** — create empty (`auto_init:false`) + client-side `git push --mirror`; gitea-family also offers server-side `POST /repos/migrate`.
- **adopt-existing** — **no create call**: `GET /repos/{owner}/{repo}` to validate → register → provision board only.

### Auth/scopes

GitHub: classic `public_repo` (public) / `repo` (private), or fine-grained **Administration: write**; header `Authorization: Bearer <token>`. gitea-family: `write:repository` (user/template) or `write:organization` (org); header `Authorization: token <token>`; use a PAT (OAuth2-provider tokens bypass scopes).

**Sources:** GitHub `docs.github.com/en/rest/repos/repos` (v2022-11-28) + `github/rest-api-description`; Gitea live swagger `demo.gitea.com/swagger.v1.json` (1.27.0+dev); Forgejo `forgejo`-branch swagger template (`CreateRepoOption`/`GenerateRepoOption`).