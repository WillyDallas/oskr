---
name: sync-worktree
description: Use before starting or resuming implementation work on a feature branch or worktree to bring it up to date with the base branch. Merges origin/<base> into the current branch via the canonical script; refuses on conflict, dirty tree, or divergence. Not for the base branch itself — that's sync-development.sh.
allowed-tools: Bash(sync-worktree.sh*) Bash(git status*) Bash(git log*) Bash(git merge*)
---

Bring the current feature branch up to date with the base branch's origin (`origin/<base>`, where `<base>` comes from `harness-config.json`'s `.base_branch`, default `main`).

Run exactly this — do not modify the command or reimplement its logic inline:

```bash
sync-worktree.sh <context-label>
```

`<context-label>` is the calling skill or session name (e.g. `execute-plan`, `manual`). The script prints one machine-readable token on stdout:

| Token | Exit | Meaning | What you do |
|-------|------|---------|-------------|
| `in-sync` | 0 | Branch already contains all of the base | Proceed |
| `merged` | 0 | Merge commit landed; branch is current | Proceed |
| `on-base` | 1 | You are on the base branch, not a feature branch | Use `sync-development.sh` instead |
| `dirty` | 1 | Uncommitted tracked changes | Stop. Commit or stash first — never discard |
| `diverged` | 1 | Local base branch has commits not on origin | Stop. Surface to the developer; do not work around it |
| `offline-stale` | 1 | Fetch failed | Stop. Surface; the base cannot be trusted as current |
| `conflict` | 1 | Merge conflicts; merge was aborted, branch unchanged | Stop. Surface to the developer with the conflicting files (`git merge origin/<base>` to reproduce) |

On any exit 1, stop and tell the developer what happened. Never resolve conflicts autonomously, never `git reset --hard` or `git checkout -f` to force a clean state.

## Gotchas

- A `merged` result creates a merge commit on the feature branch. That is expected and does not pollute scope-fencing — `git log <base>..HEAD` still shows only feature work.
- `diverged` refers to the local base branch, not your feature branch. It is a stop-everything repo-health signal even though this script merges `origin/<base>` directly.
- Fresh branches created by `execute-plan` come from a just-synced base, so `in-sync` is the normal result there; the step earns its keep in resume mode and long-running sessions.
