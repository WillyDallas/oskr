# hjarne — the project brain

`hjarne` is the durable knowledge base for an oskr workspace: where permanent
systems and tech knowledge lives, distilled and linked, so future work reads it
instead of relearning it. It follows Andrej Karpathy's LLM-wiki pattern — drop
sources into `raw/`, let the brain agent distill them into a clean, linked `wiki/`.

> This directory is a **template**. `bin/hjarne-skeleton.sh` stamps it into a
> workspace's `hjarne/` directory. The skeleton ships empty; the brain fills it.

## Layout

| Path | What lives here | Who maintains it |
|---|---|---|
| `raw/` | Sources, verbatim — articles, transcripts, digests, notes | Dropped in; never rewritten |
| `raw/research/` | Research evidence bundles, one folder per digest | Brain agent |
| `wiki/` | Distilled, linked Markdown — the pages you actually read | Brain agent, from `raw/` |
| `projects/` | Per-project knowledge subtrees | Brain agent |
| `log.md` | Append-only timeline of ingests and maintenance passes | Brain agent |
| `schema.md` | The wiki page contract (BLUF, citations, `[[wikilinks]]`, version stamp) | — |
| `todo.md` | Open threads the brain still owes work on | Brain agent |

The structure is **conceptual, not literal**. Each project's knowledge lives in
its own **project-named** subtree under `projects/` (for example
`projects/<project-name>/`), while `wiki/` holds **cross-cutting** knowledge that
spans projects. The paths above are the concrete skeleton the stamp helper
writes; grow them as each project needs.

## Where each artifact lives (the boundary)

Not everything belongs in the brain. The workspace separates durable knowledge
from time-bound delivery tracking:

| Artifact | Home |
|---|---|
| **Area PRD** | The umbrella **issue body** — not the brain. |
| **Per-task plan** | The repo's `docs/plans/` tree — **never the brain**. |
| **Research digest** | An **issue comment**, with an optional pointer back into the brain. |
| **Permanent systems / tech knowledge** | the brain owns the write. When no brain exists yet, it lands repo-side at `docs/brain-inbox/<date>-<system>.md` (pending #28). |

Rule of thumb: time-bound delivery state (PRDs, per-task plans, research
digests) stays on the board and under `docs/`; permanent, reusable knowledge is
what hjarne keeps for the long run.
