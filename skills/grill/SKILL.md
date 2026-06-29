---
name: grill
description: Grill a goal into a PRD — a relentless one-question-at-a-time interview that drives to shared understanding of the 11-section Area PRD, with Named Seams as the hard exit. Reach for it from `scope`.
allowed-tools: Read Glob Grep AskUserQuestion
---

**Grill** the developer relentlessly until you share an understanding solid enough to write the PRD. Method (the vendored `productivity/grilling`): walk the design tree, resolving dependencies one at a time. **One question per turn** — asking several at once is bewildering. For each, **recommend your answer**. If a question can be answered by reading the codebase, read it instead of asking.

## Drive toward the PRD's judgment slots

The grill is done when every **judgment** slot below is settled enough that `scope` can synthesize the PRD without re-interviewing. Walk them in dependency order; skip what the digest already settles.

- **Problem** (user's view) · **Solution** (user's view) · **Definition of Done**
- **Named Seams** — the seam(s) a test attaches to. Prefer existing over new, the highest seam, the fewest (ideal: one). **This is the hard exit checkpoint.**
- key **Implementation Decisions** (modules / interfaces / contracts — never file paths) · key **Testing Decisions** (what makes a good test; prior art)
- **Out of Scope** · **Timeline & Effort** · **Placement** (which Epoch milestone + `area/<slug>`)

*User Stories* and the *Task DAG* are **expanded** later (by `scope`'s PRD synthesis / `decompose`), not grilled — never interview for a list a synthesis step can generate.

**Done when:** every judgment slot has shared understanding **and** the developer has explicitly agreed the Named Seams. The settled material lives in the conversation — `scope` synthesizes it directly; the grill writes nothing itself.
