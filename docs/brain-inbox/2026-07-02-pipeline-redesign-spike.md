<!-- pending migration to the brain (#28) -->

# Multi-agent design-pass method (from spike #32)

A repeatable method for design spikes where the solution space is wide and one
iterated attempt anchors too early:

1. **Compete** — generate 4 independent designs from different angles (here: two
   external references — mattpocock's `grilling`→`to-prd`→`to-issues` and
   story-spark's `scope-milestone`/`create-issue`/`daily-standup` — plus variants
   grounded in the current system).
2. **Judge** — a scoring pass picks the strongest skeleton rather than averaging
   them.
3. **Transpose** — re-express the winner in the target system's native concepts
   (don't import the source's vocabulary).
4. **Adversarial critique** — 4 independent critique lenses attack the transposed
   design.
5. **Synthesize** — fold surviving critique into the final design.

Why it works: competition beats iteration when the space is wide; transposition
prevents cargo-culting an external shape; adversarial critique catches
plausible-but-wrong structure before it's committed.

Two reusable design principles the spike settled alongside the method:

- **Ability / stage / gate** — classify every capability as exactly one of:
  model-reachable on-demand ability, pipeline stage, or human decision gate.
  Gates get a hardness (hard = always human; soft = default-proceed, human may
  intervene). Place the hard gates at the points of no return.
- **Altitude contract** — the durable artifact owns WHAT (behavioral, seams);
  the ephemeral artifact owns HOW (paths, signatures, step order). The routing
  test: *if it can go stale, it's the plan.*

Source: oskr spike #32 resolution (2026-06-30),
https://github.com/WillyDallas/oskr/issues/32
