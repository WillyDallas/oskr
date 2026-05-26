---
name: research-session
description: Use when an issue in the Backlog or Research column needs investigation. Runs the researcher → research-reviewer scope-then-execute loop. Posts findings with either clarifying questions or an approval-to-proceed request, then moves the issue to Needs Input.
argument-hint: "[issue-number] [--spike]"
allowed-tools: Bash(gh *) Bash(./scripts/*) Bash(git add docs/research/*) Bash(git commit -m*) Bash(git status) Bash(git diff*) Bash(git rev-parse*) Agent
---

You are running a research session for an issue entering the Research phase. This skill dispatches the `researcher` → `research-reviewer` loop and posts the output to the issue.

## Setup

1. Load the issue:
   - Parse `$ARGUMENTS` as a whitespace-separated list. The first token is the issue number. If the token `--spike` appears anywhere in `$ARGUMENTS`, set `SPIKE_MODE=true`; otherwise `SPIKE_MODE=false`.
   - If no issue number is provided, ask the developer.
   - Fetch: `gh issue view <NUMBER> --json title,body,labels`

2. Move the issue to Research (if not already):
   ```bash
   ITEM_ID=$(./scripts/find-item.sh <ISSUE_NUMBER>)
   ./scripts/move-issue.sh "$ITEM_ID" "Research"
   ```

## Scoping Round (max 2 iterations)

### Step 1: Spawn researcher for DoD draft

Spawn the researcher with this exact first line in the prompt (it lands in this session's transcript JSONL and lets `scripts/token-report.sh` attribute the work, when present):

`HARNESS_TOKEN_MARKER role=researcher iteration=<ITER> issue=<NUMBER> kind=scoping`

```
Agent(
  subagent_type: "researcher",
  prompt: "HARNESS_TOKEN_MARKER role=researcher iteration=<ITER> issue=<NUMBER> kind=scoping
           Scoping round for issue #<NUMBER>.
           Title: [title]
           Body: [body]
           Labels: [labels]

           Propose a research Definition of Done per the Scoping Round section of your agent definition.
           If SPIKE_MODE is true, also include the Spike Mode directive from the Spike Mode section of this skill."
)
```

### Step 2: Spawn research-reviewer on the DoD

```
Agent(
  subagent_type: "research-reviewer",
  prompt: "HARNESS_TOKEN_MARKER role=research-reviewer iteration=<ITER> issue=<NUMBER> kind=scoping
           Scoping round for issue #<NUMBER>.
           Researcher DoD proposal:
           [paste]

           Evaluate per the Scoping Round Review format in your agent definition.
           If SPIKE_MODE is true, also include the spike-mode reviewer directive from the Spike Mode section."
)
```

Loop if REVISE. Max 2 iterations. Freeze DoD after acceptance (or after iter 2, flagging disagreements).

## Execution Round (max 3 iterations)

### Step 3: Spawn researcher with frozen DoD

```
Agent(
  subagent_type: "researcher",
  prompt: "HARNESS_TOKEN_MARKER role=researcher iteration=<ITER> issue=<NUMBER> kind=execution
           Execution round for issue #<NUMBER>.
           Frozen DoD:
           [paste]

           Investigate and output either Branch A (clarifying questions) or Branch B (approval-to-proceed) per your agent definition. Use the deep-research skill if the DoD calls for it.
           If SPIKE_MODE is true, also include the Spike Mode directive from the Spike Mode section of this skill."
)
```

### Step 4: Spawn research-reviewer on the findings

```
Agent(
  subagent_type: "research-reviewer",
  prompt: "HARNESS_TOKEN_MARKER role=research-reviewer iteration=<ITER> issue=<NUMBER> kind=execution
           Execution round for issue #<NUMBER>.
           Frozen DoD:
           [paste]

           Researcher findings:
           [paste]

           Evaluate per the Execution Round Review format in your agent definition.
           If SPIKE_MODE is true, also include the spike-mode reviewer directive from the Spike Mode section."
)
```

Loop if NEEDS_IMPROVEMENT or FAIL. Max 3 iterations. Surface to developer after iter 3.

## Spike Mode

If `SPIKE_MODE` is true, the scoping-round and execution-round researcher spawn prompts must include this additional directive:

```
This is a SPIKE investigation. Instead of Branch A (clarifying questions) or Branch B (approval-to-proceed), emit a Spike Deliverable using the 7-section template defined in the research-session skill. The deliverable is a document, not a gate for Q&A. Use the deep-research skill if the DoD calls for it.

Write the deliverable to `docs/research/YYYY-MM-DD-<short-slug>.md` using today's date. This file will be committed and linked from the issue comment; it must stand on its own as a searchable document.
```

The research-reviewer spawn prompts must include:

```
This is a SPIKE investigation. Evaluate the researcher's 7-section Spike Deliverable against the frozen DoD. The deliverable replaces Branch A/B output.
```

### Spike Deliverable Template

The researcher's final output in Spike Mode MUST follow this exact 7-section structure:

```
## Spike Deliverable

### Question
[From the Spike issue's Question field]

### Findings
[The investigation body, prose-first with inline citations]

### Recommendation
[What the developer should do next — concrete action]

### Follow-on Issues
- [issue description 1 with rough scope]
- [issue description 2 with rough scope]

### Search Terms
[Keywords/phrases useful for this investigation OR for deeper follow-up — used if developer wants to extend]

### Directions for Future Investigation
[Specific threads not pursued, with rationale for why they were skipped]

### References
[Citations — codebase files (with paths), docs, web sources]
```

## Post and Transition

1. Post the DoD + accepted research findings as an issue comment:
   ```bash
   gh issue comment <NUMBER> --body "$(cat <<'COMMENT'
   ## Research Complete

   **DoD (frozen after scoping round):**
   [paste DoD]

   **Scoping iterations:** N
   **Execution iterations:** M

   ---

   [paste Branch A or Branch B output verbatim]
   COMMENT
   )"
   ```

   If SPIKE_MODE is true, post the 7-section Spike Deliverable as the issue comment body instead of the Branch A/B output. Use the same `gh issue comment` invocation but with the deliverable text verbatim — do NOT wrap it in the "## Research Complete" header; the deliverable already opens with `## Spike Deliverable`. Prepend a short metadata line indicating `**Scoping iterations:** N` and `**Execution iterations:** M` above the deliverable.

2. Commit any research artifact files written under `docs/research/`:
   ```bash
   # Spike deliverables always write a file. Non-spike research may also write
   # a file if deep-research produced substantial output worth persisting.
   # Skip this step if no files were written.
   if ! git diff --quiet -- docs/research/ || [ -n "$(git ls-files --others --exclude-standard docs/research/)" ]; then
     BASE_BRANCH="${OSKR_BASE_BRANCH:-main}"
     [[ "$(git rev-parse --abbrev-ref HEAD)" == "$BASE_BRANCH" ]] || { echo "ABORT: not on $BASE_BRANCH"; exit 1; }
     git add docs/research/<FILENAME>
     git commit -m "add research for #<NUMBER> <short-slug>"
   fi
   ```

3. Move the issue to Needs Input (both branches):
   ```bash
   ./scripts/move-issue.sh "$ITEM_ID" "Needs Input"
   ```

4. Tell the developer what happened:
   - Branch A: "Research is complete. N clarifying questions are on the issue — use the `developer-input` skill when ready to answer them. It posts a `## Q&A Complete` comment and moves the issue to Planning; `planning-session` then produces the plan."
   - Branch B: "Research is complete and the solution path is well-understood. The researcher proposed skipping detailed Q&A. Run `developer-input` to confirm the approval-to-proceed recommendation (which posts `## Q&A Complete` and advances the issue), or add questions if you want elaboration."
   - Spike mode: "The spike deliverable is posted on the issue. Review it in Needs Input. If you want to create the follow-on issues listed in the deliverable, use the `create-issue` skill. Reply 'approved' if the recommendation is actionable as-is, or reply with feedback to re-run the spike."

## Key Rules

- One issue per invocation.
- Fresh subagent per iteration (no shared context across iterations).
- DoD is frozen after scoping — execution round cannot amend the contract.
- Both output branches (questions / approval) move to Needs Input. The developer gates the transition to Planning manually.
