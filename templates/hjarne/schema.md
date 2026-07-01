# Schema — the wiki page contract

Every page under `wiki/` follows the same shape so the brain — and you — can
read it, link it, and trust it. This is the layer-3 page contract.

## Required shape

1. **Title** — a single `# <Topic>` H1.
2. **Version stamp** — a blockquote directly under the title recording when the
   page was last written and in which mode, plus a version number:
   `> Written 2026-07-01 · Mode: deep · v1`.
   Bump the version and the date on every material rewrite.
3. **BLUF** — Bottom Line Up Front. The first paragraph states the answer or
   claim in 1–3 sentences, before any supporting detail. A reader who stops
   after the BLUF should still walk away with the takeaway.
4. **Body** — the supporting detail: prose, tables, steps.
5. **Sources** — a trailing `## Sources` section resolving every citation.

## Conventions

- **Inline citations.** Every non-obvious claim carries a bracketed marker —
  `[1]`, `[2]` — resolved in the `## Sources` section. No uncited assertions.
- **`[[wikilinks]]`.** Link related pages with `[[wikilinks]]` (Obsidian-style),
  not bare relative paths, so backlinks and the graph stay intact.
- **Distill, don't dump.** `raw/` holds sources verbatim; `wiki/` holds the
  distilled, linked version you actually read. The brain reads `raw/`, never
  rewrites it.

## Page skeleton

```markdown
# <Topic>

> Written <YYYY-MM-DD> · Mode: <deep|quick> · v<N>

<BLUF: the answer in 1–3 sentences.>

## <Section>

<Detail, with an inline citation where it matters [1].> Related: [[other-page]].

## Sources

[1] <author / outlet, title, URL, date accessed>
```
