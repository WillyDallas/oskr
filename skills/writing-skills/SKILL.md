---
name: writing-skills
description: Use when creating or editing an oskr skill — choosing its invocation (model-invoked ability vs user-invoked process), writing the description, structuring steps vs reference, and pruning to predictability. Reach for it before writing or changing a skill's frontmatter.
---

A skill exists to wrangle determinism out of a stochastic system. **Predictability** — the agent taking the same *process* every run, not the same output — is the root virtue; every rule below serves it.

This skill is itself all-reference and model-invoked: it obeys what it describes. The full source vocabulary is the vendored mattpocock reference — cite it, do not duplicate it:

- `docs/reference/mattpocock-skills/skills/productivity/writing-great-skills/SKILL.md` + `GLOSSARY.md`
- `docs/reference/mattpocock-skills/docs/invocation.md`

## 1. Invocation — the headline

The `description` field **is** the invocation axis. Its mere presence decides who can reach the skill. Every skill is one of two kinds:

- **Model-invoked ability** — keep the description. The agent fires it autonomously *and* the human can still type its name (model-invocation always *includes* user reach — there is no model-only state). Other skills can reach it too. Cost: the description sits in context every turn (**context load**). Use for an op the agent should reach for as needed.
- **User-invoked process** — set `disable-model-invocation: true`. Only the human, typing its name, can fire it, and no other skill can. The description becomes human-facing (a one-line summary; strip the trigger lists). Zero context load, but spends **cognitive load** — the human is the index that must remember it exists. Use for a workflow the human deliberately triggers and that must NOT be auto-injected into context.

**The test:** *could the model usefully reach for this autonomously, or must another skill reach it?* If yes → model-invoked ability. If it only ever fires by hand → user-invoked process. **Reuse is not the test** — a skill reused by humans can still be a user-invoked process.

**Default developer rituals** — bootstrap, cleanup, approval gates, manual sync — to user-invoked process. Pay context load only where the agent genuinely must self-dispatch.

**Dependency rule:** a user-invoked process may invoke a model-invoked ability, but **never another user-invoked process** (a user-invoked skill has no description, so nothing but the human can fire it). Express a handoff between two processes as a prose suggestion to the human, never a `Skill()` call.

**Router escape hatch:** when user-invoked processes multiply past what you can remember, add one user-invoked router skill that names the others and when to reach each.

## 2. Description (model-invoked only)

Two jobs: state what the skill is, and list the **branches** that trigger it. Every word is context load, so prune the description harder than the body.

- Front-load the **leading word** — the description does its invocation work there.
- One trigger per branch; synonyms renaming a single branch are duplication — collapse them.
- Cut identity already stated in the body; keep triggers plus any "when another skill needs…" reach clause.
- A user-invoked process's description is a human-facing one-liner, trigger lists stripped.

## 3. Body & information hierarchy

Content is **steps** (ordered actions, the primary tier) and **reference** (consulted on demand). A skill can be all steps, all reference, or both.

- Every step ends on a **completion criterion** — make it *checkable* (can the agent tell done from not-done?) and, where it matters, *exhaustive* ("every modified model accounted for"). A vague criterion invites **premature completion**.
- A demanding criterion drives **legwork** — the digging the agent does within a step. Raise it with a strong leading word or an exhaustive bound; it binds flat reference too ("every rule applied").
- **Progressive disclosure:** push reference behind a **context pointer** (a linked file) so the top of `SKILL.md` stays legible. Inline what every branch needs; disclose what only some branches reach.
- A context pointer's **wording, not its target**, decides when the agent reaches it. A must-have behind a weak pointer is a variance bug — fix the wording before inlining.
- **Co-location:** keep a concept's definition, rules, and caveats under one heading.
- **Split by sequence** only when a step's later steps tempt the agent to rush the current one — and hiding them needs a real context boundary (a subagent or a user hand-off), not an inline call that leaves them in context.

## 4. Leading words

A leading word is a compact concept already living in the model's pretraining (*lesson*, *fog of war*, *tracer bullets*, *red*, *tight*). Repeated as a token — never restated as a sentence — it accumulates a distributed definition and anchors a whole region of behaviour in the fewest tokens. Hunt restatements ("fast, deterministic, low-overhead" → *tight*) and collapse them. Prefer a pretrained word; a coined one recruits no priors, so you pay in definition tokens what a real word gives free.

## 5. Pruning

- **Single source of truth** — each meaning in exactly one place; changing behaviour is then a one-place edit.
- **Relevance** — does the line still bear on what the skill does? Cut stale lines.
- **No-op test** — run it per sentence, in isolation: does the line change behaviour versus the model's default? If not, delete the whole sentence (don't trim words). A leading word too weak to beat the default (*be thorough*) is a no-op; fix it with a stronger word (*relentless*), not a different technique. This skill obeys its own test — do not let it re-bloat.

## Failure modes (diagnose against)

**Premature completion** (rushing a step — sharpen the criterion first; hide later steps only if the bound is irreducibly fuzzy) · **Duplication** (the same meaning in two places) · **Sediment** (stale layers never cleared) · **Sprawl** (too long even when every line is live — cure with the hierarchy) · **No-op** (a line the model already obeys by default).
