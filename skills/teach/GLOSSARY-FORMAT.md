# Glossary Format

The glossary is a brain page — `wiki/learning-<topic-slug>-glossary.md`, first written
via `hjarne_integrate 'learning/<topic>:glossary' 'learning-<topic-slug>-glossary' …`,
updated via `hjarne_write_page`. It is the canonical language for the topic: every
lesson, reference sheet, and learning record adheres to its terminology.

## Structure (the content you hand the seam)

```md
# {Topic} Glossary

{One or two sentences on what this glossary covers.}

## Terms

**Hypertrophy**:
Muscle growth driven by mechanical tension and metabolic stress over repeated
training sessions.
_Avoid_: Bulking, getting big
```

## Rules

- **Add a term only when the user understands it.** The glossary records compressed
  knowledge — it is not a dictionary the user reads to learn. Wait until they can use
  the term correctly (this is the write gate).
- **Be opinionated.** One best word per concept; the rest listed as aliases to avoid.
- **Keep definitions tight.** One or two sentences; what the term IS.
- **Use the glossary's own terms inside definitions.**
- **Group under subheadings** when clusters emerge; flat is fine when terms cohere.
- **Flag ambiguities explicitly** ("in this topic, 'set' always means a working set").
- **Revise as understanding deepens** — update in place via `hjarne_write_page`
  (version bump); no stale entries.
