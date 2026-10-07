---
name: frontend-design
description: Design UI that reads as chosen, not defaulted — reach for it before building, restyling or reviewing any interface (app screen, component, page, HTML mock).
---

Generated UI looks generic because every choice nobody pinned falls back to the most common one: Inter, indigo, identical rounded cards under the same grey shadow, a heading with a paragraph explaining it. That is **slop**: not a style, but defaults nobody chose. Banning one default moves the model to the next (told to avoid purple, it lands on cream, serif and terracotta). What works is a **grammar**, a concrete system to work inside, plus restraint and a real look at the result.

## Name the mode first

- **Tool:** the person is doing a task. App screens, dashboards, editors, settings. Familiar beats distinctive: layout, navigation and controls stay conventional, and character comes from palette, type, copy and one signature detail. A tool's first-run and empty states are still the tool.
- **Pitch:** the page has to persuade. Landing, marketing, portfolio. More room for expression, and `tells.md` is where most of the risk sits.

## Steps

1. **Find the grammar.** Name the job each screen does in the user's words ("decide what to change next week"), not its genre ("analytics dashboard"); the genre pulls in the genre's defaults. Then read what the project already pins: design docs, decision logs, token files (CSS variables, Tailwind `@theme`), existing components. Pinned choices win over everything in this skill, including a look `tells.md` lists. Where nothing is pinned, pick one source, not a blend, and say which: the platform's guidelines (macOS HIG, Fluent, GNOME HIG) for a desktop tool, the project's component library themed on purpose, or a reference the user names. *Done when* color, type, spacing, radius, elevation and motion each have a named source.
2. **Write the tokens before code.** 4–6 color roles with values, a type scale with sizes and weights, one spacing scale, one radius scale, elevation levels, durations, and density (row height, padding) stated outright, since "too much whitespace" and "too little" are both common complaints. Put them where code reads them. *Done when* every value the UI uses is a token and no component holds a raw hex, arbitrary px or inline style.
3. **Write the copy before layout.** List every heading, label, button, empty state and error, then apply the copy rules in `rules.md`. *Done when* each string does one job and none restates its neighbor.
4. **Check the plan against `tells.md`.** For each choice that matches a listed default and wasn't pinned in step 1, change it or write one line on why it fits this brief. Fix a tell by returning to the grammar, never by grabbing its nearest opposite. Record each look you rejected and why in the project's design doc, because a later session can't see this one and will bring it back. *Done when* every match is changed or justified and the rejections are written down.
5. **Build from the project's components and tokens,** applying every rule in `rules.md` for the mode. Use the library's components as they are, themed through tokens; don't rebuild focus or keyboard behavior, and don't fight the system with `!important` or one-off classes. *Done when* every rule for the mode holds, or you've named the one you broke and why.
6. **Look at it.** Render each screen (browser, screenshot, or the running app) in its empty, typical, very long, loading and error states. Fix everything you see in one batch, look once more, stop. *Done when* every screen was seen in each state that can occur, or you've said which you couldn't render. Never claim a visual check you didn't do.

Reviewing existing UI rather than building: run steps 4 and 6 against it and report in the format in `review.md`.

## Principles behind every rule

- **Structure is information.** Every border, color, badge, icon, number and label encodes something about the content. If removing it loses nothing, remove it.
- **Spend boldness in one place.** One memorable element per screen; everything around it quiet.
- **Emphasize by de-emphasizing.** Dim what competes instead of enlarging what matters.
- **Color carries meaning.** Accent for the primary action, selection and state; a second hue only to tell categories apart; never the only cue.
- **Motion answers the person.** It shows what changed or where something went. Nothing animates on load (a pitch page may have one entrance) or on actions done many times a day.
- **Boring competence wins in tools.** A user should trust every control on sight. Strangeness without purpose is a tool's failure mode, as flatness is a pitch page's.

Mechanical checks (raw colors outside tokens, `transition: all`, `outline: none` with no replacement, `...` for `…`) belong in a linter once they've been missed twice; this skill carries the judgment. Sources are in `sources.md`.
