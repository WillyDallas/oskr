---
name: sync-worktree
description: Use before starting or resuming implementation work on a feature branch or worktree to bring it up to date with the base branch. Merges origin/<base> into the current branch via the canonical script; refuses on conflict, dirty tree, or divergence. Not for the base branch itself — that's "${CLAUDE_PLUGIN_ROOT}/bin/sync-development.sh".
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/bin/sync-worktree.sh"*) Bash(git status*) Bash(git log*) Bash(git merge*)
---

Bring the current feature branch up to date with the base branch's origin (`origin/<base>`, where `<base>` comes from `harness-config.json`'s `.base_branch`, default `main`).

Run exactly this — do not modify the command or reimplement its logic inline:

```bash
"${CLAUDE_PLUGIN_ROOT}/bin/sync-worktree.sh" <context-label>   # context-label = the calling skill or session, e.g. execute-plan, manual
```

The script prints one machine-readable token on stdout (`in-sync | merged | on-base | dirty | diverged | offline-stale | conflict`) and explains itself on stderr. Exit 0 — proceed. Exit 1 — stop and relay the script's stderr note to the developer; it names the fix. Never resolve conflicts autonomously, never `git reset --hard` or `git checkout -f` to force a clean state.

## Gotchas

- A `merged` result creates a merge commit on the feature branch. That is expected and does not pollute scope-fencing — `git log <base>..HEAD` still shows only feature work.
- `diverged` refers to the local base branch, not your feature branch. It is a stop-everything repo-health signal even though this script merges `origin/<base>` directly.
- Fresh branches created by `execute-plan` come from a just-synced base, so `in-sync` is the normal result there; the step earns its keep in resume mode and long-running sessions.
