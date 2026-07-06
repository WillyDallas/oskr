# Learning Record Format

Learning records are individual brain pages — the teaching equivalent of ADRs. Record
NNNN for a topic lives at `wiki/learning-<topic-slug>-record-NNNN-<slug>.md`, written
via `hjarne_integrate 'learning/<topic>:record-NNNN-<slug>'
'learning-<topic-slug>-record-NNNN-<slug>' …`. They capture non-obvious lessons, key
insights, and stated prior knowledge, and are the input to the zone of proximal
development.

## Template (the content you hand the seam)

```md
# {Short title of what was learned or established}

{1-3 sentences: what was learned, and why it matters for future sessions.}
```

A record can be a single paragraph. Optional sections only when they add value:
**Status** (`active | superseded by record-NNNN`), **Evidence** (how the user
demonstrated the understanding), **Implications** (what this unlocks or rules out).

## Numbering

NNNN = highest number among existing `learning-<topic-slug>-record-*` pages in the
brain wiki, plus one. Glob the wiki directory; do not keep a counter elsewhere.

## When to write one (the write gate)

Only on demonstrated understanding — never mere coverage:

1. The user demonstrably understood something non-trivial (evidence, not exposure).
2. The user disclosed prior knowledge ("I already know X"), including claimed depth.
3. A misconception was corrected.
4. The mission shifted in response to learning — cross-link and update the mission page.

Not a journal, not a duplicate of a glossary definition.

## Supersession

When a later record contradicts an earlier one, rewrite the OLD record's page via
`hjarne_write_page`, adding `Status: superseded by record-NNNN`. Records are
superseded, never removed — how understanding evolved is itself signal.
