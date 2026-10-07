# Review format

Use it when reviewing UI, whether your own work after step 6 or existing screens.

**Coverage.** List each screen and state you inspected and how: *rendered* (you saw it) or *read* (code only). Never imply that a surface you didn't inspect was reviewed.

**Findings.** At most 5 for a quick review, 15 for a full one, most severe first.

| Severity | Location | Before | After | Why |
|---|---|---|---|---|
| block / fix / polish | `file:line` | what's there | the change | the rule or tell it breaks |

- **block:** broken or inaccessible (contrast, a missing focus state, color as the only cue, overflow that hides content).
- **fix:** a tell or a rule broken where nothing pinned it.
- **polish:** alignment, rhythm, copy tightening.

**Considered but rejected.** 0–5 things that looked wrong but are right for this brief, each with the reason. Leave the section empty rather than invent filler.

**Verdict.** Block, Needs changes, or Approve.
