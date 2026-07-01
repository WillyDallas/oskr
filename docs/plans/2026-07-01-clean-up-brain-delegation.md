# clean-up → `/hjarne integrate` Delegation Rewiring (T3) Implementation Plan

**Goal:** Rewire `skills/clean-up/SKILL.md` so its Phase 5 brain half delegates every brain note to `/hjarne integrate` unconditionally (the sole brain writer), captures the returned page pointer, and records it in the Phase 8 commit body — deleting clean-up's own inbox-write branch and re-attributing all `docs/brain-inbox/` mentions to `/hjarne`.
**Architecture:** Single-file prose rewiring across 7 contiguous text edits in one skill file, plus a `.claude-plugin/plugin.json` version bump. No behavior code, no other file. `/hjarne` (shipped by T2/#70) owns the brain write and the brain-absent fallback; clean-up becomes a pure caller that mints a note-unique provenance, hands off, and breadcrumbs the returned pointer into a committed commit-message body.
**Tech Stack:** Markdown prose (Claude Code skill file); grep/structural acceptance checks; `jq` for the version assertion. No hermetic test — this is a dogfooded/structural change.
**Issue:** #71 (T3, child of the brain-hjarne Area)

---

## EXECUTION GATE — read before starting (do NOT skip)

**Blocked-by T2/#70.** T3 rests on two T2 contracts:
1. `/hjarne integrate` is the **sole brain writer** and **echoes a capturable page pointer** (the `wiki/<system-slug>.md` relpath). This is the pointer clean-up records in the Phase 8 commit body.
2. **T2 is being revised** so `/hjarne integrate` stages to `docs/brain-inbox/` on the no-brain path (nothing dropped). T3's single-home discharge — clean-up removes its own inbox write, so `/hjarne integrate` is the *only* writer and every note has *exactly one* home — **rests on that corrected integrate behavior.** Cite it: the brain-absent fallback is now `/hjarne`'s inbox, not clean-up's.

**Gate check (run at repo root before Task 1; must print `GATE_OK`):**
```
test -f skills/hjarne/SKILL.md && grep -qF 'hjarne_integrate()' bin/hjarne-lib.sh && echo GATE_OK
```
If it does not print `GATE_OK`, T2 has not landed on the Area branch. **Resolve via `sync-worktree`** (merge the Area branch in). Do NOT stub `/hjarne`; do NOT start Task 1.

**No shared-file hazard with T2** — `skills/clean-up/SKILL.md` is T3-only. The only intra-plan shared file is `skills/clean-up/SKILL.md` itself: **Tasks 1→2→3 are strictly sequential** (each edits a different region of the same file; run them in order to avoid stale-line drift).

---

## TDD substitution — harness-infra form (deliberate exemption)

This is a **prose rewiring of one skill file** — there is no code path to unit-test. Per the agent contract for harness infrastructure (agent/skill prose), TDD is substituted with **write acceptance criterion → grep/structural check → implement**. Each anchor carries a `grep`/`! grep` AC that is its RED→GREEN gate: run the grep first (RED — asserts the *old* text or the *absence* of the new token), apply the edit, run it again (GREEN).

- **Testing tier:** dogfooded/structural (grep). No hermetic test. `tests/scripts/run-tests.sh` is **excluded** — it covers `bin/*.sh` seams, not `clean-up`'s prose (running it is neither required nor meaningful here).
- **Playwright:** no-op — no web/UI/navigation/auth surface (a prose skill file).
- **`.claude/rules/`:** no-op — the repo declares none (verified in the T2 plan).

---

## Dependencies

```
GATE (T2/#70 merged to Area branch: /hjarne integrate = sole writer + echoes pointer + inbox fallback)
  └─ Task 1  Phase 5 rewiring        (anchors 1, 2)          — edits SKILL.md lines 108–113
       └─ Task 2  Phase 8 rewiring   (anchors 3, 4, 5)       — edits SKILL.md lines 137–144
            └─ Task 3  Reference + version  (anchors 6, 7)   — edits SKILL.md 159/165 + plugin.json
```

All three tasks modify `skills/clean-up/SKILL.md` → **sequential, in order**. Task 3 also touches `.claude-plugin/plugin.json` (no other task touches it).

**7 edit anchors, mapped to the frozen DoD's numbering** (DoD #3 = Phase 8 splits into two distinct sentence edits — the `git add docs/` clause and the summary clause — so 6 DoD items = 7 text edits):

| Anchor | DoD item | SKILL.md before-line | Task |
|---|---|---|---|
| 1 | DoD #1 | 110–111 (the two-arm branch) | 1 |
| 2 | DoD #2 | 113 (Done when) | 1 |
| 3 | DoD #3 | 144 (`git add docs/` captures … clause) | 2 |
| 4 | DoD #4 | 137–144 (commit-body pointer-listing instruction — NEW) | 2 |
| 5 | DoD #3 | 144 (summary `brain notes written vs staged` clause) | 2 |
| 6 | DoD #5 | 159 (graceful-degradation clause) | 3 |
| 7 | DoD #6 | 165 (committed-record clause) | 3 |

**Provenance-token reconciliation (deliberate).** The DoD's anchor-1 prose describes the shape as `<merged-PR-or-issue-ref>:<system-slug>`, but the frozen **verification grep** is `grep -qF '<issue-or-pr-ref>:<system-slug>'` (the exact token T2's `skills/hjarne/SKILL.md` uses). The verification is the contract, so the after-text uses the literal token **`<issue-or-pr-ref>:<system-slug>`** and glosses it as "the merged PR or issue ref plus the system slug." This satisfies the grep and the semantic intent in one string.

**Version:** main baseline `0.3.7`. After T2 merges, the Area branch reads `0.5.0`. T3 is a **patch** (prose refactor, no new capability → per CLAUDE.md versioning rule) → target `0.5.1`. Frozen AC only requires `!= 0.3.7` AND valid semver; **collision-tolerant** — if `0.5.1` is taken on rebase, take the next free patch.

---

## Task 1: Phase 5 rewiring — unconditional `/hjarne integrate` delegation (anchors 1, 2)

**Depends on:** EXECUTION GATE. First edit to `skills/clean-up/SKILL.md`.

**Files:**
- Modify: `skills/clean-up/SKILL.md` (Phase 5, lines 108–113)

**Acceptance Criteria:**
- [ ] `Run: grep -qF '/hjarne integrate' skills/clean-up/SKILL.md` → `Expected: exit 0`
- [ ] `Run: grep -qF '<issue-or-pr-ref>:<system-slug>' skills/clean-up/SKILL.md` → `Expected: exit 0`
- [ ] `Run: grep -qF 'returned page pointer' skills/clean-up/SKILL.md` → `Expected: exit 0`
- [ ] `Run: ! grep -qF 'pending migration to the brain' skills/clean-up/SKILL.md` → `Expected: exit 0`
- [ ] `Run: grep -qF 'zero items dropped or double-homed' skills/clean-up/SKILL.md` → `Expected: exit 0` (guard — survives Done-when rewrite)
- [ ] `Run: grep -qF 'distill it to a self-contained note' skills/clean-up/SKILL.md` → `Expected: exit 0` (guard — line 108 distill stays in clean-up; `/hjarne integrate` does NOT re-distill)

**Step 1: Write the acceptance criteria (above) — the grep set is the RED→GREEN contract.**

**Step 2: Run the RED checks** — before editing, confirm the state that the edit will flip:
Run: `grep -qF 'pending migration to the brain' skills/clean-up/SKILL.md && ! grep -qF '/hjarne integrate' skills/clean-up/SKILL.md && echo RED_OK`
Expected: prints `RED_OK` (the old inbox-write branch is present; the new delegation token is absent).

**Step 3: Apply the edit.**

**Anchor 1 — lines 110–111 (DELETE the present/absent branch; replace with unconditional delegation).**

Line 108 (`**Brain half …** For each \`brain\`-tagged item, distill it to a self-contained note, then route:`) stays **verbatim** — it is the double-distill guard. Replace the two bullets that follow it.

BEFORE (exact current text, lines 110–111):
```markdown
- **`/hjarne` brain ability available** → hand each note to it; the brain owns the write.
- **Brain absent (the v1 default — #28 not built)** → **stage, never drop**: append each note to `docs/brain-inbox/<YYYY-MM-DD>-<system>.md`, marked `<!-- pending migration to the brain (#28) -->`. It is committed (Phase 8) so nothing is lost. Never fold a brain note into `docs/` project docs — the boundary holds even while staged.
```

AFTER (paste exactly):
```markdown
Give each note a **note-unique** provenance of the shape `<issue-or-pr-ref>:<system-slug>` — the merged PR or issue ref plus the system slug (e.g. `#42:board-dispatcher`), never a bare issue ref, or a second note from the same issue silently dedups away. Hand the distilled note and that provenance to **`/hjarne integrate`**: `/hjarne` owns the write — it archives the raw note, version-stamps `wiki/<system-slug>.md`, and echoes a **returned page pointer** (the page relpath). Capture that pointer for the Phase 8 commit body. Never fold a brain note into `docs/` project docs — the boundary holds wherever `/hjarne` lands it.

The brain-absent fallback belongs to `/hjarne`, not clean-up: if the brain isn't built yet, `/hjarne`'s own inbox fallback stages the note under `docs/brain-inbox/`. clean-up calls `/hjarne integrate` **unconditionally** and no longer writes any inbox itself.
```

**Anchor 2 — line 113 (Done when: drop "or written to docs/brain-inbox/"; require handoff + pointer capture; keep "zero items dropped or double-homed").**

BEFORE (exact current text, line 113):
```markdown
**Done when:** every doc-impact item is tagged `brain` or `repo` with a reason; every `repo` item is reconciled by the curator pass; every `brain` item is handed to `/hjarne` or written to `docs/brain-inbox/`; **zero items dropped or double-homed.**
```

AFTER (paste exactly):
```markdown
**Done when:** every doc-impact item is tagged `brain` or `repo` with a reason; every `repo` item is reconciled by the curator pass; every `brain` item is handed to `/hjarne integrate` and clean-up captures the returned page pointer; **zero items dropped or double-homed.**
```

**Step 4: Run the GREEN checks:**
Run: `grep -qF '/hjarne integrate' skills/clean-up/SKILL.md && grep -qF '<issue-or-pr-ref>:<system-slug>' skills/clean-up/SKILL.md && grep -qF 'returned page pointer' skills/clean-up/SKILL.md && ! grep -qF 'pending migration to the brain' skills/clean-up/SKILL.md && grep -qF 'zero items dropped or double-homed' skills/clean-up/SKILL.md && grep -qF 'distill it to a self-contained note' skills/clean-up/SKILL.md && echo TASK1_OK`
Expected: prints `TASK1_OK` (exit 0).

**Step 5: Commit**
`git add skills/clean-up/SKILL.md && git commit -m "refactor(clean-up): Phase 5 delegates brain notes to /hjarne integrate unconditionally (#71)"`

---

## Task 2: Phase 8 rewiring — commit-body breadcrumb + re-attributed inbox (anchors 3, 4, 5)

**Depends on:** Task 1.

**Files:**
- Modify: `skills/clean-up/SKILL.md` (Phase 8, lines 137–144)

**Acceptance Criteria:**
- [ ] `Run: grep -qF 'commit body lists each' skills/clean-up/SKILL.md` → `Expected: exit 0` (anchor 4 — the sole breadcrumb-home instruction)
- [ ] `Run: ! grep -qF 'written vs staged' skills/clean-up/SKILL.md` → `Expected: exit 0` (anchor 5 — old summary clause gone)
- [ ] `Run: grep -qF 'docs/brain-inbox' skills/clean-up/SKILL.md` → `Expected: exit 0` (anchor 3 — inbox mention retained, now `/hjarne`-attributed)
- [ ] `Run: ! grep -qF 'append each note to' skills/clean-up/SKILL.md` → `Expected: exit 0` (no removed write-verb reused)
- [ ] `Run: ! grep -qF 'stage, never drop' skills/clean-up/SKILL.md` → `Expected: exit 0` (no removed write-verb reused)

**Step 1: Write the acceptance criteria (above).**

**Step 2: Run the RED checks:**
Run: `grep -qF 'written vs staged' skills/clean-up/SKILL.md && ! grep -qF 'commit body lists each' skills/clean-up/SKILL.md && echo RED_OK`
Expected: prints `RED_OK` (old summary clause present; new breadcrumb instruction absent).

**Step 3: Apply the edit.** Replace the entire Phase 8 body (lines 137–144).

**Anchors 3 + 4 + 5 — the whole Phase 8 block.** The bash block gains a two-`-m` commit that carries the pointer list (the breadcrumb home — a committed, `git log`-discoverable surface; no new file under `docs/`). The prose re-attributes the `docs/brain-inbox/` write to `/hjarne` (anchor 3), adds the commit-body pointer-listing instruction (anchor 4), and rewrites the summary clause (anchor 5).

BEFORE (exact current text, lines 137–144):
````markdown
## Phase 8: Commit

```bash
git add docs/
git commit -m "clean-up: <system>"
```

`git add docs/` captures the curator's doc changes, the `docs/plans/` deletions, and `docs/brain-inbox/` (gitignored `docs/temp/` + `docs/_local_archive/` are excluded). **Do not push** — that stays human-gated. Finish with a short summary: issues archived, issues kept, docs touched, **brain notes written vs staged** (with the staged count pending #28), and what the next run's seed will be.
````

AFTER (paste exactly):
````markdown
## Phase 8: Commit

```bash
git add docs/
git commit -m "clean-up: <system>" \
  -m "brain notes filed (returned page pointers from /hjarne integrate):" \
  -m "- <system-slug> → wiki/<system-slug>.md"
```

`git add docs/` captures the curator's doc changes, the `docs/plans/` deletions, and any `docs/brain-inbox/` notes `/hjarne` staged through its own inbox fallback (gitignored `docs/temp/` + `docs/_local_archive/` are excluded). The **commit body lists each** brain note's returned page pointer — the `wiki/<system-slug>.md` relpath `/hjarne integrate` echoed. That committed, `git log`-discoverable list is the sole repo-side breadcrumb for what landed in the brain; do not create a separate committed file for it (a `logs/clean-up.log` line is fine as a local trace but does not discharge this). **Do not push** — that stays human-gated. Finish with a short summary: issues archived, issues kept, docs touched, **brain notes integrated (each with its returned page pointer)**, and what the next run's seed will be.
````

**Step 4: Run the GREEN checks:**
Run: `grep -qF 'commit body lists each' skills/clean-up/SKILL.md && ! grep -qF 'written vs staged' skills/clean-up/SKILL.md && grep -qF 'docs/brain-inbox' skills/clean-up/SKILL.md && ! grep -qF 'append each note to' skills/clean-up/SKILL.md && ! grep -qF 'stage, never drop' skills/clean-up/SKILL.md && echo TASK2_OK`
Expected: prints `TASK2_OK` (exit 0).

**Step 5: Commit**
`git add skills/clean-up/SKILL.md && git commit -m "refactor(clean-up): Phase 8 records /hjarne page pointers in the commit body (#71)"`

---

## Task 3: Reference-section re-attribution + version bump (anchors 6, 7)

**Depends on:** Task 2.

**Files:**
- Modify: `skills/clean-up/SKILL.md` (Reference section, lines 159 and 165)
- Modify: `.claude-plugin/plugin.json` (`version`)

**Acceptance Criteria:**
- [ ] `Run: ! grep -qF 'when present, else' skills/clean-up/SKILL.md` → `Expected: exit 0` (anchor 6 — old degradation clause gone)
- [ ] `Run: grep -qF 'If this repo vanished' skills/clean-up/SKILL.md` → `Expected: exit 0` (guard — line 152 routing test survives verbatim)
- [ ] `Run: grep -qF 'Write Skill' skills/clean-up/SKILL.md` → `Expected: exit 0` (guard — line 5 allowed-tools `Skill` survives)
- [ ] `Run: test "$(jq -r .version .claude-plugin/plugin.json)" != "0.3.7" && jq -r .version .claude-plugin/plugin.json | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'` → `Expected: exit 0`

**Step 1: Write the acceptance criteria (above).**

**Step 2: Run the RED checks:**
Run: `grep -qF 'when present, else' skills/clean-up/SKILL.md && echo RED_OK`
Expected: prints `RED_OK` (old graceful-degradation clause present).

**Step 3: Apply the edits.**

**Anchor 6 — line 159 (rewrite the "when present, else to docs/brain-inbox/" clause to `/hjarne`-owned framing).**

BEFORE (exact current text, line 159):
```markdown
**Graceful degradation (the brain may not exist in v1):** brain-bound notes go to `/hjarne` when present, else to `docs/brain-inbox/` — committed, marked pending #28, never dropped, never mixed into project docs. When #28 lands, that inbox is the migration queue.
```

AFTER (paste exactly):
```markdown
**Graceful degradation lives entirely inside `/hjarne`:** clean-up always calls `/hjarne integrate` and captures the returned page pointer; if the brain isn't built yet, `/hjarne`'s own inbox fallback stages the note under `docs/brain-inbox/` (committed via Phase 8, never dropped, never mixed into project docs). clean-up itself never writes that inbox — the degradation path is `/hjarne`'s to own, and when the brain lands, that inbox is `/hjarne`'s migration queue.
```

**Anchor 7 — line 165 (keep the committed-record clause accurate but re-attribute the inbox write to `/hjarne`).**

BEFORE (exact current text, line 165):
```markdown
- **Working artifacts vs. the record.** `docs/temp/` and `logs/` are gitignored; the committed record is the doc changes, the plan-file deletions, and `docs/brain-inbox/`. The board's archived-items view plus `logs/clean-up.log` carry the audit trail.
```

AFTER (paste exactly):
```markdown
- **Working artifacts vs. the record.** `docs/temp/` and `logs/` are gitignored; the committed record is the doc changes, the plan-file deletions, and any `docs/brain-inbox/` notes `/hjarne` staged as its inbox fallback. The board's archived-items view, `logs/clean-up.log`, and the Phase 8 commit body's page-pointer list carry the audit trail.
```

**Version bump — `.claude-plugin/plugin.json`.** After T2 the Area branch reads `0.5.0`. T3 is a patch (prose refactor, no new capability).

BEFORE:
```json
  "version": "0.5.0",
```

AFTER:
```json
  "version": "0.5.1",
```

Collision-tolerant: if the Area branch is not at `0.5.0` on rebase (or `0.5.1` is taken), take the next free patch/minor — the AC only requires `!= 0.3.7` AND valid semver. If the value is not `0.5.0` before editing, bump whatever is there by one patch instead of hard-coding.

**Step 4: Run the GREEN checks:**
Run: `! grep -qF 'when present, else' skills/clean-up/SKILL.md && grep -qF 'If this repo vanished' skills/clean-up/SKILL.md && grep -qF 'Write Skill' skills/clean-up/SKILL.md && test "$(jq -r .version .claude-plugin/plugin.json)" != "0.3.7" && jq -r .version .claude-plugin/plugin.json | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' && echo TASK3_OK`
Expected: prints `TASK3_OK` (exit 0).

**Step 5: Commit**
`git add skills/clean-up/SKILL.md .claude-plugin/plugin.json && git commit -m "refactor(clean-up): re-attribute brain-inbox to /hjarne + bump version (#71)"`

---

## Final contract verification (repo-root runnable — frozen §4)

Run after all three tasks. This is the single command the reviewer runs to confirm the whole frozen contract holds:

```
grep -qF '/hjarne integrate' skills/clean-up/SKILL.md \
  && grep -qF '<issue-or-pr-ref>:<system-slug>' skills/clean-up/SKILL.md \
  && grep -qF 'returned page pointer' skills/clean-up/SKILL.md \
  && grep -qF 'commit body lists each' skills/clean-up/SKILL.md \
  && grep -qF 'If this repo vanished' skills/clean-up/SKILL.md \
  && grep -qF 'distill it to a self-contained note' skills/clean-up/SKILL.md \
  && grep -qF 'Write Skill' skills/clean-up/SKILL.md \
  && grep -qF 'zero items dropped or double-homed' skills/clean-up/SKILL.md \
  && ! grep -qF 'pending migration to the brain' skills/clean-up/SKILL.md \
  && ! grep -qF 'when present, else' skills/clean-up/SKILL.md \
  && ! grep -qF 'written vs staged' skills/clean-up/SKILL.md \
  && ! grep -qF 'append each note to' skills/clean-up/SKILL.md \
  && ! grep -qF 'stage, never drop' skills/clean-up/SKILL.md \
  && test "$(jq -r .version .claude-plugin/plugin.json)" != "0.3.7" \
  && jq -r .version .claude-plugin/plugin.json | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' \
  && echo CONTRACT_OK
```
Expected: prints `CONTRACT_OK` (exit 0).

**Note on `! grep 'brain-inbox'`:** a blanket forbid is PROHIBITED — anchors 3/6/7 legitimately retain `docs/brain-inbox` as `/hjarne`-attributed mentions. The negative discriminators above only forbid the *removed write-verbs* (`append each note to`, `stage, never drop`) and the *old attributions* (`pending migration to the brain`, `when present, else`, `written vs staged`), never the inbox path itself.
