# `/hjarne register-pointer` + research auto-ingest (T4) Implementation Plan

**Goal:** Append a `hjarne_register_pointer` helper to T2's `bin/hjarne-lib.sh` that deposits a research digest as an L1 pointer (`raw/research/<topic>-<date>/digest.md` + one INGEST log line, never a wiki page), add a `register-pointer` mode to `skills/hjarne/SKILL.md`, and wire `skills/research/SKILL.md` to call it after posting its digest.
**Architecture:** `hjarne_register_pointer` is a forge-blind, `set -euo pipefail`-safe filesystem function that reuses T2's `hjarne_resolve_brain` (dir-absent no-op gate) and `hjarne_log_append` (the dated INGEST line), owns its OWN date-scoped path derivation (deliberately NOT `hjarne_raw_path`'s `<slug>-<hash>.md`), and NEVER calls `hjarne_route`/`hjarne_write_page`. `/hjarne register-pointer` re-fetches the just-posted `## Research Digest` comment via `gh` under `/hjarne`'s own unrestricted Bash and passes it as `<content>`. `research` invokes `/hjarne register-pointer` via the `Skill` tool with the STABLE issue ref as `<topic>`; research itself writes no `digest.md` and sources no helpers.
**Tech Stack:** Pure bash (bash 3.2 / macOS-safe: no `${var,,}`, no assoc arrays, no `mapfile`), `sed`/`grep`/`tr`, `gh`, `jq`, Markdown. Tests use `tests/scripts/run-tests.sh` auto-discovery + `lib/assert.sh`. No new deps.
**Issue:** #72 (T4, child of the brain-hjarne Area). **Closes #7.**

---

## EXECUTION GATE — read before starting (do NOT skip)

Written now against FROZEN T2 contracts; T4 **REBASES onto T2 and executes only AFTER T2 (#70) merges into the Area branch.** T4 needs, from T2/#54: `hjarne_resolve_brain`, `hjarne_log_append`, `hjarne_raw_path`'s inlined slug transform (the source of the verbatim duplication), `bin/hjarne-lib.sh` itself, `skills/hjarne/SKILL.md`, `blacksmith_workspace_dir` in `harness-lib.sh`, `bin/hjarne-skeleton.sh`, and T2's `count()` test-helper convention. **None of these exist in this branch yet** — they arrive when T2 merges.

**Gate check (run at repo root before Task 1; must print `GATE_OK`):**
```
grep -qF 'hjarne_resolve_brain()' bin/hjarne-lib.sh \
  && grep -qF 'hjarne_log_append()' bin/hjarne-lib.sh \
  && grep -qF 'hjarne_raw_path()'   bin/hjarne-lib.sh \
  && grep -qF 'blacksmith_workspace_dir()' bin/harness-lib.sh \
  && test -x bin/hjarne-skeleton.sh \
  && test -f skills/hjarne/SKILL.md \
  && echo GATE_OK
```
If it does not print `GATE_OK`, T2 has not landed on the Area branch. **Resolve via `sync-worktree`** (merge the Area branch in). Do NOT stub T2's functions; do NOT recreate `bin/hjarne-lib.sh` or `skills/hjarne/SKILL.md`; do NOT start Task 1.

**T4 APPENDS ONLY.** It appends one function to `bin/hjarne-lib.sh` (after T2's `hjarne_inbox_drain`, the last frozen function) and edits NO frozen T2 code. It appends a mode section to `skills/hjarne/SKILL.md` (and touches only its `argument-hint` line). It edits two lines of `skills/research/SKILL.md`.

---

## Frozen DoD recap — exemptions & TDD substitutions (for plan-reviewer)

- **Testing tier:** unit / hermetic seam for Task 1 (a genuine committed RED→GREEN, mirroring T2's STANDARD FIXTURE — `mktemp` workspace, `.oskr/` marker, brain stamped via `bin/hjarne-skeleton.sh`, both libs sourced, no shim). Grep/structural for Tasks 2–4.
- **TDD substitution (harness-infra form: write-AC → grep/structural check → implement, NO RED unit test) applies to EXACTLY three tasks:** Task 2 (`skills/hjarne/SKILL.md` mode — prose skill, semantic quality dogfooded not hermetically tested), Task 3 (`skills/research/SKILL.md` wiring — prose skill), Task 4 (version bump + guards — config). **This substitution is deliberate and flagged here so plan-reviewer treats the missing RED unit test on 2–4 as intended, not an omission.** Task 1 is true RED-first.
- **No Playwright** — no web/UI/navigation/auth surface (pure shell + prose skills; the only `gh`/`jq` is documented shell inside a skill, not a rendered UI). Exemption deliberate.
- **No design/quality-rule ACs** — the repo declares no `.claude/rules/` (verified: none present). No-op axis.
- **`Closes #7`** is a **land-area concern, not a code AC** — the Area→main PR body (owned by `land-area`) carries `Closes #7`. T4's code MUST NOT reintroduce #7's deleted `research-session` / `obsidian_vault_path` config (guarded by Task 4 ACs over the T4 diff scope).

---

## Dependencies (per-task headers repeat this)

```
EXECUTION GATE (T2 #70 merged into Area branch)
  └─ Task 1  hjarne_register_pointer  (append to bin/hjarne-lib.sh; hermetic RED→GREEN)
        └─ Task 2  /hjarne register-pointer mode  (skills/hjarne/SKILL.md — needs the helper to exist)
              └─ Task 3  research wiring  (skills/research/SKILL.md — the research call needs the mode)
                    └─ Task 4  version bump + #7 guards  (needs Tasks 1–3 landed)
```

**Shared-file hazards:** `bin/hjarne-lib.sh` (Task 1 appends ONE function after T2's last; touches no frozen line); `skills/hjarne/SKILL.md` (Task 2 appends a mode section + edits the `argument-hint` line only); `skills/research/SKILL.md` (Task 3 edits line 5 + inserts after line 22); `.claude-plugin/plugin.json` `version` (Task 4).

**Version:** main baseline `0.3.7`; T2 lands `0.5.0` on the Area branch. T4 is a new capability (a new helper + a new skill mode + research wiring) → **minor → target `0.6.0`**. Frozen AC only requires `!= 0.3.7` AND valid semver AND strictly above T2's landed value; if `0.6.0` is taken on rebase, take the next free minor/patch. **Do not hardcode — read the current value and bump above it.**

---

## STANDARD FIXTURE (copied verbatim from T2 into the top of Task 1's hermetic test)

Task 1's test opens with this exact T2 block, then adds a `WS2` line for the brain-absent case. `mktemp` workspace, `.oskr/` marker, skeleton stamped at `<WS>/hjarne`, both libs sourced, `OSKR_WORKSPACE` exported, `trap` cleanup — the frozen hermetic contract, no shim.

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"
source "$REPO_ROOT/bin/harness-lib.sh"   # blacksmith_workspace_dir / _blacksmith_die
source "$REPO_ROOT/bin/hjarne-lib.sh"    # unit under test
```

The resolver (T2/#54) reads `OSKR_WORKSPACE` (must itself contain `.oskr/`) or walks `.oskr/` ancestors, so the absent case is just a second `.oskr/` workspace with the brain NOT stamped.

---

## Task 1: `hjarne_register_pointer` — L1 research pointer (append to `bin/hjarne-lib.sh`)

**Depends on:** EXECUTION GATE (T2 #70 merged). APPENDS one function to `bin/hjarne-lib.sh` after T2's `hjarne_inbox_drain`; edits NO frozen T2 code.

**Files:**
- Modify: `bin/hjarne-lib.sh` (append `hjarne_register_pointer` at EOF)
- Test: `tests/scripts/test_hjarne_register_pointer.sh` (create)

**Acceptance Criteria:**
- [ ] `Run: bash -n bin/hjarne-lib.sh` → `Expected: exit 0`
- [ ] `Run: grep -qF 'hjarne_register_pointer()' bin/hjarne-lib.sh` → `Expected: exit 0`
- [ ] `Run: bash tests/scripts/test_hjarne_register_pointer.sh` → `Expected: exit 0` (prints `test_hjarne_register_pointer: PASS`)
- [ ] `Run: ! awk '/^hjarne_register_pointer\(\)/{f=1} f' bin/hjarne-lib.sh | grep -qE 'hjarne_route|hjarne_write_page'` → `Expected: exit 0` (the register_pointer body never routes/writes a wiki page)
- [ ] `Run: bash tests/scripts/run-tests.sh` → `Expected: exit 0` (auto-discovers the new test; `Results: N/N passed, 0 failed`)

**Step 1: Write the failing test** — create `tests/scripts/test_hjarne_register_pointer.sh` (STANDARD FIXTURE, extended with `WS2`, then the assertions):
```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"
source "$REPO_ROOT/bin/harness-lib.sh"   # blacksmith_workspace_dir / _blacksmith_die
source "$REPO_ROOT/bin/hjarne-lib.sh"    # unit under test

WS=$(cd "$(mktemp -d)" && pwd)           # canonicalized so /tmp symlinks don't break ==
WS2=$(cd "$(mktemp -d)" && pwd)          # 2nd workspace: brain-absent case
trap 'rm -rf "$WS" "$WS2"' EXIT
mkdir -p "$WS/.oskr"
bash "$REPO_ROOT/bin/hjarne-skeleton.sh" "$WS/hjarne"
export OSKR_WORKSPACE="$WS"
BRAIN="$WS/hjarne"

LOG="$BRAIN/log.md"
# reuse T2's dated-entry counter (|| true: grep -c exits 1 at count 0, fatal under set -e)
count() { grep -cE '^- [0-9]{4}-[0-9]{2}-[0-9]{2} ' "$LOG" || true; }
wiki_md() { find "$BRAIN/wiki" -name '*.md' 2>/dev/null | wc -l | tr -d ' '; }

DATE=$(date +%F)
C1=$'# Research Digest\n\nBLUF: the dispatcher polls the board. [#28]\n'
DIGEST="$BRAIN/raw/research/28-${DATE}/digest.md"

# --- present: 1st run -> +1 INGEST line, digest.md created, ZERO wiki delta ---
L_BEFORE=$(count); W_BEFORE=$(wiki_md)
hjarne_register_pointer '28' "$C1" '28'
[[ "$(count)" -eq "$((L_BEFORE + 1))" ]] \
  || { echo "FAIL: expected exactly +1 INGEST log entry" >&2; exit 1; }
test -f "$DIGEST" || { echo "FAIL: digest.md not created at $DIGEST" >&2; exit 1; }
grep -qF 'BLUF: the dispatcher polls the board.' "$DIGEST" \
  || { echo "FAIL: digest content not deposited" >&2; exit 1; }
tail -1 "$LOG" | grep -qF "INGEST raw/research/28-${DATE}/ (28)" \
  || { echo "FAIL: INGEST log line wrong ($(tail -1 "$LOG"))" >&2; exit 1; }
[[ "$(wiki_md)" -eq "$W_BEFORE" ]] \
  || { echo "FAIL: register_pointer created a wiki page (delta != 0)" >&2; exit 1; }

# --- idempotent (same process): 2nd run -> +0 INGEST, digest byte-identical ---
cp "$DIGEST" "$WS/digest.snapshot"
L_MID=$(count)
hjarne_register_pointer '28' "$C1" '28'
[[ "$(count)" -eq "$L_MID" ]] \
  || { echo "FAIL: 2nd run added an INGEST entry (not idempotent)" >&2; exit 1; }
cmp -s "$DIGEST" "$WS/digest.snapshot" \
  || { echo "FAIL: 2nd run mutated digest.md bytes" >&2; exit 1; }

# --- absent: brain dir NOT stamped -> no-op, 0 files written, exit 0 under set -e ---
mkdir -p "$WS2/.oskr"                     # workspace marker present, brain NOT stamped
export OSKR_WORKSPACE="$WS2"
hjarne_register_pointer '28' "$C1" '28'   # must no-op cleanly (exit 0)
test ! -e "$WS2/hjarne" \
  || { echo "FAIL: brain-absent case created $WS2/hjarne" >&2; exit 1; }
FILES=$(find "$WS2" -type f | wc -l | tr -d ' ')
[[ "$FILES" -eq 0 ]] \
  || { echo "FAIL: brain-absent case wrote $FILES files (expected 0)" >&2; exit 1; }
export OSKR_WORKSPACE="$WS"

# --- never routes/writes a wiki page: the function body forbids the page writers ---
LIB="$REPO_ROOT/bin/hjarne-lib.sh"
if awk '/^hjarne_register_pointer\(\)/{f=1} f' "$LIB" | grep -qE 'hjarne_route|hjarne_write_page'; then
  echo "FAIL: hjarne_register_pointer body references hjarne_route/hjarne_write_page" >&2; exit 1
fi

echo "test_hjarne_register_pointer: PASS"
```

**Step 2: Run test to verify it fails**
Run: `bash tests/scripts/test_hjarne_register_pointer.sh`
Expected: FAIL — `hjarne_register_pointer` is undefined, so the first `hjarne_register_pointer '28' ...` call aborts under `set -e` (`command not found`; no `PASS`, exit != 0).

**Step 3: Write minimal implementation** — append this function to the END of `bin/hjarne-lib.sh` (after T2's `hjarne_inbox_drain`; touch no frozen line):
```bash
# Register a research digest as an L1 pointer: deposit the digest blob under
# raw/research/<topic-slug>-<date>/ and append ONE dated INGEST log line. It NEVER
# routes to wiki/ and NEVER version-stamps a page — distillation is clean-up's job
# (the digest still lives on the issue at L1 depth). No-op (return 0) when no brain
# resolves OR the brain dir is not stamped: register-pointer NEVER inbox-stages — a
# DELIBERATE divergence from hjarne_integrate, justified because the digest already
# posts to the issue. Dedup gate = digest.md existence (mirrors T2's [[ -e ]] &&
# return 0), so it is idempotent within a date (same-process).
# hjarne_register_pointer <topic> <content> [<ref>]
#   <topic> = STABLE issue ref (e.g. 28), never a mutable title.
#   <ref>   = issue/PR ref cited in the INGEST line (defaults to <topic>).
hjarne_register_pointer() {
  local topic="$1" content="$2" ref="${3:-$1}"
  local brain slug today dir digest
  # No-op gate scoped to dir-absent. hjarne_resolve_brain echoes <ws>/hjarne
  # UNCONDITIONALLY and fails only when blacksmith_workspace_dir dies; research always
  # runs in a workspace, so the resolve-fail half is effectively unreachable — the
  # [[ -d ]] check is the gate that actually fires.
  brain=$(hjarne_resolve_brain 2>/dev/null) || return 0
  [[ -d "$brain" ]] || return 0
  # Slug transform — DELIBERATELY duplicated verbatim from hjarne_raw_path's inlined
  # transform (also inlined in hjarne_inbox_stage). A shared helper is OUT of scope:
  # it would edit frozen T2 code.
  slug=$(printf '%s' "$topic" | tr '[:upper:]' '[:lower:]' \
         | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')
  today=$(date +%F)
  dir="$brain/raw/research/${slug}-${today}"
  digest="$dir/digest.md"
  [[ -e "$digest" ]] && return 0   # dedup (date-scoped); mirrors T2's [[ -e ]] && return 0
  mkdir -p "$dir"
  printf '%s\n' "$content" > "$digest"
  hjarne_log_append "INGEST raw/research/${slug}-${today}/ (${ref})"
}
```

**Step 4: Run test to verify it passes**
Run: `bash tests/scripts/test_hjarne_register_pointer.sh`
Expected: PASS (`test_hjarne_register_pointer: PASS`, exit 0). Also `bash -n bin/hjarne-lib.sh` → exit 0, and `bash tests/scripts/run-tests.sh` → `Results: N/N passed, 0 failed`.

**Step 5: Commit**
`git add bin/hjarne-lib.sh tests/scripts/test_hjarne_register_pointer.sh && git commit -m "feat(hjarne): register_pointer L1 research pointer (#72)"`

---

## Task 2: `/hjarne register-pointer` mode in `skills/hjarne/SKILL.md` — TDD SUBSTITUTION

**Depends on:** Task 1 (`hjarne_register_pointer` must exist to invoke). **TDD substitution (harness-infra):** write grep ACs → verify FAIL → implement. No RED unit test (prose skill; semantic quality dogfooded).

**Note — no allowed-tools change needed:** T2's `skills/hjarne/SKILL.md` frontmatter is `allowed-tools: Bash Read Glob Grep`. `Bash` is unfiltered = **`/hjarne`'s OWN unrestricted Bash**, so the `gh` re-fetch runs as-is. Task 2 adds a mode section and edits only the `argument-hint` line; it changes NO frontmatter tool grant.

**Files:**
- Modify: `skills/hjarne/SKILL.md` (append a `## Mode: register-pointer` section; edit the `argument-hint` line)

**Acceptance Criteria (grep-based structural contract):**
- [ ] `Run: grep -qF 'register-pointer' skills/hjarne/SKILL.md` → `Expected: exit 0` (the mode is named)
- [ ] `Run: grep -qF 'hjarne_register_pointer' skills/hjarne/SKILL.md` → `Expected: exit 0` (proves the helper is INVOKED, not just named)
- [ ] `Run: grep -qF 'Research Digest' skills/hjarne/SKILL.md` → `Expected: exit 0` (the `gh` re-fetch of the posted digest is documented)
- [ ] `Run: grep -qE '^name: hjarne$' skills/hjarne/SKILL.md` → `Expected: exit 0` (frontmatter intact)

**Step 1: Write the acceptance criteria (above) — the grep set is the contract.**

**Step 2: Run the checks to verify they FAIL** — Run: `grep -qF 'hjarne_register_pointer' skills/hjarne/SKILL.md`. Expected: FAIL (exit 1 — the T2 SKILL has no `register-pointer` mode yet).

**Step 3: Implement.**

3a. Edit the `argument-hint` line (T2 shipped `argument-hint: "integrate | drain"`):
```
argument-hint: "integrate | drain | register-pointer"
```

3b. Append this section to the END of `skills/hjarne/SKILL.md` (after T2's `**Done when:**` block):
````markdown
## Mode: register-pointer (research auto-ingest)

`research` calls `/hjarne register-pointer` right after it posts its `## Research Digest`
comment. This mode is **L1 depth** — it deposits the digest as a raw *pointer* and logs one
INGEST line. It does **not** distil a `wiki/` page and does **not** stage the inbox; that
distillation stays **clean-up's** job. The digest already lives on the issue, so a no-op here
loses nothing.

Under `/hjarne`'s own unrestricted `Bash`, re-fetch the digest `research` just posted (the
STABLE issue ref is `<topic>` — e.g. `28`, never the mutable title) and hand it to the helper
as `<content>`:

```bash
source bin/harness-lib.sh   # tail-sources bin/hjarne-lib.sh
# re-fetch the just-posted "## Research Digest" comment body for issue 28
DIGEST=$(gh issue view 28 --json comments \
  --jq '[.comments[] | select(.body | startswith("## Research Digest")) | .body] | last')
hjarne_register_pointer '28' "$DIGEST" '28'
```

Deposits `raw/research/<topic-slug>-<date>/digest.md` and appends one
`- <date> — INGEST raw/research/<topic-slug>-<date>/ (<ref>)` log line — or no-ops when no brain
resolves (the digest still lives on the issue). Same topic, same day → idempotent (the digest
byte-unchanged, no second INGEST line).

**Done when:** the digest sits at `raw/research/<topic-slug>-<date>/digest.md` with one INGEST
line in `log.md` — or the call no-opped because no brain resolved / the pointer was already filed
today.
````

**Step 4: Run all grep ACs to verify they pass** — Run (single line, repo root):
```
grep -qE '^name: hjarne$' skills/hjarne/SKILL.md && grep -qF 'register-pointer' skills/hjarne/SKILL.md && grep -qF 'hjarne_register_pointer' skills/hjarne/SKILL.md && grep -qF 'Research Digest' skills/hjarne/SKILL.md && echo HJARNE_MODE_AC_PASS
```
Expected: prints `HJARNE_MODE_AC_PASS` (exit 0).

**Step 5: Commit**
`git add skills/hjarne/SKILL.md && git commit -m "feat(hjarne): /hjarne register-pointer mode + gh digest re-fetch (#72)"`

---

## Task 3: research wiring in `skills/research/SKILL.md` — TDD SUBSTITUTION

**Depends on:** Task 2 (the research call needs the `register-pointer` mode to exist). **TDD substitution (harness-infra):** write grep ACs → verify FAIL → implement. No RED unit test (prose skill).

**Files:**
- Modify: `skills/research/SKILL.md` (edit line 5 allowed-tools; insert a step after line 22)

**Acceptance Criteria (grep-based structural contract):**
- [ ] `Run: grep -qE 'allowed-tools:.*\bSkill\b' skills/research/SKILL.md` → `Expected: exit 0` (`Skill` granted)
- [ ] `Run: ! grep -qE 'allowed-tools:.*\bWrite\b' skills/research/SKILL.md` → `Expected: exit 0` (`Write` NOT granted — research writes no `digest.md`)
- [ ] `Run: grep -qF 'register-pointer' skills/research/SKILL.md` → `Expected: exit 0` (the `/hjarne register-pointer` call is documented)

**Step 1: Write the acceptance criteria (above) — the grep set is the contract.**

**Step 2: Run the checks to verify they FAIL** — Run: `grep -qE 'allowed-tools:.*\bSkill\b' skills/research/SKILL.md`. Expected: FAIL (exit 1 — line 5 is `allowed-tools: Bash(gh *) Bash(sync-development.sh*) Read Glob Grep Agent`, no `Skill`).

**Step 3: Implement two edits.**

3a. Edit line 5 — append ` Skill` to the tool list (do NOT add `Write`):
```
allowed-tools: Bash(gh *) Bash(sync-development.sh*) Read Glob Grep Agent Skill
```

3b. Insert a new Step 6 **immediately after** the current Step 5 (line 22, the post-digest `gh issue comment` step) and **before** the `**Done when:**` line:
```markdown
6. **Register the pointer.** When a brain resolves in this workspace, invoke
   `/hjarne register-pointer` via the **Skill** tool, passing the **STABLE issue ref** as
   `<topic>` (e.g. `28`, never the mutable title). It re-fetches this digest and deposits it at
   `raw/research/<topic>-<date>/digest.md` with one INGEST log line. No-op when no brain
   resolves. `research` does **not** write `digest.md` itself and does **not** source the
   `hjarne_*` helpers — filing the pointer is entirely `/hjarne`'s job.
```

**Step 4: Run all ACs to verify they pass** — Run (single line, repo root):
```
grep -qE 'allowed-tools:.*\bSkill\b' skills/research/SKILL.md && ! grep -qE 'allowed-tools:.*\bWrite\b' skills/research/SKILL.md && grep -qF 'register-pointer' skills/research/SKILL.md && echo RESEARCH_WIRING_AC_PASS
```
Expected: prints `RESEARCH_WIRING_AC_PASS` (exit 0).

**Step 5: Commit**
`git add skills/research/SKILL.md && git commit -m "feat(research): wire /hjarne register-pointer after digest (#72)"`

---

## Task 4: version bump + #7 guards — TDD SUBSTITUTION

**Depends on:** Tasks 1–3. **TDD substitution:** config + guard, no RED unit test.

**Files:**
- Modify: `.claude-plugin/plugin.json` (`version` → next minor above T2's landed value; target `0.6.0`)

**Acceptance Criteria:**
- [ ] `Run: V=$(jq -r .version .claude-plugin/plugin.json); test "$V" != "0.3.7" && printf '%s\n' "$V" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'` → `Expected: exit 0` (!= main baseline AND valid semver)
- [ ] `Run: ! grep -rqF 'obsidian_vault_path' bin/hjarne-lib.sh skills/hjarne/SKILL.md skills/research/SKILL.md .claude-plugin/plugin.json tests/scripts/test_hjarne_register_pointer.sh` → `Expected: exit 0` (#7's deleted config NOT reintroduced across the T4 diff scope)
- [ ] `Run: ! grep -rqF 'research-session' skills/hjarne/SKILL.md skills/research/SKILL.md bin/hjarne-lib.sh tests/scripts/test_hjarne_register_pointer.sh` → `Expected: exit 0` (#7's deleted verb NOT reintroduced)
- [ ] `Run: bash tests/scripts/test_backend_no_inline_gh.sh` → `Expected: exit 0` (hjarne-lib.sh stays forge-blind — register_pointer has no `gh`/`curl`; every `bin/*.sh` parses)
- [ ] `Run: bash tests/scripts/run-tests.sh` → `Expected: exit 0` (final line `Results: N/N passed, 0 failed`)

**Step 1: Write the ACs (above).**

**Step 2: Record T2's landed baseline** — Run: `jq -r .version .claude-plugin/plugin.json`. Expected: prints T2's value (e.g. `0.5.0`). This is the `!= baseline` reference — the bump must go strictly above it.

**Step 3: Bump the version** — edit `.claude-plugin/plugin.json`, setting `"version"` to the next minor above the value from Step 2 (minor: a new helper + a new skill mode + research wiring is a new capability). If Step 2 read `0.5.0`, set `"version": "0.6.0"`. If `0.6.0` is already taken on rebase, take the next free minor/patch — the AC only requires `!= 0.3.7` + valid semver + above T2's value. **Do not hardcode blindly; derive from Step 2.**

**Step 4: Run the FULL CONTRACT chain** — Run (single line, repo root):
```
bash -n bin/hjarne-lib.sh && grep -qF 'hjarne_register_pointer()' bin/hjarne-lib.sh && bash tests/scripts/test_hjarne_register_pointer.sh && ! awk '/^hjarne_register_pointer\(\)/{f=1} f' bin/hjarne-lib.sh | grep -qE 'hjarne_route|hjarne_write_page' && grep -qF 'register-pointer' skills/hjarne/SKILL.md && grep -qF 'hjarne_register_pointer' skills/hjarne/SKILL.md && grep -qF 'Research Digest' skills/hjarne/SKILL.md && grep -qE 'allowed-tools:.*\bSkill\b' skills/research/SKILL.md && ! grep -qE 'allowed-tools:.*\bWrite\b' skills/research/SKILL.md && grep -qF 'register-pointer' skills/research/SKILL.md && ! grep -rqF 'obsidian_vault_path' bin/hjarne-lib.sh skills/hjarne/SKILL.md skills/research/SKILL.md .claude-plugin/plugin.json tests/scripts/test_hjarne_register_pointer.sh && bash tests/scripts/test_backend_no_inline_gh.sh && bash tests/scripts/run-tests.sh && V=$(jq -r .version .claude-plugin/plugin.json) && test "$V" != "0.3.7" && printf '%s\n' "$V" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' && echo CONTRACT_OK
```
Expected: `run-tests.sh` prints `Results: N/N passed, 0 failed` and the chain prints `CONTRACT_OK` (exit 0). This bundles the frozen T4 verification: `bash -n` → register_pointer present + hermetic test → never-routes guard → Task 2 mode greps → Task 3 wiring greps → #7 guard → forge-blind seam guard → full suite → version `!= baseline` + valid semver.

**Step 5: Commit**
`git add .claude-plugin/plugin.json && git commit -m "chore(release): bump plugin version to 0.6.0 for register-pointer (#72)"`

---

## Final contract verification (repo-root runnable)

Run the Task 4 Step 4 chain from the repo root after all tasks. Expected: prints `CONTRACT_OK` (exit 0). It is the single command the reviewer runs to confirm the whole frozen T4 contract holds.

**Land-area note (NOT a code AC):** the Area→main PR body (owned by `land-area`) must carry `Closes #7`. T4's commits should not; this is enforced at the umbrella roll-up, not in T4's diff.
