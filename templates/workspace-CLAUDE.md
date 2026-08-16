# {{WORKSPACE_NAME}} workspace — oskr-managed

Every project under `projects/` is tracked on a project board via the oskr
plugin. This file exists so sessions use the plugin's tooling instead of
improvising API calls.

## Board operations — use the blacksmith, never raw HTTP

All issue/board reads and writes go through the oskr harness library. The
installed plugin lives in a **version-keyed** cache directory, so resolve the
newest one instead of hard-coding a version. **Source it from inside the
project (or workspace) directory** — it finds the workspace `.env` by walking
up from `$PWD` at source time, once per shell, so sourcing from elsewhere
silently skips the tokens:

```bash
cd <project dir>                     # BEFORE sourcing, not after
OSKR_BIN=$(ls -d ~/.claude/plugins/cache/oskr-marketplace/oskr/*/bin | sort -V | tail -1)
source "$OSKR_BIN/harness-lib.sh"    # auto-loads the workspace .env (tokens)
blacksmith_issue_view 21             # also: _issue_comment, _issue_add_label, _move_issue, …
```

- Secrets live in the workspace-root `.env`; `harness-lib.sh` loads them
  automatically at source time. Never source `.env` by hand or go hunting
  through parent directories for env files.
- Forgejo returns 404 "The target couldn't be found" for **unauthenticated**
  requests to private repos. If an issue you expect 404s, it is an auth
  failure, not a missing issue.
- For full workflows (scoping, planning, executing, landing), invoke the oskr
  skills (`/oskr:scope`, `/oskr:planning-session`, `/oskr:execute-plan`,
  `/oskr:land-area`) rather than ad-hoc commands.
