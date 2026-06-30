---
name: research
description: Ground a goal or issue before scoping or planning — assemble ONE cited digest from the repo and the web and post it to the issue. Reach for it from `scope`, or whenever a decision needs evidence on the table.
argument-hint: "[issue-number | topic]"
allowed-tools: Bash(gh *) Bash(sync-development.sh*) Read Glob Grep Agent
---

Assemble one grounded, cited digest so the grill that follows starts informed instead of cold. This is an **ability**: `scope` runs it inline and the v2 loop runs it ahead of time — either way the output is the same durable comment.

> Future enrichment: a vendored `deep-research` (web) and `hjarne` (brain read) widen the sources. v1 leans on the **researcher → research-reviewer** agents over the working tree + `WebSearch`.

## Steps

1. **Resolve the subject.** If `$ARGUMENTS` is an issue number, read it (`gh issue view <n> --json title,body,comments`). If a `## Research Digest` comment is already present and the working tree has not moved since it was written, **reuse it — stop here** (do not re-dig). Otherwise continue.

2. **Sync the tree before spawning agents.** Researchers read the local tree; a stale base yields confident-wrong findings. `sync-development.sh research` — on a non-zero exit, surface the message and stop rather than research a stale base.

3. **Dispatch the loop.** Spawn the **researcher** agent (working tree + web), then the **research-reviewer** agent to check it. Iterate until the reviewer is satisfied or returns concrete gaps.

4. **Assemble ONE digest** — recommendation · key files & candidate **seams** (`file:path`) · risks · open questions · citations (URLs + `file:line`). One digest, not a transcript.

5. **Post it** as a `## Research Digest` comment (`gh issue comment <n>`), and **leave the card where it is** — research never crosses a gate.

**Done when:** a single reviewer-checked `## Research Digest` comment covering repo + web sits on the issue (or a fresh one already did, and you reused it).

## Token budget

Default fan-out: **researchers + 1 research-reviewer + 1 synthesizer**, iterating until the reviewer is satisfied. Keep the researcher count to what the subsystems actually demand — one per distinct subsystem, not one per file. The Area #27 scope round measured **~449k tokens / 7 agents** (research fan-out ~419k), roughly **⅐ the cost of a planning round**, so research is the secondary target; the reuse check in Step 1 (don't re-dig a still-valid digest) is the cheapest saving here. Record notable runs in the ledger — [`docs/design/workflow-token-optimization.md`](../../docs/design/workflow-token-optimization.md).
