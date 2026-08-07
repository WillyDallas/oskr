---
name: hjarne
description: File durable knowledge into the project brain — distill a note and integrate it (or drain the repo-side inbox) into hjarne's raw/wiki/log. Reach for it after research or a systems discovery, or when another skill needs to persist permanent tech/systems knowledge.
argument-hint: "integrate | drain | register-pointer"
allowed-tools: Bash Read Glob Grep
---

`hjarne` is the project brain (`<workspace>/hjarne`). This skill is its **write seam**:
distil a note into a schema-shaped page, then file it through the `hjarne_*` helpers in
`bin/hjarne-lib.sh`. The helpers are pure filesystem and forge-blind — this skill owns the
**judgement** (what to distil, where it routes, the note-unique provenance); the helpers own
the **bytes**.

## Provenance — the dedup key (contract)

Every note carries a **note-unique** provenance, supplied here at the call site, of the shape
`<issue-or-pr-ref>:<system-slug>` — e.g. `#70:board-dispatcher`, **never** a bare `#70`. Same
provenance → same raw path → a re-file is a no-op (dedup short-circuit). Two notes from one
issue MUST differ in their `:<system-slug>` suffix or the second silently dedups away.
**`clean-up` (T3) honours this exact contract** — it mints a distinct `<ref>:<system>` per note
rather than reusing the issue ref.

## Steps

1. **Distil, don't dump.** Shape the note as a `wiki/` page per `templates/hjarne/schema.md`:
   a `# <Title>` H1, BLUF first, inline citations, `[[wikilinks]]` — but **omit the version
   stamp line**. The helper owns the stamp: `hjarne_write_page` injects
   `> Written <date> · Mode: <deep|quick> · v<N>` under the H1 itself (create → v1, update →
   v<N+1>). Hand it title + body only; a stamp of your own double-stamps the page.

2. **Pick route + subdir.** `<system-slug>` is the wiki page name (`wiki/<system-slug>.md`).
   Pass `research` as the optional subdir for evidence bundles (lands under `raw/research/`);
   omit it for a plain systems note.

3. **Integrate now** — when you hold the note:
   ```bash
   source "${CLAUDE_PLUGIN_ROOT}/bin/harness-lib.sh"   # tail-sources bin/hjarne-lib.sh
   hjarne_integrate '#70:board-dispatcher' board-dispatcher "$CONTENT"   # + optional: research
   ```
   Full signature: `hjarne_integrate <provenance> <system-slug> <content> [subdir] [mode]` —
   mode is `deep` (default) or `quick` and lands in the page stamp; pass `''` for subdir when
   supplying mode alone (e.g. `... "$CONTENT" '' quick`).
   Archives the raw note, writes/updates a version-stamped `wiki/<system-slug>.md`, appends a
   dated `log.md` entry — or no-ops if that provenance was already filed. **The brain is
   optional:** if no brain resolves (no workspace, or the `hjarne/` dir isn't stamped yet),
   integrate stages the note to `docs/brain-inbox/` instead and returns cleanly — the note is
   **never dropped** and the brain is **never auto-created**. Drain it later (step 4).

4. **Or drain the inbox** — when notes were staged repo-side before a brain existed. The inbox
   lives at **`docs/brain-inbox/`**. Stage with
   `hjarne_inbox_stage docs/brain-inbox '<issue-or-pr-ref>:<system-slug>' "$CONTENT"`; later:
   ```bash
   source "${CLAUDE_PLUGIN_ROOT}/bin/harness-lib.sh"
   hjarne_inbox_drain docs/brain-inbox
   ```
   Drain integrates each staged note and removes its file — a dedup short-circuit still counts
   as filed and still clears the file. Drain needs a live (stamped) brain: without one it
   no-ops and leaves the inbox untouched, so nothing is ever dropped.

**Done when:** the note resolves to a version-stamped `wiki/<system-slug>.md`, its raw bytes sit
under `raw/` (or `raw/research/`), and `log.md` has the dated entry — or, when no brain resolved,
it sits in `docs/brain-inbox/` awaiting a drain — or the call dedup-short-circuited because that
provenance was already filed.

## Mode: register-pointer (research auto-ingest)

`research` calls `/hjarne register-pointer` right after it posts its `## Research Digest`
comment. This mode is **L1 depth** — it deposits the digest as a raw *pointer* and logs one
INGEST line. It does **not** distil a `wiki/` page and does **not** stage the inbox; that
distillation stays **clean-up's** job. The digest already lives on the issue, so a no-op here
loses nothing.

Under `/hjarne`'s own unrestricted `Bash`, re-fetch the digest `research` just posted (the
STABLE issue ref is `<topic>` — e.g. `28`, never the mutable title) and hand it to the helper
as `<content>`:

```bash
source "${CLAUDE_PLUGIN_ROOT}/bin/harness-lib.sh"   # tail-sources bin/hjarne-lib.sh
# re-fetch the just-posted "## Research Digest" comment body for issue 28
DIGEST=$(blacksmith_issue_view 28 \
  | jq -r '[.comments[] | select(startswith("## Research Digest"))] | last')
hjarne_register_pointer '28' "$DIGEST" '28'
```

Deposits `raw/research/<topic-slug>-<date>/digest.md` and appends one
`- <date> — INGEST raw/research/<topic-slug>-<date>/ (<ref>)` log line — or no-ops when no brain
resolves (the digest still lives on the issue). Same topic, same day → idempotent (the digest
byte-unchanged, no second INGEST line).

**Done when:** the digest sits at `raw/research/<topic-slug>-<date>/digest.md` with one INGEST
line in `log.md` — or the call no-opped because no brain resolved / the pointer was already filed
today.
