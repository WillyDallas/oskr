# Tells

Each item below is fine when the brief or the grammar chose it. It's a tell when it shows up because nothing else was chosen. The specific tells change with each model generation (purple was 2025's); the principle in each heading is what lasts.

## Palette: from tokens chosen for this product

1. Indigo or violet gradients and colored glows ("vibe-code purple").
2. Warm cream (near `#F4F1EA`), a high-contrast serif and a terracotta accent (near `#D97757`). This is where Claude lands when told to avoid #1.
3. Near-black with a single acid-green or vermilion accent.
4. Broadsheet: hairline rules, zero radius, dense newspaper columns.
5. Neobrutalism: thick black borders and hard offset shadows on cards, another fallback when told to avoid the others.
6. The SaaS-card kit: identical rounded cards, one radius on everything, the same `rgba(0,0,0,.1)` shadow under each, gradient washes.
7. Untouched shadcn or Tailwind defaults: zinc greys, the default radius, the default ring.
8. Many unrelated accent colors on one screen, none of them meaning anything.

## Type: chosen for the reading, not the mood

- Inter at thin weights, everywhere.
- Monospace (JetBrains Mono, IBM Plex Mono) on text that isn't code.
- One italic or colored word inside a headline.
- The "approved alternatives" set: Space Grotesk, Instrument Serif, Geist.
- A tracked all-caps eyebrow, often monospace, above every heading.
- Primary content set smaller than body size; grey body text on a dark background.

## Structure: structure is information

- Cards everywhere, cards inside cards.
- A row of KPI or stat cards at the top of every dashboard.
- Grids of identical cards with an icon on top.
- A colored border on one side of cards or list items (the "fingernail"), wider than 1px.
- Glass and blur panels, colored glows, a 1px border paired with a 40px blurred shadow.
- Badges, pills or pulsing dots for a state that never changes.
- Happy path only: no empty, loading or error state, so a raw error message or a blank panel reaches the user.
- Small misalignments: an icon off its text baseline, a divider after the last item, text spilling out of a button.

## Ornament: delete it unless it encodes something

- Meta strings joined with middle dots (`A · B · C`), and labels shaped `WORD — fragment`.
- `//` separators, and `01 / 02 / 03` numbering on things that aren't a sequence.
- `→` appended to every button and link.
- Emoji used as icons; ✨ on anything "smart".
- Grid-paper backgrounds, fake terminal windows, retro computer styling.

## Copy: one job per string

- A heading with a paragraph explaining it.
- Taglines, welcome banners ("Welcome back, Sam ✨") and slogans inside a tool.
- Narration that tells people how to use the screen in front of them.
- Second-person cheering ("Needs you!") where a neutral state belongs ("Needs review").
- Implementation leaking into labels ("Saved to IndexedDB"), and reassurance repeated on every screen ("Your data never leaves your device").
- Title Case Labels and em dashes scattered through UI text.
- Hype verbs (elevate, seamless, supercharge, unlock), filler stats, suspiciously round numbers.

## Motion: answers to an action

- Fade-and-slide-up on every section, staggered entrances on load, reveals as you scroll.
- A hover lift on every card.
- Pulsing or shimmering with no state behind it.

## Pitch-page only

- A centered hero with a badge above the headline; a big number with a small label and a gradient accent.
- A logo wall, a numbered "how it works" row, three pricing cards with the middle one highlighted.

## Second-order slop

Dodging a tell by reaching for its opposite produces the next tell: purple becomes cream, Inter becomes Space Grotesk, cards become hairline broadsheet. Go back to the grammar instead.

**Silhouette test:** blur a screenshot down to its block outline. If it could be anyone's app, the structure is still a default.
