# CLAUDE.md — oskr

oskr is a **Claude Code plugin harness** (`.claude-plugin/plugin.json` + `skills/`, `agents/`,
`bin/`). The directory layout *is* the API: the host discovers skills/agents by convention. No
build step; Claude Code is the runtime.

## Versioning — the land-area PR bumps the manifest

**Every Area→main PR bumps `version` in `.claude-plugin/plugin.json`** — one deliberate bump per
Area, sized to what the whole batch ships. Child PRs within an Area **do not** bump: they inherit
the Area baseline and leave the version untouched. Nothing reaches an installed user until the Area
lands, so a version is a release signal for the Area, not for its internal integration steps.

- **patch** — fixes, docs, refactors (no new capability)
- **minor** — a new skill, agent, or command (pre-1.0, so minor carries features)
- **major** — first stable release / breaking change to the plugin contract

**Why children don't bump:** when N children branch in parallel off one Area branch they all fork
from the same version, so per-child bumps collide on the manifest line (a guaranteed merge conflict
every second merge) and encode plan-authoring order rather than real size. Deferring the single bump
to land-area removes that conflict class entirely.

This is a tracking convention, **not a finalized update strategy** — how updates reach installed
users (pin-and-bump vs unversioned/track-SHA vs marketplace ref) is open in #38.

## Authoring skills

Use the `writing-skills` skill before writing or changing a skill's frontmatter — it owns the
model-invoked-ability vs user-invoked-process distinction and the predictability rubric.
