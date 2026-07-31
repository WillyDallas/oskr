---
name: land-area
description: Land a finished Area to main — once every child PR has merged into the Area branch, roll the umbrella to In Review and open the Area→main PR that `Closes` every child + the umbrella. Reach for it when an Area's child PRs are all merged.
argument-hint: "[umbrella-issue-number]"
allowed-tools: Bash(source bin/harness-lib.sh*) Bash(git *) Bash(find-item.sh*) Bash(move-issue.sh*) Bash(list-children.sh*) Bash(base-branch.sh*) Read Grep AskUserQuestion
---

Land a finished Area. When every child PR has merged into the Area branch, this rolls the umbrella to **In Review** and opens the one consolidated **Area → main** PR whose `Closes` directives retire every child **and** the umbrella on merge. The human reviews that single diff and merges it (GATE 3) — the merge closes everything → Done, and `/clean-up` takes it from there. **Idempotent** — safe to re-run.

> Children rode `Related:` (not `Closes:`) into the Area branch because that's a non-default base. The Area branch → `main` PR *is* on the default branch, so `Closes` fires here — one merge closes the whole Area.

## Steps

1. **Load the Area.** `source bin/harness-lib.sh && blacksmith_issue_view <umbrella>`; confirm `.labels` carries `type/umbrella` (else stop — not an Area). Resolve:
   - children — `list-children.sh <umbrella>` → `[ {number,state,…} ]`;
   - the Area branch — `AREA=$(base-branch.sh <umbrella>)` (the umbrella's own recorded marker);
   - the trunk — `MAIN` from config `.base_branch` (default `main`). If `AREA == MAIN`, stop: this Area has no branch to land.

2. **Verify every child has landed on the Area branch.** A child has landed when its PR is merged into `$AREA`:
   ```bash
   blacksmith_pr_list_merged "$AREA" | jq -r '.[].headBranch'
   ```
   Match each child to its `feature/<child#>-*` head branch. If any child has no merged PR into `$AREA`, **STOP** and report the unlanded ones (e.g. "#x, #y aren't merged into `$AREA` yet — merge their PRs first, then re-run"). Never open the trunk PR for a half-finished Area.

3. **Bump the manifest version on the Area branch** so the bump rides in the Area→main PR. Per CLAUDE.md, every Area→main PR carries exactly one deliberate bump to `.claude-plugin/plugin.json`, sized to the whole batch — **patch** (fixes/docs/refactors, no new capability), **minor** (a new skill/agent/command — pre-1.0 so minor carries features), or **major** (first stable release / breaking the plugin contract). Children never bump, so it lands here:
   ```bash
   # bump version in .claude-plugin/plugin.json (e.g. 0.7.0 -> 0.8.0), then:
   git commit -am "chore(release): bump plugin to <new> for <area> (#<umbrella>)"
   git push -u origin "$AREA"
   ```
   **Idempotent:** if `$AREA`'s `.claude-plugin/plugin.json` version already differs from `origin/$MAIN`, the bump is done — skip the edit and just ensure the branch is pushed. If `$AREA` is checked out in a sibling worktree (can't `git checkout` it here), commit the one-line bump straight onto `$AREA` via the forge contents API instead.

4. **Open the Area → main PR** (skip cleanly if one already exists — `blacksmith_pr_open_exists "$AREA" "$MAIN"` exits 0 when an open Area→main PR is already there). The branch is already pushed from step 3:
   ```bash
   blacksmith_pr_create "$AREA" "$MAIN" "<Area title>" "$(cat <<EOF
   ## <Area title>
   [2–3 line summary drawn from the umbrella PRD]

   Closes #<umbrella>
   Closes #<child1>
   Closes #<child2>
   EOF
   )"
   ```
   **One `Closes #N` per line**, the umbrella plus every child — on merge to `main` (the default branch) they all auto-close.

5. **Roll the umbrella to In Review:** `move-issue.sh "$(find-item.sh <umbrella>)" "In Review"`.

6. **Report the PR URL.** The human reviews the consolidated Area diff and merges it (GATE 3); that merge closes every issue → Done. Tell them to run `/clean-up` afterward to reconcile docs and archive the cards.

7. **Offer a comprehension quiz** — optional, never assumed. Ask via `AskUserQuestion`: "Want a quick comprehension quiz on what this Area changed?" On yes, quiz them in-conversation, grounded in the Area diff (`git diff $MAIN...$AREA`) and the umbrella PRD — a handful of questions on what shipped, what changed shape, and what to watch; give immediate feedback per answer. On no, stop without comment.

**Done when:** every child PR is merged into the Area branch, the Area branch carries the single manifest version bump, exactly one open `Area→main` PR exists whose body `Closes` every child **and** the umbrella, the umbrella is in **In Review**, and the quiz was offered — OR the run STOPPED with a clear list of children not yet landed.
