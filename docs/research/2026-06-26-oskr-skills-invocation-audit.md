# oskr skills — invocation-hygiene audit

**Date:** 2026-06-26 · Issue #33 · Rubric: `skills/writing-skills/SKILL.md`
(the meta-skill, derived from the vendored `docs/reference/mattpocock-skills/skills/productivity/writing-great-skills/`).

> **Status: #32 input note, not a co-equal #33 deliverable.** Per the maintainer reframe, #33's
> primary output is the `writing-skills` meta-skill; this audit is the *one-off* form the reframe
> steered away from. Its verdicts are sound and kept as **input to #32** (which redesigns the
> pipeline and applies the invocation calls to the surviving skills) — not as a standalone change to
> land now.

**What this is:** the per-skill verdict (user-process vs model-ability) for oskr's 8 current skills,
held against the `writing-skills` rubric. The verdicts are the **lens**; the frontmatter edits get
applied to the *redesigned* skill set in **#32's session**, not here. The "recommended frontmatter"
column is the mechanical change #32 (or a follow-up) applies once the skill survives the redesign.

## Headline finding

**All 8 skills currently keep a `description` and none set `disable-model-invocation`** — so all 8
are model-invoked and pay **context load every turn**, including the 5 that only ever fire when a
human types their name. Five of eight are paying for discoverability they don't use.

The test (`docs/reference/mattpocock-skills/docs/invocation.md`): *could the model usefully reach for
this autonomously, or must another skill reach it?* Reuse is **not** the test.

## Verdicts

| Skill | Verdict | Why | Recommended frontmatter |
|---|---|---|---|
| **execute-plan** | **model** | Runs headless via the dispatcher (`claude -p`) — the agent must self-dispatch it. | keep description (omit `disable-model-invocation`) |
| **planning-session** | **model** | Agent-only planner→reviewer loop; the dispatcher picks it up, and `developer-input` fires it. | keep description |
| **research-session** | **model** | Agent-only researcher→reviewer loop the dispatcher reaches. | keep description |
| **board-cleanup** | **user** | A maintenance ritual a human runs "periodically"; gated on human approval; no skill fires it. | add `disable-model-invocation: true` |
| **developer-input** | **user** | The human-in-the-loop Q&A gate — it *walks the developer through* questions; it can't run without a person. | add `disable-model-invocation: true` |
| **init** | **user** | Interactive project bootstrap, run by hand from a target dir. The model would never autonomously create a repo. | add `disable-model-invocation: true` |
| **plan-review** | **user** | Human approve/reject gate; "never auto-executes." | add `disable-model-invocation: true` |
| **sync-worktree** | **user** *(judgment call)* | Thin wrapper telling a human to run one canonical script. `execute-plan` already calls the *script* (`sync-worktree.sh`) directly, not the skill — so the skill exists for manual use. | add `disable-model-invocation: true` |

**Split: 3 model-reachable (the dispatcher-driven generator-evaluator loops) / 5 user-only (the
human gates and rituals).** The model-reachable set is exactly the skills an autonomous dispatcher
must fire; everything else is developer-triggered.

### The one judgment call — `sync-worktree`

Arguable as model-reachable so an agent resuming work syncs first. Kept **user** because the
canonical `sync-worktree.sh` is already directly callable and `execute-plan` uses the script, not
the skill — the skill is a human convenience around one command. If #32 gives an agent a "resume
and self-sync" path, flip it to model. Low stakes either way.

## Dependency-rule check (user-invoked may never fire another user-invoked)

Only **two real `Skill()` fires** exist; both are legal:

- `developer-input` (user) → `planning-session` (model) ✓ — option (a), `Skill(name: "planning-session")`.
- `plan-review` (user) → `execute-plan` (model) ✓ — the opt-in execute gate.

Every *other* "invoke X" line (e.g. plan-review's "(c) → invoke `developer-input`") is a
**human-facing next-action menu**, not an autonomous call — which is the correct pattern for a
user→user handoff, since a user-invoked skill has no description for another skill to fire.

**Guardrail for #32:** keep cross-gate handoffs between two user-only skills as **prose
suggestions to the human**, never `Skill()` calls. The moment a user-only skill needs to *fire*
another user-only skill, the rule is violated — promote the callee to model-invoked or route via a
**router skill**.

## Beyond invocation — description & pruning notes

When #32 rewrites these, also apply rubric §2–§5:

- **Strip trigger phrasing from the 5 user-only descriptions** → human-facing one-liners
  ("Use when processing an issue in the Needs Input column…" becomes a plain summary; the model no
  longer reads it, so the trigger list is dead weight).
- **The 3 model descriptions are already trigger-shaped** ("Use when…") — keep, but front-load the
  leading word and collapse any one-branch synonyms.
- **`allowed-tools` audit:** `planning-session` carries the `Skill` tool but its body only
  *redirects to* `developer-input` (a stop-and-tell-the-human, not a fire) — confirm it actually
  needs `Skill`, or drop it.
- **No-op sweep** on each body per rubric §5 once the redesigned bodies are stable.

## Router question (open, for #32)

Five user-only skills is near the edge where **cognitive load** wants a **router skill** — one
user-invoked entry point that names the gates (board-cleanup, developer-input, init, plan-review,
sync-worktree) and when to reach each. Decide in #32 against the *redesigned* count; not worth
building against a skill set that's about to change.
