# Resources Format

The resources page is a brain page — path from `learning_resources_page "<topic>"`,
first written via `hjarne_integrate 'learning/<topic>:resources'
'learning-<topic-slug>-resources' …`, later rewritten via `hjarne_write_page` (the
seam owns the line-2 version stamp). It is the curated set of trusted sources for
the topic AND the ingest queue that persists across sessions.

## Structure (the content you hand the seam)

```md
# {Topic} Resources

## Knowledge

- [Book: _Title_ — Author](https://example.com) <!-- learning:resource id=title-author status=queued -->
  What it covers, in one line. How to use: {the instruction the user gave for this
  source — e.g. "read one chapter before each lesson", "skim §3 only"}.

## Wisdom (Communities)

- [Community name](https://example.com) <!-- learning:resource id=community-name status=queued -->
  Why it is high-signal. How to use: {when to send the user there}.
```

## The queue marker (contract with the learning lib)

Every resource bullet carries, on the bullet line itself:

```
<!-- learning:resource id=<resource-slug> status=queued -->
```

- `id` is a stable lowercase `[a-z0-9-]` slug, unique within the page.
- `status` is exactly `queued` or `ingested`.
- Flip status ONLY via `learning_resource_mark "<topic>" <id> ingested` — never by
  editing the marker. `learning_resource_status "<topic>" <id>` reads it.

## Rules

- **High-trust only.** Primary sources, recognised experts, peer-reviewed work,
  well-moderated communities. Marketing dressed as education stays out.
- **Annotate every entry** — one line on what it covers, plus a `How to use:`
  instruction. A bare link is useless in three months.
- **Surface gaps explicitly** in a `## Gaps` section when the mission needs a
  resource that does not exist yet. This drives future search.
- **Prune ruthlessly** — rewrite the page through `hjarne_write_page`; wrong or
  off-mission resources are removed, not buried.
- **Record community preferences.** If the user opted out of communities, note it
  here so future sessions stop proposing them.
