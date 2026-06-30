---
name: decompose
description: Decompose an approved Area PRD into independently-grabbable task issues — tracer-bullet vertical slices created under the umbrella with native deps. Reach for it from `scope` after the PRD lands.
argument-hint: "[umbrella-issue-number]"
allowed-tools: Bash(gh *) Bash(create-issue.sh*) Bash(set-milestone.sh*) Bash(link-parent.sh*) Bash(add-dep.sh*) Bash(find-item.sh*) Bash(move-issue.sh*) AskUserQuestion Read Grep
---

Turn the umbrella's PRD into **tracer bullets** — thin vertical slices, each demoable on its own — published as linked task issues. Runs inside the Scope gate, so the developer is present to ratify the cut.

## Steps

1. **Read the umbrella.** `gh issue view <umbrella> --json title,body,labels`. Pull the **Task DAG** and **Named Seams** from the PRD body, and resolve the Epoch (the milestone title in the PRD's **Placement** section) + the `area/<slug>` label it carries. If the PRD describes a single unit of work, **the umbrella IS the task — stop**; there is nothing to decompose.

2. **Draft the slices.** Each slice is a **tracer bullet**: a narrow but complete path end-to-end, verifiable alone — not a horizontal layer. In a non-layered repo (bash / skills / agents), a slice is one end-to-end capability that exercises a seam. Prefactor first — "make the change easy, then make the easy change."

   **Right-size the cut: aim for ~6 slices or fewer.** Every child carries a full downstream tax — planning, adversarial review, execution, a PR — and that cost scales ~linearly with child count (the Area #27 baseline planned 9 children for ~2.96M tokens). So prefer the *coarsest* cut that still keeps each slice independently demoable. **Merge trivially-coupled slices**: two that always ship together, or where one is a thin wrapper on the other, are one slice. The ~6 cap is a smell test, not a hard limit — exceed it only when the seams genuinely demand it, and say why in the quiz.

3. **Quiz the developer** (one list, then iterate): granularity (too coarse / too fine? — explicitly flag and justify if you've drafted more than ~6 slices), dependency order, anything to split or merge. Do not publish until they approve.

4. **Publish in dependency order** (blockers first, so real numbers exist to reference). Per slice:
   - `create-issue.sh "<title>" "<body>" "area/<slug>"` — body is **`## What`** (end-to-end behavior, no file paths) + **`## AC`** (checkbox criteria). **Omit `touches:`** — the path-set is the per-task plan's job, not decompose's.
   - `set-milestone.sh <child> "<Epoch title>"` — same Epoch as the umbrella.
   - `link-parent.sh <umbrella> <child>`.
   - `add-dep.sh <child> <blocker>` for each blocker (typed edge, never prose).
   - `move-issue.sh "$(find-item.sh <child>)" Planning`.

**Done when:** every approved slice is published with `area/<slug>` + Epoch milestone, linked under the umbrella, its blockers recorded as native deps, and sitting in **Planning** — and the umbrella's children list matches the approved DAG. Do not modify the umbrella itself.

## Token budget

Decompose itself is cheap (no agent fan-out), but the **child count it sets is the single biggest multiplier on downstream cost** — every child is planned and reviewed independently. Default target: **~6 slices or fewer** per Area. Track the realized count against downstream token cost in the ledger — the Datapoints table in [`docs/design/workflow-token-optimization.md`](../../docs/design/workflow-token-optimization.md).
