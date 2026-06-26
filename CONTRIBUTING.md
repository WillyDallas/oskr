# Contributing

Oskr is in bootstrap. Open issues, but expect heavy churn while the
seed issues on the Oskr board are being executed.

The harness eats its own dog food: Oskr itself is a project under
`~/oskr/project_repos/oskr/` once extraction lands. Contributions
flow through the same Research → Planning → Approval → Ready →
Implementation cycle described in `docs/harness-config.schema.md`.

## Versioning

**Every PR bumps `version` in `.claude-plugin/plugin.json`.** This is a
change-tracking discipline — the bump is a human-readable signal of what each
PR ships.

Use semver judgment (pre-1.0, so minor carries features):
- **patch** (`0.1.0 → 0.1.1`) — fixes, docs, refactors, no new capability.
- **minor** (`0.1.0 → 0.2.0`) — a new skill, agent, or command; any
  user-visible capability.
- **major** (`0.x → 1.0.0`) — reserved for the first stable release / a
  breaking change to the plugin contract.

**Not yet decided: how updates actually reach installed users.** Today oskr
pins an explicit version and Claude Code caches by that string, so a bump is
what would surface an update — but whether we keep pin-and-bump, move to an
unversioned/track-SHA scheme, or pin a marketplace ref is **open in #38**.
Treat the bump as a tracking convention, not a finalized distribution strategy.
