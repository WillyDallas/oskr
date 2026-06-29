# The blacksmith — oskr's backend adapter

**Status:** shipped (#26, PR #41) · **Capability research:** [2026-06-27-backend-capability.md](../research/2026-06-27-backend-capability.md)

The **blacksmith** is oskr's forge-agnostic board/issue operation layer. An agent or skill calls a
blacksmith verb; the verb dispatches to the right *forge* — GitHub Projects v2 or self-hosted
Forgejo — based on the project's config. Board structure (Epoch/Area/Task, the columns, the
gen-eval workflow) is **not** baked into the blacksmith: it exposes neutral primitives, and skills
compose structure on top.

> The blacksmith works at whichever **forge** a project is configured for. "Forge" is the backend
> platform (GitHub/Forgejo); the blacksmith is the tool that operates it.

It lives entirely in [`bin/harness-lib.sh`](../../bin/harness-lib.sh).

## Dispatch & config

Each project's `harness-config.json` carries a `forge` discriminator (`github` | `forgejo`,
default `github`). A public verb is a one-line dispatcher:

```sh
blacksmith_move_issue() { _blacksmith_dispatch move_issue "$@"; }
# _blacksmith_dispatch reads `forge`, then calls _blacksmith_<forge>_<op>
```

So `_blacksmith_github_move_issue` and `_blacksmith_forgejo_move_issue` are the two renderings;
calling an op a forge doesn't implement fails loudly. Config is **ambient** — the scripts find
`harness-config.json` from `$PWD` (or `$HARNESS_CONFIG`), exactly like `git` reads `.git/config`.
A skill never passes the forge; it just calls the verb and the project's config selects the backend.

## The operation set

| Verb | GitHub | Forgejo |
|------|--------|---------|
| `create_issue` | REST create + add to Project v2 (GraphQL) | REST create + `status/backlog` label |
| `move_issue` | `updateProjectV2ItemFieldValue` | exclusive `status/<slug>` label (server auto-evicts the old one) |
| `issue_status` / `item_status` | Project Status field | read `status/*` label → display name |
| `find_item` / `item_issue_number` | project item id (`PVTI_…`) | the issue number *is* the item |
| `list_board` | Project v2 items query | issues + label synthesis |
| `read_deps` | native dependencies API | native dependencies API |
| `link_parent` / `list_children` | native sub-issues | body-fenced child checklist |
| `count_actionable` / `archive_item` | Project query / archive card | label filter / remove `status/*` |
| `ensure_label` / `issue_add_label` / `issue_comment` | `gh` | REST |

Every op returns the **same neutral shape** regardless of forge — e.g. `list_board` →
`{ total, items:[ {number,title,status,priority,category,createdAt,body,assignees,comments,labels,blocking,blockedBy} ] }`,
`read_deps` → `[ {number,state,title,repository,url} ]`. `status`/`priority`/`category` are column
display names, resolved identically by both forges via config.

## Canonical-store rule

**Native features are the source of truth wherever they're GA; the issue body is a generated
mirror.** The lone exception: Forgejo has no native sub-issues, so parent/child containment is
stored as an adapter-owned, HTML-comment-fenced checklist in the parent body (parsed only inside
the fence). Dependencies are native on *both* forges, so blocked-by is read as typed edges with
`state` — never parsed from prose. And the dispatcher must **never gate on a field only one backend
has**: Forgejo `list_board` reports `blocking: 0` (ranked on as a tiebreak, never gated), so
parallel auto-pickup can't silently break on Forgejo.

## The seam guard

`tests/scripts/test_backend_no_inline_gh.sh` enforces that **all** forge calls live in
`harness-lib.sh`: no other `bin/` script may make an inline `gh` board call or a `curl` to a forge
REST API (`/api/v1`). Callers go through the public `blacksmith_*` verbs only.

## Auth

- **GitHub** — `gh` (the user's `gh auth`).
- **Forgejo** — a PAT in `$FORGEJO_TOKEN`, passed to `curl` via a stdin config so the secret never
  appears on argv / in `ps`. Base URL + owner/repo come from `harness-config.json`'s `.forgejo`
  block. The token belongs to the workspace (e.g. a gitignored `.env`), never the plugin repo.

## Testing

- **Hermetic** (`tests/scripts/`, runs in CI): a `gh`-shim and a `curl`-shim replay canned fixtures;
  the suite covers dispatch, parsing, and neutral-shape synthesis offline. No network, no creds.
- **Live smoke** (opt-in, `bin/smoke/forgejo-roundtrip.sh`): drives a full round-trip against a real
  Forgejo repo through the public verbs — the acceptance gate. Needs `$FORGEJO_TOKEN` + a throwaway
  repo whose exclusive `status/*` labels are provisioned.

## Adding a third backend

1. Implement `_blacksmith_<forge>_<op>` for each verb, returning the neutral shapes.
2. Add a transport helper (the `gh`-style or `_blacksmith_forgejo_curl`-style pattern).
3. Extend the relevant shim + fixtures for hermetic coverage; add a live smoke.
4. Set the `forge` discriminator to select it. No caller or skill changes.

## Not the blacksmith's job: provisioning

Creating the repo and the board UI (the GitHub Project v2, or the exclusive Forgejo label set) is a
**manual setup walkthrough** owned by the `init` / `/oskr-setup` work (#27), not a runtime
primitive — the Forgejo board UI has no REST API, and one-time setup is better guided than scripted.
