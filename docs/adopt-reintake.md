# Adopt — full re-intake (harvest → reconcile → re-emit)

The heavy adopt path for a **brownfield** project: take a repo with an off-board
backlog and re-shape it into oskr board structure — one Epoch milestone, phases as
Area umbrellas, slim task issues linked beneath. Use it when `init` adopt detects
existing issues/a board and you choose **full migration** over register-only.

The middle step — **reconcile** — is a **guided checklist done by hand**, not an
automated test. A lot of "what is actually true now" lives only in your head; the
tooling harvests and re-emits, but you decide the shape.

## Step 1 — Harvest (scripted)

Read every existing issue into a reconciliation tasklist:

    adopt-harvest.sh harvest.md

`harvest.md` lists `- [ ] #<n> <title> (<state>)` for each issue (pull requests
excluded). It is your raw material, not the final plan.

## Step 2 — Reconcile (manual — by hand, not an automated test)

Work through `harvest.md` and decide current state. There is no script for this; it
is the developer's judgment call. Produce a `reconciled-plan.json`:

    {
      "epoch": "<project> v1",
      "areas": [
        {
          "slug": "intake",
          "title": "[Area] Patient intake",
          "what": "<end-to-end behavior>",
          "ac": "- [ ] ...",
          "tasks": [
            { "title": "...", "what": "...", "ac": "- [ ] ..." }
          ]
        }
      ]
    }

Reconcile checklist:
- [ ] Collapse each project phase into one Area (`slug` + `[Area] <title>`).
- [ ] Drop dead/won't-do issues; merge duplicates.
- [ ] For each surviving issue, write a slim `## What` + `## AC` (no file paths,
      no TDD-shaped ACs — the per-task plan owns those later).
- [ ] Name the Epoch (the single milestone all Areas share).

## Step 3 — Re-emit (scripted)

Feed the reconciled plan back:

    adopt-reemit.sh reconciled-plan.json

This creates the Epoch milestone, one `type/umbrella` + `area/<slug>` umbrella per
Area, and one `delivery/manual` task per task — each carrying a slim
`## Parent` / `## What` / `## AC` body and linked beneath its umbrella. The board
lands **dispatch off**: nothing is moved into an actionable column, so you review
before any work starts.

> The live coremyotherapy migration is Area 5; this slice builds and fixture-proves
> the capability only.
