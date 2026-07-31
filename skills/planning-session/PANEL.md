# Rubric panel — Step 4b escalation

You are here because the single execution-round reviewer returned NEEDS_IMPROVEMENT or FAIL. A thorough multi-lens sweep now lets the planner fix everything in one loop instead of ping-ponging. Re-review the *same* draft by fanning the rubric across three parallel lenses + a synthesizer. Emit all three lens calls as `Agent` calls in one message. Each lens owns a disjoint set of rubric axes and carries a `lens=<LENS>` marker:

| lens | rubric axes it owns | what it must DO |
|---|---|---|
| `verify` | Mechanically verifiable criteria + Playwright gate | Run or grep every AC's command against the real tree; confirm it exists and yields the claimed output shape. A UI plan with no `npx playwright test` AC fails this axis outright. |
| `structure` | File-path exactness + TDD structure + task bite-size | Verify every named file path exists (or is a sensible new path) via Glob/Read; check each task has the 5-step TDD pattern and is 2–5 min of work. |
| `completeness` | Dependency declaration + complete code | Confirm cross-task dependencies are explicit and the plan body carries real code snippets, not descriptions. |

```
Agent(
  subagent_type: "plan-reviewer",
  prompt: "HARNESS_TOKEN_MARKER role=plan-reviewer iteration=<ITER> issue=<NUMBER> kind=execution lens=<LENS>
           Execution round for issue #<NUMBER> — <LENS> lens only.
           Frozen DoD:
           [paste accepted DoD]

           Plan file: docs/plans/YYYY-MM-DD-<feature>.md

           Evaluate ONLY your lens's rubric axes (see the panel table in the planning-session skill). Grade each axis you own PASS or FAIL with evidence; for the `verify` lens, actually run/grep the AC commands. Return your axis verdicts + issues with file:line evidence — do NOT emit the overall verdict; the synthesizer owns that."
)
```

Then spawn a single `plan-reviewer` to merge the lens verdicts into the canonical Plan Review output:

```
Agent(
  subagent_type: "plan-reviewer",
  prompt: "HARNESS_TOKEN_MARKER role=plan-reviewer iteration=<ITER> issue=<NUMBER> kind=execution lens=synthesis
           Execution round for issue #<NUMBER> — synthesis.
           Frozen DoD:
           [paste accepted DoD]

           Lens reviews (labeled by lens):
           [paste each lens's axis verdicts + issues]

           Merge into the single Plan Review output. Overall = FAIL if any lens graded an axis FAIL that the planner cannot fix in one revision, NEEDS_IMPROVEMENT if any axis failed, else PASS. Preserve every lens's issues in the Issues Found section."
)
```

Return to SKILL.md **Looping** with the synthesized verdict.
