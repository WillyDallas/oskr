---
name: teach
description: Teach a topic across sessions — seed a mission and resource queue into the brain, then run interactive lessons from the workspace learning domain.
disable-model-invocation: true
argument-hint: "<topic> — what would you like to learn?"
allowed-tools: Bash(source "${CLAUDE_PLUGIN_ROOT}/bin/harness-lib.sh"*) Bash(open *) Bash(mkdir *) Bash(ls *) Bash(date *) Read Write Glob Grep WebFetch WebSearch AskUserQuestion
---

Teaching is stateful — the user learns `$ARGUMENTS` over multiple sessions. All state
survives in two places and ONLY two places:

- **Knowledge state** (mission, resources + ingest queue, glossary, learning records) —
  hjarne pages in the brain, written through the `hjarne_*` seam.
- **Presentation artifacts** (lessons, reference sheets, shared assets) — files under
  the topic directory in the workspace learning domain.

Never store knowledge as loose markdown in the topic directory, and never write
presentation artifacts into the brain.

## Step 0 — Resolve the learning domain (always first)

```bash
source "${CLAUDE_PLUGIN_ROOT}/bin/harness-lib.sh"          # tail-sources hjarne-lib.sh + learning-lib.sh
learning_resolve_root >/dev/null   # loud, instructive refusal outside a workspace
```

The resolver walks to the workspace root — it works from any directory inside the
workspace and never trusts the CWD. **If it fails: STOP.** Relay its stderr
instructions to the user verbatim (cd into a workspace, export `OSKR_WORKSPACE`, or
run `/oskr:oskr-setup`) and write NOTHING — no directory, no page, no artifact.

## Step 0.5 — Name the topic and reconcile (before any write)

The slug that keys every page is derived from a **confirmed canonical name**, never
from the raw `$ARGUMENTS`. A user may type a sentence or a typo (`I want to lear
rust`); do not slug that.

1. **Normalize.** Turn `$ARGUMENTS` into a short canonical topic name — fix typos,
   drop filler (`I want to lear rust` → `Rust`).
2. **Reconcile against existing topics:**
   ```bash
   learning_list_topics   # one line per topic: <slug><TAB><canonical name>
   ```
   Match your normalized name against this list **semantically** — it is a handful of
   entries; read them in-context, no fuzzy library needed.
   - **Match found** → confirm with the user via AskUserQuestion ("Continue your
     existing **Rust** topic?"). On yes, adopt that topic's stored name verbatim.
   - **No match** → propose the canonical name and confirm ("Start a new topic,
     **Rust**?"). On yes, that is the name.
3. **Fix the topic for the session** — only now derive the directory:
   ```bash
   TOPIC="<confirmed canonical name>"
   TOPIC_DIR=$(learning_topic_dir "$TOPIC")
   ```
   Use `$TOPIC` for every `<topic>` reference below, and always brace it in a string
   (`"learning/${TOPIC}:resources"`). Under zsh, `$TOPIC:r…` and `$TOPIC:gl…` are
   modifiers: zsh silently rewrites the provenance. The slug stays stable across
   sessions because the name is **pinned** as the mission page's H1
   (`# Mission: {Topic}`), which `learning_list_topics` reads back — so a differently
   phrased re-invocation reconciles to the same topic instead of forking a duplicate.

Done when: `$TOPIC` is a confirmed canonical name (a continued topic's, or a newly
agreed one), `TOPIC_DIR` echoes `<workspace>/learning/<topic-slug>`, and nothing has
been written yet — or the session ended with the refusal relayed and zero writes.

## The brain contract

Every knowledge write goes through the hjarne seam with a **note-unique** provenance
of the shape `learning/<topic>:<slug>`:

| Page | Provenance | System slug (wiki page) | Format spec |
|---|---|---|---|
| Mission | `learning/<topic>:mission` | `learning-<topic-slug>-mission` | [MISSION-FORMAT.md](./MISSION-FORMAT.md) |
| Resources | `learning/<topic>:resources` | `learning-<topic-slug>-resources` — path from `learning_resources_page "<topic>"` | [RESOURCES-FORMAT.md](./RESOURCES-FORMAT.md) |
| Glossary | `learning/<topic>:glossary` | `learning-<topic-slug>-glossary` | [GLOSSARY-FORMAT.md](./GLOSSARY-FORMAT.md) |
| Learning record NNNN | `learning/<topic>:record-NNNN-<slug>` | `learning-<topic-slug>-record-NNNN-<slug>` | [LEARNING-RECORD-FORMAT.md](./LEARNING-RECORD-FORMAT.md) |

- **First write** of a page: `hjarne_integrate 'learning/<topic>:<slug>' '<system-slug>' "$CONTENT"` —
  archives the raw note, version-stamps the wiki page, logs a dated entry.
- **Brain must exist before seeding** (assume a present brain): teach writes knowledge
  straight to the brain via the direct `hjarne_integrate` path. If the brain directory
  is absent, `hjarne_integrate` silently stages the note to the repo-side inbox instead
  of the wiki page — do NOT rely on that path (a drained inbox note reconstructs its
  page path from the provenance suffix, not the topic's `learning-<slug>-…` system
  slug, so it would not land where `learning_resources_page` expects). Treat an absent
  brain as a precondition failure: STOP, tell the user to initialize the brain first,
  then re-run `/oskr:teach` so the seed writes go through the direct path. Never
  hand-create the page.
- **Update** of an existing page: `hjarne_write_page "<page-path>" "$CONTENT"` then
  `hjarne_log_append "<what changed>"` — never re-`integrate` (same provenance dedups
  to a no-op).
- **Resource queue flips**: ONLY `learning_resource_mark "<topic>" <resource-id> queued|ingested`.
  Never edit a `status=` marker by hand, never `sed` the page, never re-seed to flip status.

## Step 1 — Seed the topic (first session)

1. **Mission interview.** If no mission page exists, interview the user on WHY they
   want this (per MISSION-FORMAT.md — push back on vagueness), then integrate the
   mission page.
2. **Resource drop.** Ask the user for sources AND how to use each one. Each entry
   carries a one-line annotation, a `How to use:` instruction, and the queue marker
   `<!-- learning:resource id=<resource-slug> status=queued -->` (per
   RESOURCES-FORMAT.md). Integrate the resources page.

Done when: mission + resources pages exist in the brain (version-stamped) and every
supplied resource has an id, a How-to-use instruction, and `status=queued`.

## Step 2 — The teaching loop (every session)

1. **Read state first**: the mission page, learning records, glossary, and the queue
   (`learning_resource_status "<topic>" <id>` per resource). Compute the zone of
   proximal development from the records — never from parametric memory of the user.
2. **Ingest before teaching**: pick the next `queued` resource whose How-to-use fits
   the lesson, read/fetch it as its instruction says, then
   `learning_resource_mark "<topic>" <id> ingested`. Ground the lesson in ingested
   resources, with citations — never in parametric knowledge alone.
3. **Author the lesson**: one self-contained HTML file at
   `$TOPIC_DIR/lessons/NNNN-<dash-case-name>.html` (NNNN increments). Short, beautiful
   (think Tufte), one tangible win, tied to the mission, inside the user's zone of
   proximal development. Reuse components from `$TOPIC_DIR/assets/` (a shared
   stylesheet is the first component every topic earns); compress durable knowledge
   into `$TOPIC_DIR/reference/*.html`. Presentation artifacts land under `$TOPIC_DIR`
   and nowhere else — never in the brain, never in the repo. The lesson ends with a
   quiz built per [QUIZ-FORMAT.md](./QUIZ-FORMAT.md) — read it before writing any
   quiz. A "Try it" exercise is exploration: never ask the user to report its results.
4. **Open it for the user**: `open "$TOPIC_DIR/lessons/NNNN-<dash-case-name>.html"`,
   and ask them to paste the quiz's results line into the session when done.
5. **Chat round** — once the results line arrives, before any new lesson. Ask one
   question at a time, answered in the user's own words (no options), with immediate
   feedback after each. At least three, one per slot:
   - **miss** — a wrong pick from the results line; none → the lesson's hardest idea
   - **transfer** — the idea applied to a case the lesson did not show
   - **spaced** — an earlier lesson's idea; a record's **Open** question claims this
     slot first

   Keep asking while answers still reveal something — a miss, a shaky answer, wording
   that drifts from the glossary (correct the wording even when the answer is right).
   Once every slot is asked, stop after two clean answers in a row on the new idea,
   or at about six questions; the user's "more" or "stop" overrides. A question the user moves past unanswered
   goes under **Open** in a record (per LEARNING-RECORD-FORMAT.md).

Done when: the lesson file exists under `$TOPIC_DIR/lessons/`, was opened for the
user, every resource the lesson drew on is marked `ingested`, and the chat round hit
its stop rule — or its unanswered question is saved under **Open**.

## Write gates — records and glossary

Both are gated on **demonstrated understanding**, not coverage:

- **Learning record** (`learning/<topic>:record-NNNN-<slug>`): write one only when the
  user demonstrably understood something non-trivial, disclosed prior knowledge,
  corrected a misconception, or the mission shifted (per LEARNING-RECORD-FORMAT.md).
  The evidence is chat-round answers; a quiz score alone never passes the gate.
  NNNN = highest existing record number for the topic, plus one.
- **Glossary term**: promote a term only when the user can use it correctly.
- **Supersede, never delete**: when a later record contradicts an earlier one, rewrite
  the OLD record's page via `hjarne_write_page`, adding `Status: superseded by
  record-NNNN`, then integrate the new record. When the mission shifts, update the
  mission page (via `hjarne_write_page`) AND write a record — confirm with the user
  first.

Done when: the session's demonstrated learning is captured as record/glossary pages in
the brain, the queue reflects what was actually ingested, and the topic directory
holds only `lessons/`, `reference/`, and `assets/`.
