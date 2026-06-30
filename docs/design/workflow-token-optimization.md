# Workflow token optimization — baseline + plan

**Date:** 2026-06-30 · **Status:** plan, pre-implementation · **Tracking:** [#73](https://github.com/WillyDallas/oskr/issues/73)

oskr's multi-agent workflow skills are correct but **expensive** — the fan-outs dominate token cost. This doc records the first measured baseline and the plan to cut it. The two primary targets map to the two cost drivers:

1. **`planning-session` (Area-batch / Phase U)** — reviewers per task.
2. **`decompose`** — the number of children an Area is cut into (cost scales ~linearly with it).

(`research` shares the same adversarial-review pattern and benefits from the same fixes, but is ~7× cheaper per run, so it's secondary.)

## Baseline — Area #27 (Workspace & setup), 2026-06-30

Single source of truth for future comparison. **Subagent tokens only** (main-loop orchestration excluded). Append new datapoints below as the optimization lands.

### Planning — `planning-session` Area-batch (9 children): **2,960,407 tokens / 48 agents** (~38 min)

| Category | Agents | Tokens | Share |
|---|---|---|---|
| planners | 9 | 918,911 | 31% |
| **lens reviewers** | **27** | **1,572,832** | **53%** |
| synthesizers | 9 | 214,333 | 7% |
| revisers | 3 | 254,331 | 9% |
| **review subtotal** | **36** | **1,787,165** | **60%** |

Per-child average ≈ **329k tokens** · 5.3 agents/child (1 planner + 3 lenses + 1 synth + ~0.3 revise).

### Scope / GATE 1: **449,449 tokens / 7 agents**
- research fan-out: 419,102 (4 subsystem researchers 314k + 1 reviewer 64k + 1 synth 41k)
- PRD adversarial review: 30,347

**Combined scope + plan ≈ 3.41M tokens / 55 agents.** Planning was **6.6×** the scope round.

## Cost model

```
cost ≈ children × (planner + reviewers_per_child × reviewer_cost + synth + revise)
```

The dominant term is `reviewers_per_child` (3 lenses + 1 synth = 60% of planning), multiplied by `children`. The two highest-leverage knobs are therefore **reviewers-per-child** and **children**.

## Levers (highest leverage first)

1. **`planning-session`: collapse the reviewer panel.** Replace the always-on 3-lens panel + synthesizer (36 of 48 agents) with **one reviewer owning all axes**, escalating to the full panel **only** when the single reviewer flags risk or the task touches a named-seam contract. Eliminates the synth stage entirely. Est. **≈ −43%** of planning.
2. **`decompose`: right-size the cut.** Cost is ~linear in child count; 9 tracer slices was generous. Add explicit guidance + a soft cap, and prefer merging trivially-coupled slices. ~−⅓ at 9→6.
3. **Single planner pass.** The stock `planning-session` runs *two* planner rounds (scoping DoD, then execution); the Area-batch already collapsed these into one. Make the single pass the default and measure the quality delta.
4. **Cheaper tiers for cheap stages.** Synthesis (merging JSON, no tree reads) and shallow lenses don't need the top model/effort — route them down.
5. **Drop the un-re-reviewed revise.** A revise pass that isn't re-verified adds cost without a confidence gain; defer the fix to the human GATE 2 (plan-approval) instead, which exists to catch exactly this.

**Rough target:** fewer children (9→~6) + single-reviewer-with-escalation → planning **2.96M → ~1.1M (~−63%)** with no drop in caught-defect rate.

## Acceptance

- [ ] `planning-session` reviewer fan-out is **conditional** (escalate; don't always run 3 lenses + synth).
- [ ] `decompose` documents a right-sizing heuristic / soft cap on children.
- [ ] `planning-session`, `decompose`, and `research` each document a default agent/reviewer budget.
- [ ] A re-run on a comparable Area is measured here at a **materially lower** token cost than the 2.96M baseline, with **no drop** in caught-defect rate.

## Datapoints

| Date | Area | Children | Planning tokens | Agents | Config |
|---|---|---|---|---|---|
| 2026-06-30 | #27 | 9 | 2,960,407 | 48 | 3-lens panel + synth + 1 revise (baseline) |
