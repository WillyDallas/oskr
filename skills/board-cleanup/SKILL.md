---
name: board-cleanup
description: Use periodically to clear verified-Done cards off the project board and reconcile documentation. Works one system cluster per run — seeds from the oldest Done issue, gathers the issues/PRs that touched the same system, updates architecture docs via the doc-curator agent, archives plan files, then archives the board cards after human approval. Replaces branch-docs-cleanup.
allowed-tools: Bash(gh *) Bash(git *) Bash(jq *) Bash(sync-development.sh*) Bash(find-item.sh*) Bash(archive-item.sh*) Bash(mv docs/plans/*) Bash(mkdir *) Bash(tail *) Bash(date *) Agent AskUserQuestion Read Glob Grep Write
---

Clear the board of completed work and bring documentation in line with what actually shipped. One **system cluster per invocation** — bounded cost, repeatable until the Done column is empty. Run it again for the next cluster.

The flow is plan → validate → human approve → execute. No board write or doc commit happens before the approval gate.

## Setup

Resolve the project coordinates and base branch from `harness-config.json` (in the consumer repo's CWD) — every GraphQL query below uses them:

```bash
OWNER=$(jq -r '.github.owner' harness-config.json)
REPO=$(jq -r '.github.repo' harness-config.json)
PROJECT_NUMBER=$(jq -r '.github.project_number' harness-config.json)
BASE_BRANCH=$(jq -r '.base_branch // "main"' harness-config.json)
```

## Preconditions

Runs from the base branch directly — no feature branch.

```bash
sync-development.sh board-cleanup
```

On exit 1, stop and inform the developer — cleanup decisions made against a stale tree can archive work that isn't actually shipped.

Then read prior-run state so this run doesn't re-litigate already-archived issues:

```bash
tail -30 logs/board-cleanup.log 2>/dev/null || echo "(no prior runs)"
```

## Phase 1: Seed and cluster

List the Done column directly from the board and pick the seed — the lowest issue number (the earliest work still on the board):

```bash
gh api graphql -f query='
  query($owner: String!, $repo: String!, $number: Int!) {
    repository(owner: $owner, name: $repo) {
      projectV2(number: $number) {
        items(first: 100) {
          nodes {
            status: fieldValueByName(name: "Status") {
              ... on ProjectV2ItemFieldSingleSelectValue { name }
            }
            content { ... on Issue { number title } }
          }
        }
      }
    }
  }
' -F owner="$OWNER" -F repo="$REPO" -F number="$PROJECT_NUMBER" \
  --jq '[.data.repository.projectV2.items.nodes[]
         | select(.status.name == "Done")
         | {number: .content.number, title: .content.title}]
        | sort_by(.number)'
```

For the seed and each candidate, pull closing evidence and changed paths in one query:

```bash
gh api graphql -f query='query($owner: String!, $repo: String!, $n: Int!) {
  repository(owner: $owner, name: $repo) {
    issue(number: $n) {
      state stateReason title
      closedByPullRequestsReferences(first: 10) {
        nodes { number merged mergedAt baseRefName files(first: 100) { nodes { path } } }
      }
    }
  }
}' -F owner="$OWNER" -F repo="$REPO" -F n=<NUMBER>
```

Identify the **system** the seed touched from its PR's changed paths (e.g. auth, payment gate, content pipeline, harness). Then scan the other Done issues for ones whose closing PRs touch the same system. The cluster is the seed plus those related issues, **capped at 10** — leave the rest for the next run and say so (no silent caps).

## Phase 2: Classify and draft the cleanup plan

Classify every issue in the cluster, with evidence:

| Classification | Meaning | Default disposition |
|----------------|---------|---------------------|
| `merged-pr` | Closed by a merged PR (verify `merged: true` and the base branch) | Archive after batch approval |
| `not-planned` | Closed as `NOT_PLANNED` with an explanatory comment | Individual decision |
| `closed-no-pr` | Closed `COMPLETED` but no merged PR found (policy violation or non-PR route) | Individual decision |
| `anomaly` | In Done but still open, or evidence contradicts the column | Report only — never archive |

Write the cleanup plan artifact to `docs/temp/board-cleanup-<YYYY-MM-DD>-<system>.md` (keep it as a working artifact — gitignore `docs/temp/` if the project doesn't already):

- One row per issue: number, title, classification, evidence link (PR URL or closing comment), linked plan file in `docs/plans/` if any
- **Doc-impact map**: the system touched, the paths involved, which docs in the project's docs tree cover that system (check any docs index), and what looks stale or missing

## Phase 3: Validate

Re-verify mechanically before anything reaches the developer — do not trust the artifact you just wrote. For every `merged-pr` claim, re-run the GraphQL query fresh and confirm: PR `merged: true`, `baseRefName` is `$BASE_BRANCH` (or another branch the project legitimately ships through), and the issue state is `CLOSED`. Downgrade anything that fails to `anomaly`.

## Phase 4: Human approval gate

Walk the developer through the artifact with `AskUserQuestion`:

1. **Batch question** for the validated `merged-pr` set: archive all / pick / skip.
2. **One individual question per** `not-planned`, `closed-no-pr`, and `anomaly` case, quoting the evidence. Options: Archive / Keep on board / Needs follow-up (suggest `create-issue`; do not create it yourself).

Nothing the developer didn't approve gets archived. Max 4 options per question — group into batches if a list runs long.

## Phase 5: Documentation reconciliation

Spawn the curator with the doc-impact map. One dispatch per run — the cluster is one system, so one curator pass covers it:

```
Agent(
  subagent_type: "doc-curator",
  prompt: "HARNESS_TOKEN_MARKER role=doc-curator issue=<SEED> kind=execution
           Reconcile the project's docs tree for the <system> system.
           Doc-impact map: [paste from the cleanup plan artifact]
           Issues/PRs in this cluster: [numbers + PR links]
           Verify doc claims against the actual tree, patch drift, create a new
           doc only if no existing doc covers this system, and update the docs
           index if the project maintains one. Report every claim checked."
)
```

Then spawn the `reviewer` agent on the curator's output with these criteria: every changed doc claim is backed by a cited file path that exists; no invented content; any docs index reflects new or renamed docs. One revision loop max — if the second pass still fails, surface to the developer instead of iterating.

## Phase 6: Archive plan files

For each approved issue with a linked plan file still in `docs/plans/`:

```bash
mv docs/plans/<file>.md docs/_local_archive/<file>.md
```

`docs/_local_archive/` is gitignored — the move shows as a delete from `docs/plans/`, and the file stays reachable on disk and in git history. Multi-phase plans: if a later-phase plan file references unfinished work, ask before archiving.

## Phase 7: Archive board cards and log

For each approved issue:

```bash
ITEM_ID=$(find-item.sh <NUMBER>)
archive-item.sh "$ITEM_ID"
echo "$(date +%F) #<NUMBER> <classification> <evidence-url>" >> logs/board-cleanup.log
```

Archiving removes the card from the board view only — the issue itself is untouched and the action is reversible from the project's archived-items view.

## Phase 8: Commit

```bash
git add docs/
git commit -m "board cleanup: <system>"
```

Do not push — that stays human-gated. Finish with a short summary: issues archived, issues kept, docs touched, and what the next run's seed will be.

## Gotchas

- **`state: CLOSED` is not "shipped".** An issue can be closed `NOT_PLANNED` or closed without a merged PR; only a verified merged PR counts as `merged-pr`. Archiving and closing are different operations — this skill never closes or reopens an issue.
- **Old plan files vastly outnumber clusters.** `docs/plans/` accumulates completed plans; only archive the ones linked to issues approved this run. The backlog drains over repeated runs, not one.
- **`closedByPullRequestsReferences` misses non-linked PRs.** If empty, search before concluding `closed-no-pr`: `gh pr list --search "<NUMBER> in:body" --state merged`.
- **Two-stage base flows bundle issues.** If the project ships through an intermediate branch (e.g. `development` → `main`), one base-branch PR can close many issues — expect clusters to share a single closing PR.
- **Working artifacts vs. the record.** `docs/temp/` and `logs/` should be gitignored; the committed record is the doc changes and plan-file deletions, while the board's archived-items view plus `logs/board-cleanup.log` carry the audit trail.
