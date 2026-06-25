# Skills audit — mattpocock/skills for oskr adoption

**Date:** 2026-06-22 · Source: https://github.com/mattpocock/skills (34 skills, audited per-skill).
**Why this doc:** the audit drove the platform reframe; this preserves its actionable verdicts so the
adopt-list isn't lost. Feeds the parked **Skills adoption** epoch (see [roadmap-v1](../design/roadmap-v1.md)).

## Framing

Matt's skills are small, stateless, model-agnostic thinking-tools; oskr's are heavy, board-wired
pipeline drivers. The fit question is "does it fill an oskr gap without fighting the board-centric
model" — so most value is *techniques to fold into existing agents*, not skills to install.

## Adopt

| Skill | Why | How |
|---|---|---|
| **diagnosing-bugs** | The one **natural-fit** — oskr has no bug-diagnosis discipline | As a `diagnosing-bugs` agent (counterpart to `implementer`); unblocks #15. Gem: Phase-1 hard gate — "no red-capable command → no hypothesis." |

## Fold the technique (don't adopt the skill)

- **grilling** → `developer-input` adversarial mode: one question at a time, always offer a recommended answer, explore the codebase instead of asking.
- **tdd** (`tests.md`/`mocking.md`) → reference material for `implementer`/`reviewer`; guardrail: "rename an internal fn — if tests break, they tested implementation, not behavior."
- **review** (two-axis Standards vs Spec, never blended) → fixes `reviewer` collapsing spec + quality into one weighted score.
- **codebase-design `DESIGN-IT-TWICE`** → anti-mode-collapse fan-out (N agents, conflicting constraints) for research/plan exploration.

## Worth investigating (real gap, real port)

- **Issue-ingestion** (`to-issues`/`to-prd`/`triage`/`qa`) — oskr's pipeline assumes issues exist. Gems: "tracer-bullet vertical slice", "durable issue: behavior not code, no file paths".
- **decision-mapping** — multi-session decision resolution before planning (fog-of-war frontier).

## Standalone / outside the pipeline

- **teach** — great skill, *wrong harness for the delivery pipeline* → becomes the **learning domain** (own workspace). Steal: learning-records-as-ADRs, FORMAT-file compression, "never trust parametric knowledge."
- **writing-great-skills** — drop-in meta-skill for maintaining oskr's own skill library (leading-word + No-Op pruning).
- **git-guardrails** — skip the git patterns (they'd block oskr's own pushes); keep the exit-code-2 PreToolUse hook as an AFK deny-list primitive.

## Skip (off-mission / Matt-specific)

ask-matt, setup-matt-pocock-skills, improve-codebase-architecture, implement, request-refactor-plan,
migrate-to-shoehorn, scaffold-exercises, setup-pre-commit, edit-article, obsidian-vault,
writing-beats/fragments/shape.

## Cross-cutting patterns worth stealing regardless

Durable artifacts (behavior not code, no file paths) · opinionated glossaries with `_Avoid_` alias
lists · ADR write-gate (hard-to-reverse AND surprising AND a real trade-off) · divergent-constraint
fan-out · learning-records-as-ADRs (supersedable decision log).
