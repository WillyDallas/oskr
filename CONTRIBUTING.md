# Contributing

Oskr is in bootstrap. Open issues, but expect heavy churn while the
seed issues on the Oskr board are being executed.

The harness eats its own dog food: Oskr itself is a project under
`~/oskr/project_repos/oskr/` once extraction lands. Contributions
flow through the same Research → Planning → Approval → Ready →
Implementation cycle described in `docs/harness-config.schema.md`.

## Versioning

**Every PR bumps `version` in `.claude-plugin/plugin.json`.** Oskr pins an
explicit version, so Claude Code caches installed plugins by that string — a
PR that ships changes without a bump is invisible to anyone who already
installed oskr (they see no update). The bump *is* the release signal.

Use semver judgment (pre-1.0, so minor carries features):
- **patch** (`0.1.0 → 0.1.1`) — fixes, docs, refactors, no new capability.
- **minor** (`0.1.0 → 0.2.0`) — a new skill, agent, or command; any
  user-visible capability.
- **major** (`0.x → 1.0.0`) — reserved for the first stable release / a
  breaking change to the plugin contract.

See #38 for the full distribution strategy (marketplace catalog, ref pinning).
