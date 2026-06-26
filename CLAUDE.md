# CLAUDE.md — oskr

oskr is a **Claude Code plugin harness** (`.claude-plugin/plugin.json` + `skills/`, `agents/`,
`bin/`). The directory layout *is* the API: the host discovers skills/agents by convention. No
build step; Claude Code is the runtime.

## Versioning — every PR bumps the manifest

**Every PR bumps `version` in `.claude-plugin/plugin.json`.** oskr pins an explicit version, so
Claude Code caches installed plugins by that string — a PR that ships changes without a bump is
invisible to anyone who already installed oskr. The bump *is* the release signal.

- **patch** — fixes, docs, refactors (no new capability)
- **minor** — a new skill, agent, or command (pre-1.0, so minor carries features)
- **major** — first stable release / breaking change to the plugin contract

Full distribution strategy (marketplace catalog, ref pinning): see issue #38 and `CONTRIBUTING.md`.

## Authoring skills

Use the `writing-skills` skill before writing or changing a skill's frontmatter — it owns the
model-invoked-ability vs user-invoked-process distinction and the predictability rubric.
