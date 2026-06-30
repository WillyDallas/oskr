# Adopt — Consent Gate & Register-Only Path Implementation Plan

**Goal:** When `init` adopts a repo that already has issues/a board, detect that, ask the developer (full-migration vs register-only) instead of auto-migrating, and make register-only bring the repo under oskr management without touching its existing board.
**Architecture:** Two new forge-dispatched verbs in the blacksmith (`harness-lib.sh`) plus two thin `bin/` wrappers, all proven through the hermetic `tests/scripts/` harness: `blacksmith_count_issues` (the gh/curl-shim-replayed forge probe), `bin/adopt-detect.sh` (emits the `existing N`/`empty 0` consent verdict), and `bin/adopt-register.sh` (writes config no-clobber + delegates the registry entry to `registry.sh`, and makes **zero** forge calls — the no-touch guarantee). The interactive prompt itself is additive prose in `skills/init/SKILL.md` (guided/manual surface).
**Tech Stack:** Bash 3.2-safe shell, `jq`, `gh`/`curl` PATH-boundary shims, the existing `tests/scripts/` subshell-fixture harness.
**Issue:** #61 (child of Area #27, branch `WillyDallas/27`)

> **Worktree note (read first).** This branch `WillyDallas/27` is checked out at the worktree
> **`.`** (run `git worktree list` to confirm). This plan
> file and ALL task work live in that worktree. The `.` checkout is
> the **`main`** worktree — do NOT execute there; commits made there land on `main` and bypass the
> feature branch and PR. Every `Files:` path and the repo-root for every `Run:` command below is
> rooted at `.`.

---

## Context the implementer must hold

- **This is umbrella #27's single Named Seam:** the hermetic `tests/scripts/` harness over the `bin/` shell layer. Subshell + `harness-config.*.json` fixtures for pure resolution; `lib/gh-shim.sh` + `lib/curl-shim.sh` PATH-boundary replay for forge-touching verbs. Prior art to mirror exactly: `tests/scripts/test_harness_config.sh`, `tests/scripts/test_blacksmith_create_issue.sh` (gh-shim), `tests/scripts/test_blacksmith_forgejo_ops.sh` (curl-shim).
- **Seam guard:** `tests/scripts/test_backend_no_inline_gh.sh` forbids inline `gh (api|issue|pr|label|project)` and `curl ... api/v1` in any `bin/*.sh` except `harness-lib.sh`, and `bash -n`s every `bin/` script. Every new `bin/` script must keep all forge calls inside `harness-lib.sh` and parse cleanly.
- **`run-tests.sh` auto-discovers `test_*.sh`** — new test files run automatically; no registration needed. Its final line is `Results: N/N passed, 0 failed (N tests)`.
- **Settled PRD decisions honored here:**
  - The `forge` discriminator is kept (not `backend`).
  - Adopt is consent-gated — it **never** auto-migrates.
  - Register-only **leaves the existing board untouched** (the testable invariant: zero forge calls).
  - Registry writes go through `bin/registry.sh` (#27 T2) — **no new inline registry jq**.
  - Live Forgejo/coremyotherapy acceptance is Area 5; T6 is fixture-proven only.
- **8-column reshape is live in this Area.** Sibling task **#27 T5 / #52** is migrating provisioning from the legacy 9-column scheme (`gen-eval-9col`, columns incl. `research`/`needs_input`/`approval`) to the **8-column** scheme `Backlog · Scoping · Planning · Plan Approval · Ready · In Progress · In Review · Done`. Register-only's fresh-config default must emit the **8-column** block, not the stale 9-column one (see Task 4 + the cross-task note). T5 owns the canonical scheme; this default mirrors the PRD-declared columns as a fallback that only fires when T4 has not already emitted config (no-clobber).
- **Sequencing reality (declared dependencies, see bottom):** the adopt consent gate runs **after** init v2 mode-detection + config emission (#27 T4) has classified the repo as `adopt` and emitted `harness-config.json` (forge + coords). Register-only delegates its registry write to `bin/registry.sh add` (#27 T2). The hermetic tests in this plan stand alone (they supply config fixtures and stub `registry.sh`), so they are green regardless of T2/T4 landing; only the live `skills/init` wiring needs them merged.

---

## Definition of Done

1. **Deliverables**
   - Modify `bin/harness-lib.sh`: public verb `blacksmith_count_issues` + `_blacksmith_github_count_issues` + `_blacksmith_forgejo_count_issues` (forge-dispatched; PR-excluded count of existing issues).
   - Create `bin/adopt-detect.sh`: emits `existing <N>` / `empty 0` from the verb (no inline forge calls).
   - Create `bin/adopt-register.sh`: no-clobber config write (8-column default) + `registry.sh add` delegation + zero forge calls.
   - Create fixtures `tests/scripts/fixtures/gh-issues-list.json` (issues + a PR) and `tests/scripts/fixtures/gh-issues-empty.json` (`[]`).
   - Modify `tests/scripts/lib/gh-shim.sh`: add an `/issues?` route gated on `GH_SHIM_ISSUES_FIXTURE`.
   - Create tests `tests/scripts/test_blacksmith_count_issues.sh`, `tests/scripts/test_adopt_detect.sh`, `tests/scripts/test_adopt_register.sh`.
   - Modify `skills/init/SKILL.md`: additive consent-gate section + `allowed-tools` entries.
   - Modify `.claude-plugin/plugin.json`: version bump.
2. **Testing tier: unit / hermetic shell** — justification: the whole Area seam is verb-boundary behavior over `bin/`. There is no UI, no network in test, no service. Detection is a shim-replayed forge probe; register-only is a file-state + no-forge-call assertion. (No Playwright AC — there is no UI surface in this repo; the exemption is the plugin-harness nature of the project.)
3. **Task granularity:** 7 tasks, each ≤ ~5 min of implementer work (one verb / one half-script / one prose edit per task). Task 4/5 split the register-only script + test so neither exceeds the bite-size budget.
4. **Verification:** every AC below is a `Run:`/`Expected:` tuple with an exact shell command. The detect→prompt branch is proven by the existing-issues fixture vs the empty fixture; the no-touch guarantee is proven by an empty `gh`/`curl` call log.
5. **Dependencies:** declared explicitly in the final section (T4 emits the adopt config before the gate; T2's `registry.sh` is the register-only registry writer; tests are decoupled via fixtures/stubs; a deferred post-T2 integration AC is named).
6. **Design/quality rules:** `.claude/rules/` declares no design tokens for this shell-only repo — that AC class is a no-op here. The load-bearing convention rule (the backend seam guard) **is** asserted: `test_backend_no_inline_gh.sh` must stay green for the two new `bin/` scripts.

**Harness-infra TDD substitution (declared):** Task 6 edits a skill markdown (prose, no runtime). Per the planner convention it uses **write AC → grep/structural check → implement**, not RED-test-first. All other tasks (shell verbs/scripts) use full 5-step TDD.

---

## AC → verification map

All commands run from the repo root: **`.`**.

| # | Acceptance criterion | Runnable verification |
|---|----------------------|-----------------------|
| AC1 | `blacksmith_count_issues` exists and is forge-dispatched | `Run: grep -qE 'blacksmith_count_issues\(\)[[:space:]]*\{[[:space:]]*_blacksmith_dispatch count_issues' bin/harness-lib.sh` → `Expected: exit 0` |
| AC2 | GitHub count excludes PRs, counts existing issues | `Run: bash tests/scripts/test_blacksmith_count_issues.sh` → `Expected: exit 0` (asserts `2` from the issues+PR fixture, `0` from empty) |
| AC3 | Forgejo count returns existing-issue count via curl-shim | covered by `Run: bash tests/scripts/test_blacksmith_count_issues.sh` → `Expected: exit 0` (forgejo block asserts `2`) |
| AC4 | Detect→branch: existing-issues fixture → prompt verdict | `Run: bash tests/scripts/test_adopt_detect.sh` → `Expected: exit 0` (asserts `existing 2`) |
| AC5 | Detect→branch: empty fixture → no-prompt verdict (empty repo proceeds without prompt) | covered by `Run: bash tests/scripts/test_adopt_detect.sh` → `Expected: exit 0` (asserts `empty 0`) |
| AC6 | Register-only writes config (forge + github coords) | `Run: bash tests/scripts/test_adopt_register.sh` → `Expected: exit 0` (asserts `.forge==github`, `.github.owner==acme`) |
| AC7 | Register-only fresh config emits the **8-column** workflow, no retired slugs | covered by `Run: bash tests/scripts/test_adopt_register.sh` → `Expected: exit 0` (asserts `.workflow.kind==gen-eval-8col`; `actionable_columns` contains none of `research`/`needs_input`/`approval`) |
| AC8 | No-clobber: a pre-emitted config is preserved byte-for-byte | covered by `Run: bash tests/scripts/test_adopt_register.sh` → `Expected: exit 0` |
| AC9 | Register-only delegates the registry entry to `registry.sh add` with the exact outgoing flags | covered by `Run: bash tests/scripts/test_adopt_register.sh` → `Expected: exit 0` (registry stub log contains `add`, `--name story-spark`, `--forge github`, `--owner acme`, `--repo story-spark`, `--path`) |
| AC10 | **No-touch guarantee:** register-only makes zero forge calls | covered by `Run: bash tests/scripts/test_adopt_register.sh` → `Expected: exit 0` (gh + curl call logs are empty) |
| AC11 | Register-only writes forgejo coords (`base_url` + owner/repo) | covered by `Run: bash tests/scripts/test_adopt_register.sh` → `Expected: exit 0` (asserts `.forge==forgejo`, `.forgejo.base_url`) |
| AC12 | Backend seam guard stays green for the new scripts | `Run: bash tests/scripts/test_backend_no_inline_gh.sh` → `Expected: exit 0` |
| AC13 | init prose has the consent gate (detect + register-only + never-auto-migrate) and wires the scripts | `Run: grep -qF 'adopt-detect.sh' skills/init/SKILL.md && grep -qF 'adopt-register.sh' skills/init/SKILL.md && grep -qiF 'never auto-migrate' skills/init/SKILL.md && grep -qF 'Register-only' skills/init/SKILL.md` → `Expected: exit 0` |
| AC14 | Full suite green | `Run: bash tests/scripts/run-tests.sh` → `Expected: exit 0` (last line `... 0 failed ...`) |
| AC15 | Version bumped off 0.3.5 | `Run: test "$(jq -r '.version' .claude-plugin/plugin.json)" != "0.3.5"` → `Expected: exit 0` |

---

## Task 1: GitHub existing-issue count verb + shim route + fixtures

**Files:**
- Modify: `bin/harness-lib.sh` (add public verb + GitHub impl)
- Modify: `tests/scripts/lib/gh-shim.sh` (add `/issues?` route)
- Create: `tests/scripts/fixtures/gh-issues-list.json`
- Create: `tests/scripts/fixtures/gh-issues-empty.json`
- Test: `tests/scripts/test_blacksmith_count_issues.sh`

**Acceptance Criteria:**
- [ ] AC1: `grep -qE 'blacksmith_count_issues\(\)[[:space:]]*\{[[:space:]]*_blacksmith_dispatch count_issues' bin/harness-lib.sh` → exit 0
- [ ] AC2: `bash tests/scripts/test_blacksmith_count_issues.sh` GitHub block passes (count `2`, PR excluded; empty `0`)

**Step 1: Write the failing test**

Create `tests/scripts/fixtures/gh-issues-list.json` (two real issues + one PR — the REST issues list interleaves PRs, which must be excluded):
```json
[
  { "number": 1, "title": "real issue one", "state": "open" },
  { "number": 2, "title": "real issue two", "state": "closed" },
  { "number": 3, "title": "a pull request", "state": "open",
    "pull_request": { "url": "https://api.github.com/repos/acme/x/pulls/3" } }
]
```

Create `tests/scripts/fixtures/gh-issues-empty.json`:
```json
[]
```

Create `tests/scripts/test_blacksmith_count_issues.sh` (GitHub block now; Forgejo block added in Task 2):
```bash
#!/usr/bin/env bash
# blacksmith_count_issues (#27 T6): forge-dispatched count of EXISTING issues for
# the adopt consent gate. GitHub excludes PRs (the REST issues list interleaves
# them); Forgejo's ?type=issues already excludes them. Hermetic via gh/curl shims.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB="$REPO_ROOT/bin/harness-lib.sh"
FIX="$REPO_ROOT/tests/scripts/fixtures"
source "$SCRIPT_DIR/lib/assert.sh"

SHIM_DIR=$(mktemp -d); CACHE_DIR=$(mktemp -d)
trap 'rm -rf "$SHIM_DIR" "$CACHE_DIR"' EXIT
cp "$SCRIPT_DIR/lib/gh-shim.sh" "$SHIM_DIR/gh"; chmod +x "$SHIM_DIR/gh"
LOG="$SHIM_DIR/gh.log"; : > "$LOG"

gh_count() {
  PATH="$SHIM_DIR:$PATH" \
    HARNESS_CONFIG="$FIX/harness-config.sample.json" \
    GH_SHIM_CALL_LOG="$LOG" \
    GH_SHIM_FIXTURE="$FIX/gh-project-discovery.json" \
    GH_SHIM_ISSUES_FIXTURE="$1" \
    XDG_CACHE_HOME="$CACHE_DIR" \
    bash -c "source '$LIB'; blacksmith_count_issues"
}

# GitHub: two issues + one PR -> 2 (PR excluded).
assert_eq "2" "$(gh_count "$FIX/gh-issues-list.json")"  "github count excludes PRs" || exit 1
# GitHub: empty list -> 0 (the empty-repo adopt path: no prompt).
assert_eq "0" "$(gh_count "$FIX/gh-issues-empty.json")" "github count empty -> 0"   || exit 1

echo "test_blacksmith_count_issues: PASS"
```

**Step 2: Run test to verify it fails**
Run: `bash tests/scripts/test_blacksmith_count_issues.sh`
Expected: FAIL — the shim default route emits the discovery fixture (so `blacksmith_count_issues` / the `/issues?` route does not exist yet); assertion of `2` fails, or the verb is undefined.

**Step 3: Write minimal implementation**

In `tests/scripts/lib/gh-shim.sh`, add this route **immediately after** the `*/milestones*` route (lines 64–66), before the `*dependencies/blocked_by*` route:
```bash
if [[ "$args" == *"/issues?"* && -n "${GH_SHIM_ISSUES_FIXTURE:-}" ]]; then  # GET issues list (count_issues)
  emit < "$GH_SHIM_ISSUES_FIXTURE"; exit 0
fi
```
(Gated on `GH_SHIM_ISSUES_FIXTURE` so existing tests that never set it are unaffected. `/issues?` does not contain `sub_issues`, `title=`, `pageInfo`, or `/milestones`, so no earlier route shadows it; the POST create path has no `?`, so create is not shadowed. The verb's own `--jq` filter is applied by the shim's `emit`, so the fixture is reduced to the count.)

In `bin/harness-lib.sh`, add the public verb next to the other `#26 graph/write primitives` dispatchers (after `blacksmith_base_branch`, line 104):
```bash
blacksmith_count_issues()      { _blacksmith_dispatch count_issues "$@"; }
```
Add the GitHub impl in the GitHub backend section, after `_blacksmith_github_base_branch` (which ends at line 717):
```bash
# --- Existing-issue detection (adopt consent gate; #27 T6) ------------------
# Echo the count of EXISTING issues on the configured repo (open+closed). Pull
# requests are EXCLUDED — GitHub's REST issues list interleaves PRs. The adopt
# consent gate reads this: >0 => prompt full-vs-register; 0 => no prompt. Single
# page (per_page=100) is sufficient for the >0-vs-0 gate. Never fails the caller
# (echo 0 on any error) so the gate degrades to "no existing".
_blacksmith_github_count_issues() {
  local owner repo
  owner=$(blacksmith_config_get '.github.owner') || return 1
  repo=$(blacksmith_config_get '.github.repo')   || return 1
  gh api "repos/${owner}/${repo}/issues?state=all&per_page=100" \
    --jq '[ .[] | select(has("pull_request") | not) ] | length' 2>/dev/null || echo 0
}
```

**Step 4: Run test to verify it passes**
Run: `bash tests/scripts/test_blacksmith_count_issues.sh`
Expected: PASS (`test_blacksmith_count_issues: PASS`)

**Step 5: Commit**
`git add bin/harness-lib.sh tests/scripts/lib/gh-shim.sh tests/scripts/fixtures/gh-issues-list.json tests/scripts/fixtures/gh-issues-empty.json tests/scripts/test_blacksmith_count_issues.sh && git commit -m "feat(#61): blacksmith_count_issues (github) for adopt detection"`

---

## Task 2: Forgejo existing-issue count impl + test block

**Files:**
- Modify: `bin/harness-lib.sh` (add Forgejo impl)
- Modify: `tests/scripts/test_blacksmith_count_issues.sh` (add Forgejo block)

**Acceptance Criteria:**
- [ ] AC3: `bash tests/scripts/test_blacksmith_count_issues.sh` Forgejo block passes (count `2` via curl-shim)
- [ ] `grep -qF '_blacksmith_forgejo_count_issues' bin/harness-lib.sh` → exit 0

**Step 1: Write the failing test**

Append to `tests/scripts/test_blacksmith_count_issues.sh`, **before** the final `echo "...: PASS"` line. The existing `tests/scripts/fixtures/forgejo-issues-list.json` already holds two issues (#10, #11), and the curl-shim already routes `*"/issues?"*` to `CURL_SHIM_LIST_FIXTURE`:
```bash
# --- Forgejo (curl-shim) ---------------------------------------------------
CSHIM_DIR=$(mktemp -d); trap 'rm -rf "$SHIM_DIR" "$CACHE_DIR" "$CSHIM_DIR"' EXIT
cp "$SCRIPT_DIR/lib/curl-shim.sh" "$CSHIM_DIR/curl"; chmod +x "$CSHIM_DIR/curl"
CLOG="$CSHIM_DIR/curl.log"; : > "$CLOG"

fj_count() {
  PATH="$CSHIM_DIR:$PATH" \
    HARNESS_CONFIG="$FIX/harness-config.forgejo.json" \
    FORGEJO_TOKEN="test-token" \
    CURL_SHIM_CALL_LOG="$CLOG" \
    CURL_SHIM_LIST_FIXTURE="$1" \
    bash -c "source '$LIB'; blacksmith_count_issues"
}

# Forgejo: the 2-issue list fixture -> 2.
assert_eq "2" "$(fj_count "$FIX/forgejo-issues-list.json")" "forgejo count -> 2" || exit 1
# Forgejo: no list fixture -> shim returns [] -> 0.
assert_eq "0" "$(fj_count "")"                              "forgejo count empty -> 0" || exit 1
```
(Note: the appended `trap` line replaces the Task-1 trap so all three temp dirs are cleaned.)

**Step 2: Run test to verify it fails**
Run: `bash tests/scripts/test_blacksmith_count_issues.sh`
Expected: FAIL — `[blacksmith] forge 'forgejo' has no implementation for 'count_issues' (missing _blacksmith_forgejo_count_issues)`.

**Step 3: Write minimal implementation**

In `bin/harness-lib.sh`, add to the Forgejo backend section, after `_blacksmith_forgejo_base_branch` (which ends at line 1037, near the end of the file):
```bash
# Echo the count of EXISTING issues (adopt consent gate; #27 T6). Forgejo's
# ?type=issues already excludes PRs. Never fails the caller (echo 0 on error).
_blacksmith_forgejo_count_issues() {
  local owner repo raw
  owner=$(blacksmith_config_get '.forgejo.owner') || return 1
  repo=$(blacksmith_config_get '.forgejo.repo')   || return 1
  raw=$(_blacksmith_forgejo_curl GET "/repos/${owner}/${repo}/issues?state=all&type=issues&limit=50") \
    || { echo 0; return 0; }
  printf '%s' "$raw" | jq 'length' 2>/dev/null || echo 0
}
```

**Step 4: Run test to verify it passes**
Run: `bash tests/scripts/test_blacksmith_count_issues.sh`
Expected: PASS

**Step 5: Commit**
`git add bin/harness-lib.sh tests/scripts/test_blacksmith_count_issues.sh && git commit -m "feat(#61): blacksmith_count_issues (forgejo)"`

---

## Task 3: `bin/adopt-detect.sh` — consent verdict CLI

**Files:**
- Create: `bin/adopt-detect.sh`
- Test: `tests/scripts/test_adopt_detect.sh`

**Acceptance Criteria:**
- [ ] AC4: existing-issues fixture → stdout `existing 2`
- [ ] AC5: empty fixture → stdout `empty 0` (the empty-repo adopt path: no prompt)
- [ ] AC12: `bash tests/scripts/test_backend_no_inline_gh.sh` passes (no inline `gh`; `bash -n` clean)

**Step 1: Write the failing test**

Create `tests/scripts/test_adopt_detect.sh`:
```bash
#!/usr/bin/env bash
# adopt-detect.sh (#27 T6): emits the consent-gate verdict for init's adopt mode.
# "existing <N>" => prompt the developer; "empty 0" => no prompt. Hermetic via gh-shim.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FIX="$REPO_ROOT/tests/scripts/fixtures"
source "$SCRIPT_DIR/lib/assert.sh"

SHIM_DIR=$(mktemp -d); CACHE_DIR=$(mktemp -d)
trap 'rm -rf "$SHIM_DIR" "$CACHE_DIR"' EXIT
cp "$SCRIPT_DIR/lib/gh-shim.sh" "$SHIM_DIR/gh"; chmod +x "$SHIM_DIR/gh"
LOG="$SHIM_DIR/gh.log"; : > "$LOG"

detect() {
  PATH="$SHIM_DIR:$PATH" \
    HARNESS_CONFIG="$FIX/harness-config.sample.json" \
    GH_SHIM_CALL_LOG="$LOG" \
    GH_SHIM_FIXTURE="$FIX/gh-project-discovery.json" \
    GH_SHIM_ISSUES_FIXTURE="$1" \
    XDG_CACHE_HOME="$CACHE_DIR" \
    "$REPO_ROOT/bin/adopt-detect.sh"
}

assert_eq "existing 2" "$(detect "$FIX/gh-issues-list.json")"  "existing issues -> prompt verdict" || exit 1
assert_eq "empty 0"    "$(detect "$FIX/gh-issues-empty.json")" "empty repo -> no-prompt verdict"  || exit 1

echo "test_adopt_detect: PASS"
```

**Step 2: Run test to verify it fails**
Run: `bash tests/scripts/test_adopt_detect.sh`
Expected: FAIL — `bin/adopt-detect.sh: No such file or directory`.

**Step 3: Write minimal implementation**

Create `bin/adopt-detect.sh`:
```bash
#!/usr/bin/env bash
# Adopt detection (#27 T6): probe the configured forge for EXISTING issues and
# emit the consent-gate verdict for init's adopt mode. Forge-agnostic — all forge
# I/O goes through the blacksmith, so this script makes NO inline gh/curl calls.
#
#   stdout: "existing <N>"  (N>0 — repo has a workflow; prompt full-vs-register)
#           "empty 0"       (no existing issues; proceed without a migration prompt)
#
# Reads repo coords from the harness-config.json that init's mode-detection +
# config emission (#27 T4) writes for adopt mode before this gate runs.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/harness-lib.sh"

count=$(blacksmith_count_issues || echo 0)
[[ "$count" =~ ^[0-9]+$ ]] || count=0
if [[ "$count" -gt 0 ]]; then
  echo "existing $count"
else
  echo "empty 0"
fi
```

**Step 4: Run test to verify it passes**
Run: `bash tests/scripts/test_adopt_detect.sh && bash tests/scripts/test_backend_no_inline_gh.sh`
Expected: PASS (both)

**Step 5: Commit**
`git add bin/adopt-detect.sh tests/scripts/test_adopt_detect.sh && git commit -m "feat(#61): adopt-detect.sh emits consent-gate verdict"`

---

## Task 4: `bin/adopt-register.sh` — config write + no-clobber (8-column default)

> **Split note (bite-size):** the register-only script + test are split across Task 4 and Task 5
> so neither exceeds the ~5-min budget. Task 4 builds the **config-write half** (arg-parse for the
> github coords, no-clobber, the 8-column workflow default) and its config/no-clobber assertions.
> Task 5 adds the **forgejo branch + the `registry.sh add` delegation** and the no-touch / delegation
> assertions. Task 4's test pre-stages the registry/gh/curl logging stubs in the setup block (so they
> are on `PATH` when Task 5's appended cases run) but asserts only config + no-clobber.

**Files:**
- Create: `bin/adopt-register.sh`
- Test: `tests/scripts/test_adopt_register.sh`

**Acceptance Criteria:**
- [ ] AC6: writes `harness-config.json` with `.forge` + github coords
- [ ] AC7: fresh config emits the 8-column workflow (`.workflow.kind==gen-eval-8col`; `actionable_columns` contains no retired slug `research`/`needs_input`/`approval`)
- [ ] AC8: no-clobber — a pre-existing config is preserved byte-for-byte
- [ ] AC12: `bash tests/scripts/test_backend_no_inline_gh.sh` passes

**Step 1: Write the failing test**

Create `tests/scripts/test_adopt_register.sh` (Task 4 version — github config + no-clobber; Task 5 appends forgejo + delegation + no-touch):
```bash
#!/usr/bin/env bash
# adopt-register.sh (#27 T6): register-only adopt. Writes config (no-clobber,
# 8-column default) and (added in Task 5) delegates the registry entry to
# registry.sh, making ZERO forge calls. registry.sh (#27 T2) and the forge
# binaries are stubbed; the stubs pre-stage Task 5's delegation + no-touch asserts.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/lib/assert.sh"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bin"; mkdir -p "$BIN"
cp "$REPO_ROOT/bin/adopt-register.sh" "$BIN/adopt-register.sh"

# registry.sh stub (#27 T2's CLI) — logs its argv, succeeds. (Used by Task 5.)
REGLOG="$TMP/registry.log"; : > "$REGLOG"
cat > "$BIN/registry.sh" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$REGLOG"
EOF
chmod +x "$BIN/registry.sh"

# Logging gh/curl stubs — ANY invocation is a no-touch violation (asserted in Task 5).
GHLOG="$TMP/gh.log";     : > "$GHLOG"
CURLLOG="$TMP/curl.log"; : > "$CURLLOG"
cat > "$BIN/gh"   <<EOF
#!/usr/bin/env bash
echo "gh \$*" >> "$GHLOG"
EOF
cat > "$BIN/curl" <<EOF
#!/usr/bin/env bash
echo "curl \$*" >> "$CURLLOG"
EOF
chmod +x "$BIN/gh" "$BIN/curl"

# --- Case A: fresh adopt (no config yet) -----------------------------------
TARGET="$TMP/proj"; mkdir -p "$TARGET"
PATH="$BIN:$PATH" "$BIN/adopt-register.sh" \
  --name story-spark --forge github --owner acme --repo story-spark \
  --path "$TARGET" --project-number 7

CFG="$TARGET/harness-config.json"
assert_eq "github"      "$(jq -r '.forge' "$CFG")"          "register-only writes forge"  || exit 1
assert_eq "acme"        "$(jq -r '.github.owner' "$CFG")"   "register-only writes owner"  || exit 1
assert_eq "story-spark" "$(jq -r '.github.repo' "$CFG")"    "register-only writes repo"   || exit 1
assert_eq "7"           "$(jq -r '.github.project_number' "$CFG")" "register-only writes project_number" || exit 1

# 8-column default (NOT the retired gen-eval-9col scheme; #27 T5/#52 reshape).
assert_eq "gen-eval-8col" "$(jq -r '.workflow.kind' "$CFG")" "register-only writes 8-col workflow kind" || exit 1
jq -e '.workflow.actionable_columns | any(. == "research" or . == "needs_input" or . == "approval")' "$CFG" >/dev/null \
  && { echo "FAIL: stale 9-col slug in actionable_columns" >&2; exit 1; } || true

# --- Case B: no-clobber (config already emitted by T4) ---------------------
SENT="$TMP/proj2"; mkdir -p "$SENT"
printf '%s' '{"name":"pre","forge":"github","github":{"owner":"x","repo":"y"},"_sentinel":true}' > "$SENT/harness-config.json"
BEFORE=$(cat "$SENT/harness-config.json")
PATH="$BIN:$PATH" "$BIN/adopt-register.sh" \
  --name pre --forge github --owner x --repo y --path "$SENT"
assert_eq "$BEFORE" "$(cat "$SENT/harness-config.json")" "no-clobber preserves emitted config" || exit 1

echo "test_adopt_register: PASS"
```

**Step 2: Run test to verify it fails**
Run: `bash tests/scripts/test_adopt_register.sh`
Expected: FAIL — `bin/adopt-register.sh: No such file or directory`.

**Step 3: Write minimal implementation**

Create `bin/adopt-register.sh` (Task 4 version — github config write + no-clobber; the forgejo branch + registry delegation are added in Task 5):
```bash
#!/usr/bin/env bash
# Register-only adopt (#27 T6): bring an existing repo under oskr management
# WITHOUT touching its board/columns/issues. Writes harness-config.json
# (no-clobber — preserves a config init's emission already wrote). Makes ZERO
# forge calls — that no-touch guarantee is what lets oskr manage a project that
# keeps its own board/workflow. The heavy harvest->reconcile->re-emit migration
# is the OTHER consent-gate branch (#27 T7), never this path.
#
# Usage (Task 4 — github):
#   adopt-register.sh --name N --forge github --owner O --repo R --path DIR [--project-number P]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

NAME="" FORGE="github" OWNER="" REPO="" TARGET="" PROJECT_NUMBER=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)           NAME="$2";           shift 2;;
    --forge)          FORGE="$2";          shift 2;;
    --owner)          OWNER="$2";          shift 2;;
    --repo)           REPO="$2";           shift 2;;
    --path)           TARGET="$2";         shift 2;;
    --project-number) PROJECT_NUMBER="$2"; shift 2;;
    *) echo "adopt-register: unknown arg: $1" >&2; exit 2;;
  esac
done
[[ -n "$NAME" && -n "$OWNER" && -n "$REPO" && -n "$TARGET" ]] \
  || { echo "adopt-register: --name --owner --repo --path are required" >&2; exit 2; }

CFG="$TARGET/harness-config.json"
# No-clobber: if init's config emission (#27 T4) already wrote it, preserve it.
if [[ ! -f "$CFG" ]]; then
  forge_block=$(jq -nc --arg o "$OWNER" --arg r "$REPO" \
    --argjson pn "${PROJECT_NUMBER:-null}" '{github: {owner:$o, repo:$r, project_number:$pn}}')
  # 8-column scheme (#27 T5/#52 reshape) — NOT the retired gen-eval-9col block.
  # T5 owns the canonical scheme; this default mirrors the PRD-declared columns and
  # fires ONLY on the fresh-config path (no-clobber means T4/T5 emission wins when present).
  jq -n --arg name "$NAME" --arg forge "$FORGE" --argjson fb "$forge_block" '
    { name: $name, forge: $forge }
    + $fb
    + { workflow: { kind: "gen-eval-8col", column_names: {}, actionable_columns: ["plan_approval","ready","in_review"] } }
  ' > "$CFG"
  jq . "$CFG" >/dev/null || { echo "adopt-register: wrote malformed config" >&2; exit 1; }
fi

echo "adopt-register: $NAME config written (register-only; board untouched)"
```
Note: `forge_block` is a plain (not `local`) variable — this script runs as `main`, not a function, so `local` would error.

**Step 4: Run test to verify it passes**
Run: `bash tests/scripts/test_adopt_register.sh && bash tests/scripts/test_backend_no_inline_gh.sh`
Expected: PASS (both). The seam guard is clean because `adopt-register.sh` contains no `gh (api|issue|pr|label|project)` and no `curl`/`api/v1`.

**Step 5: Commit**
`git add bin/adopt-register.sh tests/scripts/test_adopt_register.sh && git commit -m "feat(#61): adopt-register.sh config write + no-clobber (8-col default)"`

---

## Task 5: `bin/adopt-register.sh` — registry delegation + no-touch + forgejo coords

**Files:**
- Modify: `bin/adopt-register.sh` (add forgejo branch + `registry.sh add` delegation)
- Modify: `tests/scripts/test_adopt_register.sh` (append forgejo + delegation + no-touch cases)

**Acceptance Criteria:**
- [ ] AC9: delegates the registry entry to `registry.sh add` with the exact outgoing flags (no inline registry jq)
- [ ] AC10: **no-touch** — zero `gh`/`curl` invocations
- [ ] AC11: writes forgejo coords (`.forge==forgejo`, `.forgejo.base_url`)
- [ ] AC12: `bash tests/scripts/test_backend_no_inline_gh.sh` passes

**Step 1: Write the failing test**

Append to `tests/scripts/test_adopt_register.sh`, **before** the final `echo "...: PASS"` line:
```bash
# --- Case A delegation + no-touch (script now calls registry.sh add) --------
# registry delegated to registry.sh add with the EXACT outgoing argv this script
# emits (pins the contract #27 T2 must satisfy; see plan cross-task note).
grep -qF 'add'              "$REGLOG" || { echo "FAIL: registry.sh 'add' not invoked" >&2; exit 1; }
grep -qF -- '--name story-spark' "$REGLOG" || { echo "FAIL: registry missing --name" >&2; exit 1; }
grep -qF -- '--forge github'     "$REGLOG" || { echo "FAIL: registry missing --forge" >&2; exit 1; }
grep -qF -- '--owner acme'       "$REGLOG" || { echo "FAIL: registry missing --owner" >&2; exit 1; }
grep -qF -- '--repo story-spark' "$REGLOG" || { echo "FAIL: registry missing --repo" >&2; exit 1; }
grep -qF -- '--path'             "$REGLOG" || { echo "FAIL: registry missing --path" >&2; exit 1; }

# NO-TOUCH: zero forge calls across every case above.
[[ ! -s "$GHLOG"   ]] || { echo "FAIL: register-only invoked gh (board touched)" >&2;   cat "$GHLOG"   >&2; exit 1; }
[[ ! -s "$CURLLOG" ]] || { echo "FAIL: register-only invoked curl (board touched)" >&2; cat "$CURLLOG" >&2; exit 1; }

# --- Case C: forgejo coords ------------------------------------------------
FJ="$TMP/proj3"; mkdir -p "$FJ"
PATH="$BIN:$PATH" "$BIN/adopt-register.sh" \
  --name sluice --forge forgejo --owner squirrlylabs --repo sluice \
  --path "$FJ" --base-url https://git.squirrlylabs.dev
assert_eq "forgejo"                       "$(jq -r '.forge' "$FJ/harness-config.json")"            "forgejo forge"   || exit 1
assert_eq "https://git.squirrlylabs.dev"  "$(jq -r '.forgejo.base_url' "$FJ/harness-config.json")" "forgejo base_url" || exit 1
assert_eq "gen-eval-8col"                 "$(jq -r '.workflow.kind' "$FJ/harness-config.json")"    "forgejo 8-col"   || exit 1
```

**Step 2: Run test to verify it fails**
Run: `bash tests/scripts/test_adopt_register.sh`
Expected: FAIL — `FAIL: registry.sh 'add' not invoked` (the Task-4 script never calls `registry.sh`), and Case C fails because `--base-url` is an unknown arg in the Task-4 parser.

**Step 3: Write minimal implementation**

Edit `bin/adopt-register.sh`. (a) Add the `--base-url` option to the arg-parse loop and a `BASE_URL=""` initializer:
```bash
NAME="" FORGE="github" OWNER="" REPO="" TARGET="" PROJECT_NUMBER="" BASE_URL=""
```
```bash
    --base-url)       BASE_URL="$2";       shift 2;;
```
(b) Replace the single github `forge_block` line with a forge-branched build (still inside the `if [[ ! -f "$CFG" ]]` no-clobber block, before the `jq -n ...` that assembles the config):
```bash
  if [[ "$FORGE" == "forgejo" ]]; then
    [[ -n "$BASE_URL" ]] || { echo "adopt-register: --base-url required for forgejo" >&2; exit 2; }
    forge_block=$(jq -nc --arg u "$BASE_URL" --arg o "$OWNER" --arg r "$REPO" \
      '{forgejo: {base_url:$u, owner:$o, repo:$r}}')
  else
    forge_block=$(jq -nc --arg o "$OWNER" --arg r "$REPO" \
      --argjson pn "${PROJECT_NUMBER:-null}" '{github: {owner:$o, repo:$r, project_number:$pn}}')
  fi
```
(c) Add the registry delegation as the final step (after the no-clobber block, before the closing echo):
```bash
# Registry entry — delegated to the canonical registry CLI (#27 T2). No inline
# registry jq here (PRD: registry.sh owns the registry shape). Board untouched.
extra=()
[[ -n "$PROJECT_NUMBER" ]] && extra+=(--project-number "$PROJECT_NUMBER")
[[ -n "$BASE_URL"       ]] && extra+=(--base-url "$BASE_URL")
"$SCRIPT_DIR/registry.sh" add \
  --name "$NAME" --path "$TARGET" --forge "$FORGE" --owner "$OWNER" --repo "$REPO" \
  "${extra[@]+"${extra[@]}"}"
```
The `"${extra[@]+"${extra[@]}"}"` empty-array-safe expansion mirrors the bash-3.2 idiom already in `harness-lib.sh:793` (`_blacksmith_forgejo_create_issue`).

**Step 4: Run test to verify it passes**
Run: `bash tests/scripts/test_adopt_register.sh && bash tests/scripts/test_backend_no_inline_gh.sh`
Expected: PASS (both). Delegation is asserted via the registry stub log; no-touch via the empty gh/curl logs; the seam guard stays green because the only sub-process exec is `registry.sh` (a sibling `bin/` script), not `gh`/`curl`.

**Step 5: Commit**
`git add bin/adopt-register.sh tests/scripts/test_adopt_register.sh && git commit -m "feat(#61): adopt-register.sh registry delegation + no-touch + forgejo"`

---

## Task 6: Wire the consent gate into `skills/init/SKILL.md` (harness-infra: AC → grep → implement)

**TDD substitution (declared):** this task edits skill prose (no runtime). It uses **write AC → grep/structural check → implement**, not RED-test-first.

**Files:**
- Modify: `skills/init/SKILL.md` (frontmatter `allowed-tools` + additive consent-gate section)

**Acceptance Criteria:**
- [ ] AC13: `grep -qF 'adopt-detect.sh' skills/init/SKILL.md && grep -qF 'adopt-register.sh' skills/init/SKILL.md && grep -qiF 'never auto-migrate' skills/init/SKILL.md && grep -qF 'Register-only' skills/init/SKILL.md` → exit 0

**Step 1: Write the acceptance check**
Run: `grep -qF 'adopt-detect.sh' skills/init/SKILL.md && grep -qF 'adopt-register.sh' skills/init/SKILL.md && grep -qiF 'never auto-migrate' skills/init/SKILL.md && grep -qF 'Register-only' skills/init/SKILL.md`
Expected (before edit): FAIL (no match)

**Step 2: Implement — frontmatter + additive section**

(a) In the YAML frontmatter `allowed-tools` (line 5), add the two scripts (keep all existing entries):
```
allowed-tools: Bash(gh *) Bash(git *) Bash(mkdir *) Bash(touch *) Bash(jq *) Bash(cat *) Bash(echo *) Bash(test *) Bash(find-item.sh*) Bash(move-issue.sh*) Bash(adopt-detect.sh*) Bash(adopt-register.sh*) Read Write Edit
```

(b) Add this **additive** section after Phase 5 / before Phase 6 (it is wired into the adopt branch that init v2 mode-detection — #27 T4 — adds to Phase 0; it does not require rewriting Phase 0 here):
```markdown
## Phase 5b: Adopt — consent gate & register-only (adopt mode only)

This phase runs ONLY in **adopt** mode (an existing local repo with a remote, classified
by mode-detection). oskr **never auto-migrates** an adopted repo — it detects whether the
repo already has a workflow and asks the developer how to proceed.

1. **Detect existing issues.** With the adopt config already emitted (forge + coords),
   probe the forge through the blacksmith:
   ```bash
   VERDICT=$(adopt-detect.sh)   # "existing <N>"  or  "empty 0"
   ```

2. **Branch on the verdict — never auto-migrate:**
   - **`empty 0`** — the repo has no existing issues. There is nothing to migrate;
     proceed without a migration prompt (register-only, or new-style provisioning if the
     developer asked for it). Do NOT prompt.
   - **`existing <N>`** — the repo already has issues/a board. **Stop and ask:**
     > This repo has N existing issues. How should oskr adopt it?
     > [1] **Register-only** — manage it without changing your board, columns, or issues
     >     (for a shared project that keeps its own structure/skills, e.g. story-spark-child).
     > [2] **Full migration** — harvest → reconcile → re-emit into oskr's Epoch/Area/Task
     >     board (#27 T7).
     > (default: 1)

3. **Register-only (choice 1)** — bring the repo under management with no board changes:
   ```bash
   EXTRA=()
   [ -n "$PROJECT_NUMBER" ] && EXTRA+=(--project-number "$PROJECT_NUMBER")
   [ -n "$BASE_URL" ]       && EXTRA+=(--base-url "$BASE_URL")
   adopt-register.sh --name "$NAME" --forge "$FORGE" \
     --owner "$OWNER" --repo "$REPO" --path "$CWD" "${EXTRA[@]}"
   ```
   This writes `harness-config.json` (if not already emitted) + a registry entry and
   touches **nothing** on the forge — the existing board is left exactly as it was.

4. **Full migration (choice 2)** — hand off to the harvest → reconcile → re-emit flow
   (#27 T7). Out of scope for the register-only path.
```

**Step 3: Run the acceptance check to verify it passes**
Run: `grep -qF 'adopt-detect.sh' skills/init/SKILL.md && grep -qF 'adopt-register.sh' skills/init/SKILL.md && grep -qiF 'never auto-migrate' skills/init/SKILL.md && grep -qF 'Register-only' skills/init/SKILL.md`
Expected: exit 0

**Step 4: Sanity — frontmatter still carries the new allow-entry**
Run: `head -6 skills/init/SKILL.md | grep -qF 'adopt-register.sh*'`
Expected: exit 0

**Step 5: Commit**
`git add skills/init/SKILL.md && git commit -m "docs(#61): wire adopt consent gate + register-only into init"`

---

## Task 7: Full-suite green + version bump

**Files:**
- Modify: `.claude-plugin/plugin.json` (version bump)

**Acceptance Criteria:**
- [ ] AC14: `bash tests/scripts/run-tests.sh` → exit 0, final line reports `0 failed`
- [ ] AC15: `test "$(jq -r '.version' .claude-plugin/plugin.json)" != "0.3.5"` → exit 0

**Step 1: Establish the failing/initial state**
Run: `jq -r '.version' .claude-plugin/plugin.json`
Expected: prints `0.3.5` (the current value in this worktree; if a sibling already bumped it on the Area branch, bump to the next patch above the current value instead).

**Step 2: Bump the version (patch — adds bin verbs, not a new skill/command)**
Edit `.claude-plugin/plugin.json` line 4: `"version": "0.3.5"` → `"version": "0.3.6"`.
(Per CLAUDE.md: every PR bumps the manifest; this slice is a patch — new `bin/` verbs, no new skill/agent/command. If the current value is already > 0.3.5, increment the patch from there.)

**Step 3: Run the whole hermetic suite**
Run: `bash tests/scripts/run-tests.sh`
Expected: PASS — last line `Results: N/N passed, 0 failed (N tests)`. The three new tests (`test_blacksmith_count_issues.sh`, `test_adopt_detect.sh`, `test_adopt_register.sh`) auto-discover and pass; `test_backend_no_inline_gh.sh` stays green.

**Step 4: Verify the version AC**
Run: `test "$(jq -r '.version' .claude-plugin/plugin.json)" != "0.3.5"`
Expected: exit 0

**Step 5: Commit**
`git add .claude-plugin/plugin.json && git commit -m "chore(#61): bump version for adopt consent gate + register-only"`

---

## Cross-task dependencies

**Within this plan (strict order):**
1. Task 1 (GitHub `count_issues` + shim route + fixtures) → blocks Task 2 (Forgejo block reuses the same test file), Task 3 (detect CLI calls the verb), and the fixtures Tasks 3–5 reuse.
2. Task 3 and Task 4 are independent of each other (both depend only on Task 1's fixtures / verb).
3. Task 5 extends Task 4's script + test (forgejo branch, registry delegation, no-touch) → strictly after Task 4.
4. Task 6 references `adopt-detect.sh` (Task 3) and `adopt-register.sh` (Tasks 4–5) — do it after both.
5. Task 7 last (full suite must see all new tests).

**Cross-issue (Area #27) — declared, with test decoupling:**
- **#27 T4 (init v2 mode-detection + config emission):** the consent gate runs *after* T4 classifies the repo as `adopt` and emits `harness-config.json` (forge + coords). The detection verb reads those coords. The hermetic tests supply config fixtures, so they pass without T4; only the live `skills/init` adopt branch needs T4 merged. Task 6's section is **additive** (Phase 5b) to avoid colliding with T4's Phase 0 rewrite.
- **#27 T5 / #52 (8-column reshape):** T5 owns the canonical provisioning scheme — columns `Backlog · Scoping · Planning · Plan Approval · Ready · In Progress · In Review · Done` and the `actionable_columns` migration off `research`/`needs_input`/`approval`. Register-only's fresh-config default (`adopt-register.sh`, Task 4) mirrors that 8-column scheme (`kind: gen-eval-8col`, `actionable_columns: ["plan_approval","ready","in_review"]`) so it never writes the stale 9-column block. This default fires ONLY when T4 has not already emitted config (no-clobber). **Reconcile note:** if T5 lands a different canonical `kind` token or actionable set, update this default and AC7 to match T5's value — they are a fallback, not a second source of truth.
- **#27 T2 (`bin/registry.sh add`):** register-only's registry write delegates to `registry.sh add` (PRD forbids new inline registry jq). `bin/registry.sh` does **not exist yet** in this worktree (confirmed). `test_adopt_register.sh` **stubs** `registry.sh`, so this plan's tests are green independent of T2; the live register-only path needs T2 merged.
  - **Outgoing contract `adopt-register.sh` requires T2 to satisfy** (pinned by AC9 against the stub log):
    `registry.sh add --name <N> --path <DIR> --forge <github|forgejo> --owner <O> --repo <R> [--project-number <P>] [--base-url <URL>]` → exit 0, idempotent add.
  - **Residual integration risk:** the stub accepts any argv beyond the flags AC9 greps, so a T2 parser that *rejects* an unexpected ordering/flag would not be caught by the hermetic suite. AC9 pins only the *outgoing* argv.
  - **Deferred post-T2 integration AC** (NOT runnable until T2 lands; add to the Area merge gate once `bin/registry.sh` exists on `WillyDallas/27`):
    `Run: D=$(mktemp -d); bash bin/adopt-register.sh --name itest --forge github --owner o --repo r --path "$D" --project-number 9 && bash bin/registry.sh list | grep -qF itest`
    `Expected: exit 0` — proves the real T2 parser accepts adopt-register's emitted argv end-to-end.
- **#27 T7 (full harvest→reconcile→re-emit):** the *other* consent-gate branch; explicitly out of scope here (register-only only).

**Deferred (not this issue):** live Forgejo / coremyotherapy migration acceptance → Area 5.
