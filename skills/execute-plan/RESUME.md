# Resume mode — continuing a dead dispatch

You are here because a branch matching `feature/<NUMBER>-*` already exists (typically the issue carries the `dispatch-incomplete` label from a prior dispatch that died mid-run). Do NOT create a new branch or restart from task 1.

```bash
git checkout feature/<NUMBER>-<existing-slug>
git log --oneline "$BASE_BRANCH"..HEAD   # what already landed
```

Read the issue's `## Dispatch Incomplete` comment (if present) for where the prior run stopped, map the existing commits against the plan's task list, and continue from the first task without a corresponding commit. Re-run the project's type-check command (per CLAUDE.md) before resuming to confirm the inherited state is sound. If the branch exists but has zero commits, treat it as a fresh start on that branch.

After the PR opens, Completion step 3 clears the `dispatch-incomplete` label.

Return to SKILL.md at **Sync the worktree**.
