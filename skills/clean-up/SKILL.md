---
name: clean-up
description: Clear verified-Done cards off the board and reconcile docs after merge — one system cluster per run, human-approved.
disable-model-invocation: true
allowed-tools: Bash(git *) Bash(jq *) Bash(source "${CLAUDE_PLUGIN_ROOT}/bin/harness-lib.sh"*) Bash("${CLAUDE_PLUGIN_ROOT}/bin/find-item.sh"*) Bash("${CLAUDE_PLUGIN_ROOT}/bin/archive-item.sh"*) Bash("${CLAUDE_PLUGIN_ROOT}/bin/list-children.sh"*) Bash("${CLAUDE_PLUGIN_ROOT}/bin/sync-development.sh"*) Bash(mv docs/plans/*) Bash(mkdir *) Bash(tail *) Bash(date *) Agent AskUserQuestion Read Glob Grep Write Skill
---

**Stage 7** of the pipeline — the developer ritual you run by hand after merges land work in **Done**. It clears completed cards and brings documentation in line with what shipped, **one system cluster per run** (bounded cost, repeatable until Done is empty — run it again for the next cluster).

The flow is **plan → validate → human-approve → execute**. No board write, doc change, or brain write happens before the approval gate.

The headline rule is the **docs/brain split** (reference section below): every piece of knowledge the cluster surfaces routes to *exactly one* home — the brain or the repo. Read it before Phase 5.

## Setup

Runs from the base branch in the consumer repo (CWD holds `harness-config.json`). The neutral verbs (`blacksmith_list_board`, `blacksmith_issue_view`) read coordinates from there — no per-query owner/repo wiring.

## Preconditions

```bash
"${CLAUDE_PLUGIN_ROOT}/bin/sync-development.sh" clean-up
```

On exit 1, **stop** and tell the developer — cleanup decided against a stale tree can archive work that is not actually shipped.

Read prior-run state so this run does not re-litigate already-archived issues:

```bash
tail -30 logs/clean-up.log 2>/dev/null || echo "(no prior runs)"
```

## Phase 1: Seed and cluster

Read the Done column from the board (neutral shape — works on either backend):

```bash
source "${CLAUDE_PLUGIN_ROOT}/bin/harness-lib.sh" && blacksmith_list_board \
  | jq '[.items[] | select(.status == "Done")
         | {number, title, labels}] | sort_by(.number)'
```

The **seed** is the lowest-numbered Done card (the earliest work still on the board). Form the cluster two ways:

- **Seed is an Area umbrella** (`type/umbrella` label): the cluster is the umbrella **plus its Done children** — `"${CLAUDE_PLUGIN_ROOT}/bin/list-children.sh" <umbrella>`, keep those with `state == "closed"` that are also in Done. The Area *is* the system; this is the natural cluster.
- **Seed is a solo / `area/loose` task** (no umbrella): group it with other Done tasks that touched the **same system**, inferred from their plan files' paths (`docs/plans/<number>*.md`). A task with no plan and no umbrella is its own one-item cluster.

Cap the cluster at **10**; leave the rest for the next run and **say so** — no silent caps.

## Phase 2: Classify and draft the cleanup plan

For every issue in the cluster, gather evidence and classify:

```bash
source "${CLAUDE_PLUGIN_ROOT}/bin/harness-lib.sh" && blacksmith_issue_view <NUMBER> \
  | jq '{number, title, state, stateReason, url}'
# umbrellas: confirm every child is closed
"${CLAUDE_PLUGIN_ROOT}/bin/list-children.sh" <UMBRELLA> | jq '[.[] | {number, state}]'
```

| Classification | Meaning | Default disposition |
|----------------|---------|---------------------|
| `shipped` | `state == "closed"` + `stateReason == "completed"` (on forges without close reasons — Forgejo — `stateReason` is `null`: fall back to close state + every-child-closed); **umbrella:** every child `closed` | Archive after batch approval |
| `not-planned` | Closed `not_planned` (a `null` `stateReason` on a closed issue is **not** `not-planned` — treat it as `shipped`-candidate per the fallback above, or `in-flight` if children are open) with an explanatory comment | Individual decision |
| `in-flight` | Closed but an umbrella still has open children (or evidence of unmerged work) | Individual decision |
| `anomaly` | In Done but still **open**, or evidence contradicts the column | Report only — never archive |

> **Why state, not PR-base.** Children merge into the **Area branch**, not `main`, and are **explicitly closed** on that staging merge — so the portable "shipped" signal is the close state (umbrella ⇒ all children closed), not a PR's `baseRefName`. (`blacksmith_pr_open_count` keys off a **branch**, not an issue, so it is not the per-issue check here.) Per-Area base resolution is the Track-C refinement; close-state does not need it.

Write the plan artifact to `docs/temp/clean-up-<YYYY-MM-DD>-<system>.md` (gitignored working artifact):

- One row per issue: number, title, classification, evidence link (issue/PR URL or closing comment), linked plan file in `docs/plans/` if any.
- **Doc-impact map.** For each `shipped` issue, read the touched paths from its plan file (`docs/plans/<number>*.md`; plan-less issues → derive from the issue body or note "paths unknown"). Map which `docs/` files cover those paths and what looks stale or missing. **Then tag each knowledge item `brain` or `repo`** per the split rule, with a one-line reason citing the test.

## Phase 3: Validate

Re-verify mechanically before anything reaches the developer — do not trust the artifact you just wrote. Re-run `blacksmith_issue_view` (and `"${CLAUDE_PLUGIN_ROOT}/bin/list-children.sh"` for umbrellas) **fresh** for every `shipped` claim and confirm the close state still holds. Downgrade anything that fails to `anomaly`.

## Phase 4: Human approval gate

Walk the developer through the artifact with `AskUserQuestion`:

1. **Batch question** for the validated `shipped` set: archive all / pick / skip.
2. **One individual question per** `not-planned`, `in-flight`, and `anomaly` case, quoting the evidence. Options: Archive / Keep on board / Needs follow-up (suggest `/scope` or a new issue; do not create it yourself).
3. **Confirm the routing** — show which knowledge items go to the **brain** vs **repo** (brain writes leave the repo or get staged, so they are gated too).

Nothing the developer didn't approve gets archived or written to the brain. Max 4 options per question — batch if a list runs long.

## Phase 5: Documentation reconciliation — the split

Route the approved doc-impact items by the **docs/brain split** (reference below). Two disjoint passes; an item lands in exactly one.

**Repo half (project-scoped docs).** Spawn the curator with the `repo`-tagged items — one dispatch per run (one cluster = one system):

```
Agent(
  subagent_type: "doc-curator",
  prompt: "HARNESS_TOKEN_MARKER role=doc-curator issue=<SEED> kind=execution
           Reconcile the project's docs/ tree for the <system> system.
           Doc-impact map (repo-tagged items only): [paste from the artifact]
           Issues/PRs in this cluster: [numbers + links]
           Verify every doc claim against the actual tree, patch drift, create a
           new doc only if none covers this system, update the docs index if one
           exists. Report every claim checked."
)
```

Then spawn `reviewer` on the curator's output: every changed claim is backed by a cited file path that exists; no invented content; any docs index reflects new/renamed docs. One revision loop max — if the second pass still fails, surface to the developer instead of iterating.

**Brain half (permanent systems/tech knowledge).** For each `brain`-tagged item, distill it to a self-contained note, then route:

Give each note a **note-unique** provenance of the shape `<issue-or-pr-ref>:<system-slug>` — the merged PR or issue ref plus the system slug (e.g. `#42:board-dispatcher`), never a bare issue ref, or a second note from the same issue silently dedups away. Hand the distilled note and that provenance to **`/hjarne integrate`**: `/hjarne` owns the write — it archives the raw note, version-stamps `wiki/<system-slug>.md`, and echoes a **returned page pointer** (the page relpath). Capture that pointer for the Phase 8 commit body. Never fold a brain note into `docs/` project docs — the boundary holds wherever `/hjarne` lands it.

The brain-absent fallback belongs to `/hjarne`, not clean-up: if the brain isn't built yet, `/hjarne`'s own inbox fallback stages the note under `docs/brain-inbox/`. clean-up calls `/hjarne integrate` **unconditionally** and no longer writes any inbox itself.

**Done when:** every doc-impact item is tagged `brain` or `repo` with a reason; every `repo` item is reconciled by the curator pass; every `brain` item is handed to `/hjarne integrate` and clean-up captures the returned page pointer; **zero items dropped or double-homed.**

## Phase 6: Archive plan files

For each approved `shipped` issue with a linked plan still in `docs/plans/`:

```bash
mv docs/plans/<file>.md docs/_local_archive/<file>.md
```

`docs/_local_archive/` is gitignored — the move shows as a delete from `docs/plans/`; the file stays on disk and in git history. Multi-phase plans: if a later-phase file references unfinished work, ask before archiving. A plan **never** goes to the brain — *if it can go stale, it's the plan.*

## Phase 7: Archive board cards and log

For each approved issue:

```bash
ITEM_ID=$("${CLAUDE_PLUGIN_ROOT}/bin/find-item.sh" <NUMBER>)
"${CLAUDE_PLUGIN_ROOT}/bin/archive-item.sh" "$ITEM_ID"
echo "$(date +%F) #<NUMBER> <classification> <evidence-url>" >> logs/clean-up.log
```

Archiving removes the card from the board view only — the issue is untouched and the action is reversible from the archived-items view. This skill never closes or reopens an issue.

## Phase 8: Commit

```bash
git add docs/
git commit -m "clean-up: <system>" \
  -m "brain notes filed (returned page pointers from /hjarne integrate):" \
  -m "- <system-slug> → wiki/<system-slug>.md"
```

`git add docs/` captures the curator's doc changes, the `docs/plans/` deletions, and any `docs/brain-inbox/` notes `/hjarne` staged through its own inbox fallback (gitignored `docs/temp/` + `docs/_local_archive/` are excluded). The **commit body lists each** brain note's returned page pointer — the `wiki/<system-slug>.md` relpath `/hjarne integrate` echoed. That committed, `git log`-discoverable list is the sole repo-side breadcrumb for what landed in the brain; do not create a separate committed file for it (a `logs/clean-up.log` line is fine as a local trace but does not discharge this). **Do not push** — that stays human-gated. Finish with a short summary: issues archived, issues kept, docs touched, **brain notes integrated (each with its returned page pointer)**, and what the next run's seed will be.

---

## Reference — the docs/brain split (Stage 7's governing rule)

Every piece of knowledge the cluster surfaces routes to **exactly one** home. Decide per item with one test:

> **If this repo vanished, would the knowledge still be worth keeping?**

- **Yes → the brain (hjarne, #28).** Permanent systems/tech knowledge: how a subsystem works, an architecture decision's rationale, a cross-cutting invariant, a reusable pattern or gotcha — what a future task on a *different* Area would want. Not tied to this repo's file layout.
- **No → the repo (`docs/`).** Project-scoped docs: module references, runbooks, setup, config — anything path- or repo-bound. It versions next to the code it describes.

**Per-task plans are always repo, always archived.** `docs/plans/<id>.md` is the ephemeral HOW (paths, TDD step order); on ship it moves to `docs/_local_archive/` (Phase 6). Never the brain — it goes stale by design.

**Graceful degradation lives entirely inside `/hjarne`:** clean-up always calls `/hjarne integrate` and captures the returned page pointer; if the brain isn't built yet, `/hjarne`'s own inbox fallback stages the note under `docs/brain-inbox/` (committed via Phase 8, never dropped, never mixed into project docs). clean-up itself never writes that inbox — the degradation path is `/hjarne`'s to own, and when the brain lands, that inbox is `/hjarne`'s migration queue.

## Gotchas

- **`state: "closed"` is not "shipped".** An issue can be closed `not_planned`. For an umbrella, "shipped" means **every child closed** (the Area-branch merge model's portable signal) — not the umbrella's own state alone.
- **Old plan files vastly outnumber clusters.** `docs/plans/` accumulates; archive only the ones linked to issues approved this run. The backlog drains over repeated runs, not one.
- **Working artifacts vs. the record.** `docs/temp/` and `logs/` are gitignored; the committed record is the doc changes, the plan-file deletions, and any `docs/brain-inbox/` notes `/hjarne` staged as its inbox fallback. The board's archived-items view, `logs/clean-up.log`, and the Phase 8 commit body's page-pointer list carry the audit trail.
- **Don't reach for `gh api graphql`.** Read the board through `blacksmith_list_board` and children through `"${CLAUDE_PLUGIN_ROOT}/bin/list-children.sh"` so the skill stays backend-neutral; use `blacksmith_issue_view` / `blacksmith_issue_comment` for per-issue read/comment.
