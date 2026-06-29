# Oskr

A config-driven Claude Code harness for agentic project delivery. Oskr (from
Ratatoskr, the squirrel-courier of Yggdrasil) lets Claude Code skills and
subagents drive a project's full workflow — research → planning →
implementation → review — against a project board.

## Backends

Board operations run behind one interface — **the blacksmith** — so the same
workflow runs on **GitHub Projects v2** or **self-hosted Forgejo**, selected per
project by a `forge` key in `harness-config.json`. See
[docs/design/blacksmith.md](docs/design/blacksmith.md).

## Configuration

Each managed project has a `harness-config.json` at its root (or under
`.claude/`). See [docs/harness-config.schema.md](docs/harness-config.schema.md).

## Layout

- `skills/`, `agents/` — the Claude Code skills and subagents the harness ships.
- `bin/` — the shell glue skills shell out to (the blacksmith adapter and the
  board dispatcher live here).
- `docs/design/`, `docs/research/` — architecture decisions and grounding.

## License

MIT. See `LICENSE`.
