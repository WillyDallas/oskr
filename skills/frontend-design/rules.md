# Rules

Every rule applies in both modes unless marked. *Pitch:* marks where a pitch page differs. Project tokens and decisions override any number here.

## Type

- One family is usually right; two at most, clearly different. The system font is a valid choice for a desktop tool: it's what native apps use. *Pitch:* a deliberate display face earns its place.
- A fixed scale with a ratio of 1.125–1.2, set in rem. No fluid `clamp()` sizes in app UI. *Pitch:* larger ratios and fluid sizes are fine.
- Body size matches the platform: 13px on macOS (minimum 10), 14–16px in a web app. Primary content is never smaller than body.
- Weights 400–700. Nothing at 300 or lighter in UI text.
- Line height 1.4–1.5 for body, 1.1–1.25 for headings. Prose stays under 80 characters per line.
- `font-variant-numeric: tabular-nums` on every number that changes or gets compared: timers, durations, totals, table columns.
- All caps only on labels under one line, with 5–12% letter-spacing, and only when the label earns its place. No letter-spacing changes on body text.
- Monospace only for code and for data people read as code.
- `text-wrap: balance` on headings, `text-wrap: pretty` on paragraphs.

## Color

- Build roles, not a bag of swatches: surface (one or two levels), text (primary, secondary, disabled), border, accent, and the states you need (danger, warning, success). Each one is a token.
- Define ramps in OKLCH. Equal lightness steps then look equally light; lower the chroma near white and black.
- One accent, for the primary action, selection and state only.
- A grey screen with one accent is a default too. If the content has kinds (tracks, categories, calendars), give each kind a hue, and pair it with a second cue (label, icon, position).
- Never use color as the only cue.
- Contrast: at least 4.5:1 for body text, 3:1 for large text, icons and focus rings. Check it with a tool, not by eye.
- Tint neutrals, borders and shadows toward the surface hue. Secondary text on a colored surface is a tint of that hue, not grey.
- Gradients only when they carry information, such as a continuous value or the identity of a block. Never as a wash on chrome, never on text.
- Design dark mode on purpose; don't invert. Lower the chroma, and show elevation with lighter surfaces instead of shadows.

## Layout and spacing

- One spacing scale whose neighboring steps are at least 25% apart (4, 8, 12, 16, 24, 32, 48, 64).
- More space above a heading than below it.
- Group with space first, then a hairline divider, then a background shift. Use a card only for an object people move, open or select, or one that needs to float. Never cards in cards.
- A small radius scale, matched to element size. Nested radii are concentric: outer = inner + padding.
- Shadows only for things that float (menus, popovers, dragged items). Use one light source and layer an ambient and a direct shadow.
- Left-align by default. Center only a lone item, such as an empty state.
- Labels are a last resort: when a value explains itself, drop the `label: value` pair. When a label stays, make it quieter than the value.
- Text-holding flex children get `min-width: 0` and truncate. Test with very long content.
- Layout stays intrinsic as a window resizes. Fixed widths only for sidebars and similar panels.

## Components and states

- Use the component library as it is, themed through tokens. Don't mix two primitive systems in one surface.
- Every interactive element has default, hover, focus-visible, active and disabled states, plus loading and error wherever those can happen.
- Hit targets are at least 24px for a mouse and 44px for touch. Hit areas never overlap.
- The same action looks the same everywhere. If Save looks different in two places, one of them is wrong.
- Destructive actions get a confirm dialog or an undo. Prefer undo for anything frequent.
- Reach for inline editing and popovers before a modal.
- An empty state says what goes here and offers the one action that fills it.
- Icons: one set, stroke matched to the text beside it (1.5px next to 400 weight, 2px next to 600), sized to that text. Outline by default; filled marks the active state. No emoji as icons.
- Badges, dots and pills only for state that can change. A badge that is always "Active" is decoration.
- Tooltips: delay the first one; later ones show at once.
- Loading: show nothing for the first 150ms or so, a spinner or layout-matched placeholder after that, and a progress bar past about 10 seconds.

## Motion

- Set motion by how often the action happens. 100+ times a day: none. Tens of times: minimal, at most 150ms. Occasional (menus, dialogs): 150–250ms. Rare or first-time: room for delight.
- Never animate an action started from the keyboard, or the first render. *Pitch:* one orchestrated entrance is allowed; per-section fade-ins are not.
- Ease-out for entrances, never ease-in, and stay under 300ms.
- Animate `transform` and `opacity` only. Never `transition: all`.
- Popovers grow from their trigger via `transform-origin`, starting at about `scale(0.95)` with opacity 0, never `scale(0)`.
- Use CSS transitions rather than keyframes for state changes, so they stay interruptible.
- Honor `prefers-reduced-motion` and `prefers-reduced-transparency`.

## Copy

- Name things by what the user does, not how the system is built. A user manages notifications, not webhook config. No implementation details in the UI.
- Buttons say what happens: "Save changes", not "Submit". Keep one verb through the flow: "Publish" leads to "Published".
- No heading followed by a paragraph that restates it. No taglines, welcome banners or narration of the UI in a tool.
- A neutral voice. Labels describe state ("Needs review"), not cheer the user ("Needs you!").
- Errors say what happened and how to fix it. They don't apologize, and a raw exception message never reaches the user.
- Sentence case. Use `…` (not `...`) for actions that open a follow-up ("Rename…") and for loading.
- One format per unit across the app (durations, dates, times), locale-aware.

## Desktop shells (Tauri, Electron, any webview app)

- It should behave natively: the standard shortcuts (⌘, for settings, ⌘W, ⌘Q), a menu or palette that lists every command with its shortcut, and shortcuts taught in tooltips and menus.
- The default cursor on buttons and controls; the pointer cursor only on real links. That's the macOS convention.
- `user-select: none` on chrome; text stays selectable where people would copy it.
- `overscroll-behavior: none` on `html` under `@media (pointer: fine)`, so the window doesn't rubber-band.
- Theme the webview's own surfaces from the palette: text selection, caret, scrollbars, focus ring.
- Respond within 100ms. Update optimistically and let the store catch up.
