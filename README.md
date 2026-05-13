# Oskr

A general-purpose Claude Code harness for agentic project workflows.

Oskr (from Ratatoskr, the squirrel-courier of Yggdrasil) is a config-driven
harness that lets Claude Code subagents drive a project's full delivery
workflow — research, planning, implementation, review — against a GitHub
Projects v2 board.

## Status

Bootstrap. The harness currently lives inside the
[Wonderloom](https://github.com/Wonderloom-books/wonderloom) project. Extraction
to this repo is tracked in the seeded issues on the Oskr board.

## Architecture

See `docs/harness-config.schema.md` for the per-project configuration schema.
The canonical harness spec (board workflow, agents, skills, dispatcher)
will be ported from Wonderloom's `docs/Architecture/harness.md` as part
of the agent/skill extraction issues.

## License

MIT. See `LICENSE`.
