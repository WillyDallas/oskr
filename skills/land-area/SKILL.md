---
name: land-area
description: Land a finished Area to main — once every child PR has merged into the Area branch, roll the umbrella to In Review and open the Area→main PR that `Closes` every child + the umbrella. Reach for it when an Area's child PRs are all merged.
argument-hint: "[umbrella-issue-number]"
allowed-tools: Bash(gh *) Bash(git *) Bash(find-item.sh*) Bash(move-issue.sh*) Bash(list-children.sh*) Bash(base-branch.sh*) Read Grep
---

Land a finished Area. When every child PR has merged into the Area branch, this rolls the umbrella to **In Review** and opens the one consolidated **Area → main** PR whose `Closes` directives retire every child **and** the umbrella on merge. The human reviews that single diff and merges it (GATE 3) — the merge closes everything → Done, and `/clean-up` takes it from there. **Idempotent** — safe to re-run.

> Children rode `Related:` (not `Closes:`) into the Area branch because that's a non-default base. The Area branch → `main` PR *is* on the default branch, so `Closes` fires here — one merge closes the whole Area.

## Steps

1. **Load the Area.** `gh issue view <umbrella> --json number,title,body,labels`; confirm it carries `type/umbrella` (else stop — not an Area). Resolve:
   - children — `list-children.sh <umbrella>` → `[ {number,state,…} ]`;
   - the Area branch — `AREA=$(base-branch.sh <umbrella>)` (the umbrella's own recorded marker);
   - the trunk — `MAIN` from config `.base_branch` (default `main`). If `AREA == MAIN`, stop: this Area has no branch to land.

2. **Verify every child has landed on the Area branch.** A child has landed when its PR is merged into `$AREA`:
   ```bash
   gh pr list --base "$AREA" --state merged --json number,headRefName --jq '.[].headRefName'
   ```
   Match each child to its `feature/<child#>-*` head branch. If any child has no merged PR into `$AREA`, **STOP** and report the unlanded ones (e.g. "#x, #y aren't merged into `$AREA` yet — merge their PRs first, then re-run"). Never open the trunk PR for a half-finished Area.
   *(Backend note: `gh pr list --base` is GitHub-only; the Forgejo equivalent is a follow-up — the same coupling the other delivery skills carry.)*

3. **Open the Area → main PR** (skip cleanly if one already exists — `gh pr list --head "$AREA" --base "$MAIN" --state open`):
   ```bash
   git push -u origin "$AREA"
   gh pr create --head "$AREA" --base "$MAIN" --title "<Area title>" --body "$(cat <<EOF
   ## <Area title>
   [2–3 line summary drawn from the umbrella PRD]

   Closes #<umbrella>
   Closes #<child1>
   Closes #<child2>
   EOF
   )"
   ```
   **One `Closes #N` per line**, the umbrella plus every child — on merge to `main` (the default branch) they all auto-close.

4. **Roll the umbrella to In Review:** `move-issue.sh "$(find-item.sh <umbrella>)" "In Review"`.

5. **Report the PR URL** and stop. The human reviews the consolidated Area diff and merges it (GATE 3); that merge closes every issue → Done. Tell them to run `/clean-up` afterward to reconcile docs and archive the cards.

**Done when:** every child PR is merged into the Area branch, exactly one open `Area→main` PR exists whose body `Closes` every child **and** the umbrella, and the umbrella is in **In Review** — OR the run STOPPED with a clear list of children not yet landed.
