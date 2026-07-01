# Contributing

Oskr is in bootstrap. Open issues, but expect heavy churn while the
seed issues on the Oskr board are being executed.

The harness eats its own dog food: Oskr itself is a project under
`~/oskr/project_repos/oskr/` once extraction lands. Contributions
flow through the same Research → Planning → Approval → Ready →
Implementation cycle described in `docs/harness-config.schema.md`.

## Versioning

**The Area→main PR bumps `version` in `.claude-plugin/plugin.json`** — one
deliberate bump per Area, sized to the whole batch. **Child PRs within an Area do
not bump**: they inherit the Area baseline and leave the version untouched. The
bump is a human-readable signal of what each *release* (Area landing) ships.

Use semver judgment (pre-1.0, so minor carries features):
- **patch** (`0.1.0 → 0.1.1`) — fixes, docs, refactors, no new capability.
- **minor** (`0.1.0 → 0.2.0`) — a new skill, agent, or command; any
  user-visible capability.
- **major** (`0.x → 1.0.0`) — reserved for the first stable release / a
  breaking change to the plugin contract.

**Why children don't bump.** When several child slices branch in parallel off one
Area branch, they all fork from the same version. Per-child bumps then collide on
the manifest line — a guaranteed merge conflict on every second merge — and the
numbers encode plan-authoring order, not real relative size. Deferring the single
bump to land-area removes that conflict class and lets one number describe what
actually reaches users.

**Not yet decided: how updates actually reach installed users.** Today oskr
pins an explicit version and Claude Code caches by that string, so a bump is
what would surface an update — but whether we keep pin-and-bump, move to an
unversioned/track-SHA scheme, or pin a marketplace ref is **open in #38**.
Treat the bump as a tracking convention, not a finalized distribution strategy.

## Developing oskr: dev vs installed

oskr lives at `projects/oskr` inside the workspace **and** is the plugin Claude Code
loads — a deliberate self-hosting recursion. So "I edited a skill" must not silently
change every workspace operation.

**The installed/pinned plugin is the default.** Working *on* oskr is a deliberate
`--plugin-dir projects/oskr` launch, never ambient:

    claude --plugin-dir projects/oskr     # load the dev checkout in-place for this session

Do not leave both enabled. A `--plugin-dir` dev copy does **not** replace a
marketplace-cached copy — both can be enabled at once, a **double-enable** collision
that yields duplicate `/oskr:*` skills and two `bin/` dirs on `PATH` with ambiguous
precedence.

**Which copy is active?** Run the doctor:

    bin/doctor.sh

It reads `$CLAUDE_PLUGIN_ROOT` and `$PATH` and reports whether the active copy is a
**dev** checkout or the **installed** marketplace cache (`~/.claude/plugins/cache`),
and exits non-zero with a warning if it detects a double-enable collision.
