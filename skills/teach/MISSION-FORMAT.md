# Mission Format

The mission is a brain page — `wiki/learning-<topic-slug>-mission.md`, first written
via `hjarne_integrate 'learning/<topic>:mission' 'learning-<topic-slug>-mission' …`,
updated via `hjarne_write_page` (the seam stamps line 2 with `> Written <date> · v<N>`;
never write that line yourself). It captures the _reason_ the user is learning this
topic. Every teaching decision — what to teach next, which resources to surface, which
exercises to design — traces back to this page.

## Template (the content you hand the seam)

```md
# Mission: {Topic}

## Why
{1-3 sentences. The concrete real-world goal. Avoid abstract framings like "to
understand X" — push for the underlying outcome.}

## Success looks like
- {A specific, observable thing the user will be able to do}
- {…}

## Constraints
- {Time, budget, prior commitments, learning preferences}

## Out of scope
- {Adjacent topics the user explicitly is not chasing — protects the zone of
  proximal development}
```

## Rules

- **The H1 is the pinned canonical name.** Line 1 `# Mission: {Topic}` IS the topic's
  canonical name — `learning_list_topics` reads it back so a differently phrased
  re-invocation reconciles to this topic. Set it from the name confirmed at the skill's
  Step 0.5 and keep it stable; renaming it forks the topic.
- **One mission per topic.** Two unrelated goals are two topics.
- **Concrete over abstract.** "Ship a Rust CLI to my team" beats "learn Rust."
- **Push back on vagueness.** If the user cannot articulate why, interview them
  before writing anything. A bad mission is worse than no mission.
- **Revise when reality shifts** — via `hjarne_write_page` (version bump), with a
  learning record capturing the change. Confirm with the user first.
- **Keep it short.** Past a screen, it has stopped being a compass.
