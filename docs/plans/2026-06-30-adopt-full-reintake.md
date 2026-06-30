# Adopt — full harvest→reconcile→re-emit re-intake — Implementation Plan

**Goal:** Give `init`'s adopt path the heavy brownfield migration arm — harvest every existing issue into a reconciliation tasklist, let the developer reconcile current state by hand, then re-emit the result as oskr board structure (1 Epoch milestone, phases→`type/umbrella`+`area/*` Areas, slim `## Parent`/`## What`/`## AC` tasks linked beneath, `delivery/manual`, dispatch off) — built and fixture-proven, with the live coremyotherapy run deferred to Area 5.
**Architecture:** Two new seam-tested `bin/` verbs — `adopt-harvest.sh` (reads all repo issues via a new backend-neutral `blacksmith_list_issues` and renders a markdown tasklist) and `adopt-reemit.sh` (consumes a reconciled-plan JSON and drives the existing blacksmith write verbs plus a new `blacksmith_create_milestone`). Both route exclusively through `harness-lib.sh` (no inline `gh`/`curl`), so they're proven hermetically via `lib/gh-shim.sh` PATH-boundary replay. The interactive reconcile step is a documented guided checklist, never an automated test.
**Tech Stack:** Bash 3.2 (macOS) + `jq`; the hermetic `tests/scripts/` gh-shim/curl-shim replay harness; the `_blacksmith_*` forge-adapter layer in `bin/harness-lib.sh`.
**Issue:** #62 (T7, child of Area #27 — Workspace & setup)

---

## Context the implementer must hold

- **The seam is the `bin/` verb boundary, replayed with shims.** Prior art is exact: `tests/scripts/test_blacksmith_create_issue.sh` (create + board-add via gh-shim, `GH_SHIM_CALL_LOG` assertions), `test_blacksmith_link_children.sh` (sub-issues by DB id), and `test_blacksmith_set_milestone.sh` (both forges in one file). Copy their harness scaffolding (`mktemp -d`, `cp lib/gh-shim.sh "$SHIM_DIR/gh"`, `PATH="$SHIM_DIR:$PATH"`, `GH_SHIM_*` env) verbatim — do not invent a new test style.
- **Re-emit reuses landed verbs; it adds exactly ONE new write verb.** `blacksmith_create_issue` (`harness-lib.sh:597`), `blacksmith_set_milestone` (`:663`), `blacksmith_link_parent` (`:636`), and `blacksmith_ensure_label` (`:548`) already exist. The gap is milestone *creation*: `set_milestone` resolves a title that **must already exist** (`harness-lib.sh:663-674`). Adopt is the intake — nothing creates the Epoch first — so re-emit needs an idempotent find-or-create `blacksmith_create_milestone`. That is a deliberate, minimal addition (justified, not scope creep).
- **Harvest reads ALL repo issues, not the board.** A brownfield project's backlog is largely off-board, so `blacksmith_list_board` is wrong here. The new `blacksmith_list_issues` lists every repo issue (open+closed) via REST and **filters out pull requests** (GitHub's issues endpoint returns PRs; drop any node with a `pull_request` key).
- **Both forges implement the new verbs (blacksmith contract).** Every public verb dispatches to `_blacksmith_<forge>_<op>`; a missing impl dies loudly (`harness-lib.sh:74-76`). For symmetry with the existing op-set, implement `list_issues` and `create_milestone` for **both** GitHub and Forgejo. The Forgejo paths are curl-shim-tested but **live Forgejo acceptance stays Area 5** — the coremyotherapy migration this slice fixture-proves is a GitHub repo.
- **"Dispatch off" has two halves; T7 owns the issue-level half.** Re-emit (a) labels every emitted task `delivery/manual`, and (b) performs **no Status move** — issues land freshly created on the board with no column, never pushed into an actionable column. The project-config-level default (`delivery: manual` + loop disabled) is **T6's** config emission, not this slice. The testable T7 assertion is: zero `updateProjectV2ItemFieldValue` calls in the re-emit log.
- **Slim bodies are the contract.** Re-emitted issues carry `## Parent` / `## What` / `## AC` only — **no `touches:`**, no TDD-shaped ACs (that's the per-task plan's job, mirroring `decompose` which also omits `touches:`, `skills/decompose/SKILL.md:19`). The gh-shim flattens newlines into the call log, so body assertions are plain `grep -qF '## Parent'` / `! grep -qF 'touches:'`.
- **Seam guard stays green.** `bin/adopt-harvest.sh` / `bin/adopt-reemit.sh` issue no inline `gh`/`curl` (only `blacksmith_*`) and both `source harness-lib.sh`, so `test_backend_no_inline_gh.sh` passes them (it also runs `bash -n` on every bin script).
- **gh-shim gains two opt-in routes.** Both are guarded by env vars unset in existing tests, so the rest of the suite is unaffected: (1) milestone-create POST → `GH_SHIM_CREATE_MILESTONE_FIXTURE`; (2) single-issue GET/PATCH → `GH_SHIM_ISSUE_FIXTURE` (needed because `link_parent` resolves the child's DB `.id` from `GET /issues/<n>`, and that call would otherwise collide with the discovery fixture create_issue's board-add needs).

---

## Definition of Done (frozen contract)

1. **Deliverables:**
   - Modify: `bin/harness-lib.sh` — new verbs `blacksmith_list_issues`, `blacksmith_create_milestone` (+ both forge impls).
   - Create: `bin/adopt-harvest.sh`, `bin/adopt-reemit.sh`.
   - Create tests: `tests/scripts/test_blacksmith_list_issues.sh`, `tests/scripts/test_blacksmith_create_milestone.sh`, `tests/scripts/test_adopt_harvest.sh`, `tests/scripts/test_adopt_reemit.sh`.
   - Create fixtures: `tests/scripts/fixtures/gh-existing-issues.json`, `gh-create-milestone.json`, `gh-milestones-adopt.json`, `reconciled-plan.json`.
   - Modify: `tests/scripts/lib/gh-shim.sh` (two opt-in routes).
   - Create: `docs/adopt-reintake.md` (the reconcile guided checklist).
   - Modify: `skills/init/SKILL.md` (wire the full-migration arm to the bin verbs + reconcile doc).
   - Modify: `.claude-plugin/plugin.json` (version bump).
2. **Testing tier:** hermetic integration at the `bin/` verb boundary — the umbrella's single Named Seam — via gh-shim/curl-shim PATH-boundary replay. Justification: every automatable behavior is "given this fixture tree + shimmed forge responses, the verb yields these board ops / this artifact." No unit-pure layer exists below the verb worth isolating; no live forge call is in scope (Area 5 owns that).
3. **Task granularity:** each task ≤ 5 min implementer work (one verb pair or one bin verb or one doc/skill edit, plus its test).
4. **Verification:** every t7.md AC maps to a runnable command (AC→verification map below). The interactive reconcile step is the **only** manual surface — verified by a grep over the guided-checklist doc, with an explicit assertion that **no** automated reconcile test exists (per the "manual steps are acceptable" principle).
5. **Dependencies:** declared in the final section. Cross-task: **blocked-by T6** (#27 adopt consent gate + register-only path — Task 7 attaches the full-migration arm to that gate). Shared files: `bin/harness-lib.sh`, `tests/scripts/lib/gh-shim.sh`, `skills/init/SKILL.md`, `.claude-plugin/plugin.json`.
6. **Harness-task exceptions (Tasks 6 & 7):** `docs/adopt-reintake.md` and the `skills/init/SKILL.md` edit are prose/agent-instruction, not executable code. Per the agent definition they use **write-acceptance-criterion → grep/structural check → implement** in place of RED-test-first. Flagged here so plan-reviewer treats the substitution as deliberate.

---

## AC → verification map

All `Run:` commands assume repo root `.`.

| t7.md AC | Where satisfied | Run | Expected |
|---|---|---|---|
| (1) Harvest reads all existing issues into a tasklist artifact | Task 1 (`blacksmith_list_issues`) + Task 2 (`adopt-harvest.sh`) | `bash tests/scripts/test_blacksmith_list_issues.sh && bash tests/scripts/test_adopt_harvest.sh` | exit 0 |
| (2) Re-emit → 1 Epoch milestone; phases→`type/umbrella`+`area/*`; tasks linked beneath | Task 3 (`blacksmith_create_milestone`) + Tasks 4–5 (`adopt-reemit.sh`) | `bash tests/scripts/test_adopt_reemit.sh` | exit 0 |
| (3) Slim `## Parent`/`## What`/`## AC` (no `touches:`/TDD-ACs), `delivery/manual`, dispatch off | Task 5 (re-emit task arm) | `bash tests/scripts/test_adopt_reemit.sh` | exit 0 (asserts `## Parent`, `! touches:`, `labels[]=delivery/manual`, `! updateProjectV2ItemFieldValue`) |
| (4) Harvest + re-emit board ops proven via gh-shim replay against an "existing issues" fixture; no live run | Tasks 1–5 (all shim-replayed) | `bash tests/scripts/run-tests.sh` | exit 0 — `Results: N/N passed, 0 failed` |
| (5) Reconcile step is a documented guided checklist, not an automated test | Task 6 (`docs/adopt-reintake.md`) | `grep -qiF 'guided checklist' docs/adopt-reintake.md && ! test -f tests/scripts/test_adopt_reconcile.sh` | exit 0 |

---

## Task 1: `blacksmith_list_issues` — the harvest read primitive (both forges)

**Files:**
- Modify: `bin/harness-lib.sh`
- Create: `tests/scripts/fixtures/gh-existing-issues.json`
- Create: `tests/scripts/test_blacksmith_list_issues.sh`

**Acceptance Criteria:**
- [ ] `blacksmith_list_issues` (GitHub) echoes a normalized array `[ {number,title,state,body,labels:[name]} ]` over `GET /repos/{owner}/{repo}/issues?state=all`.
- [ ] Pull requests are excluded (any node with a `pull_request` key dropped).
- [ ] Forgejo dispatch returns the same neutral shape from `GET /repos/{owner}/{repo}/issues?type=issues&state=all`.
- [ ] `bash -n bin/harness-lib.sh` parses; `test_backend_no_inline_gh.sh` still passes.

**Step 1: Write the failing test** — `tests/scripts/test_blacksmith_list_issues.sh`

```bash
#!/usr/bin/env bash
# blacksmith_list_issues (adopt harvest read primitive): list ALL repo issues
# (open+closed; PRs excluded) as the neutral [ {number,title,state,body,labels} ]
# array, on both forges. The off-board backlog source for full-migration adopt.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB="$REPO_ROOT/bin/harness-lib.sh"
FIX="$REPO_ROOT/tests/scripts/fixtures"
source "$SCRIPT_DIR/lib/assert.sh"

SHIM_DIR=$(mktemp -d); trap 'rm -rf "$SHIM_DIR"' EXIT
cp "$SCRIPT_DIR/lib/gh-shim.sh"   "$SHIM_DIR/gh";   chmod +x "$SHIM_DIR/gh"
cp "$SCRIPT_DIR/lib/curl-shim.sh" "$SHIM_DIR/curl"; chmod +x "$SHIM_DIR/curl"

# --- GitHub: all issues, PRs filtered ---
LOG="$SHIM_DIR/gh.log"; : > "$LOG"
out=$(PATH="$SHIM_DIR:$PATH" \
  HARNESS_CONFIG="$FIX/harness-config.sample.json" \
  GH_SHIM_CALL_LOG="$LOG" \
  GH_SHIM_FIXTURE="$FIX/gh-existing-issues.json" \
  bash -c "source '$LIB'; blacksmith_list_issues")

assert_eq "2"  "$(jq 'length' <<<"$out")"            "github: PRs filtered, 2 issues" || exit 1
assert_eq "12" "$(jq -r '.[0].number' <<<"$out")"    "github: first issue number"     || exit 1
assert_eq "open"   "$(jq -r '.[0].state' <<<"$out")" "github: first issue state"      || exit 1
assert_eq '["bug"]' "$(jq -c '.[0].labels' <<<"$out")" "github: labels normalized to names" || exit 1
if jq -e '.[] | select(.number==5)' <<<"$out" >/dev/null; then echo "FAIL: PR #5 not filtered" >&2; exit 1; fi
grep -qF 'issues?state=all' "$LOG" || { echo "FAIL: did not list all repo issues" >&2; exit 1; }

# --- Forgejo: same neutral shape from the gitea issues list ---
LOG2="$SHIM_DIR/curl.log"; : > "$LOG2"
fout=$(PATH="$SHIM_DIR:$PATH" \
  HARNESS_CONFIG="$FIX/harness-config.forgejo.json" \
  FORGEJO_TOKEN="test-token" \
  CURL_SHIM_CALL_LOG="$LOG2" \
  CURL_SHIM_LIST_FIXTURE="$FIX/forgejo-issues-list.json" \
  bash -c "source '$LIB'; blacksmith_list_issues")

assert_eq "2"  "$(jq 'length' <<<"$fout")"         "forgejo: 2 issues"      || exit 1
assert_eq "10" "$(jq -r '.[0].number' <<<"$fout")" "forgejo: first number"  || exit 1
grep -qF 'type=issues' "$LOG2" || { echo "FAIL: forgejo must request type=issues (exclude PRs)" >&2; exit 1; }

echo "test_blacksmith_list_issues: PASS"
```

And the fixture — `tests/scripts/fixtures/gh-existing-issues.json`:

```json
[
  { "number": 12, "title": "Fix login redirect", "state": "open",   "body": "Users bounce to /",  "labels": [ { "name": "bug" } ] },
  { "number": 8,  "title": "CSV export",         "state": "closed", "body": "shipped last sprint", "labels": [] },
  { "number": 5,  "title": "Refactor auth",      "state": "open",   "body": "PR not an issue",    "pull_request": { "url": "x" }, "labels": [] }
]
```

**Step 2: Run test to verify it fails**
Run: `bash tests/scripts/test_blacksmith_list_issues.sh`
Expected: FAIL — `blacksmith_list_issues` is undefined (dispatch dies / command not found, non-zero).

**Step 3: Write minimal implementation** — in `bin/harness-lib.sh`

Add the public verb beside the other #26 graph/write primitives (after line 104, `blacksmith_base_branch`):

```bash
blacksmith_list_issues()       { _blacksmith_dispatch list_issues "$@"; }
blacksmith_create_milestone()  { _blacksmith_dispatch create_milestone "$@"; }
```

(The `create_milestone` verb line is added now so both new public verbs sit together; its impls land in Task 3.)

Add the GitHub impl in the GitHub section (e.g. after `_blacksmith_github_read_deps`, near line 589):

```bash
# --- Issue harvest (adopt full-migration; #27) ------------------------------
# Echo ALL repo issues (open + closed; pull requests excluded) as the neutral
# array [ { number, title, state, body, labels:[name] } ]. The off-board backlog
# source the adopt harvest reconciles. Native REST list, paginated to 100.
#   list_issues
_blacksmith_github_list_issues() {
  local owner repo raw
  owner=$(blacksmith_config_get '.github.owner') || return 1
  repo=$(blacksmith_config_get '.github.repo')   || return 1
  raw=$(gh api "repos/${owner}/${repo}/issues?state=all&per_page=100" 2>/dev/null) \
    || { _blacksmith_die "list_issues query failed for ${owner}/${repo}"; return 1; }
  printf '%s' "$raw" | jq -c '[ .[]
    | select(has("pull_request") | not)
    | { number, title, state, body: (.body // ""), labels: [ (.labels // [])[] | .name ] } ]'
}
```

Add the Forgejo impl in the Forgejo section (e.g. after `_blacksmith_forgejo_read_deps`, near line 760):

```bash
# Forgejo harvest: same neutral shape. `type=issues` excludes PRs server-side.
_blacksmith_forgejo_list_issues() {
  local owner repo raw
  owner=$(blacksmith_config_get '.forgejo.owner') || return 1
  repo=$(blacksmith_config_get '.forgejo.repo')   || return 1
  raw=$(_blacksmith_forgejo_curl GET "/repos/${owner}/${repo}/issues?type=issues&state=all&limit=100") \
    || { _blacksmith_die "list_issues (forgejo) query failed"; return 1; }
  printf '%s' "$raw" | jq -c '[ .[]
    | { number, title, state, body: (.body // ""), labels: [ (.labels // [])[] | .name ] } ]'
}
```

**Step 4: Run test to verify it passes**
Run: `bash tests/scripts/test_blacksmith_list_issues.sh`
Expected: PASS — prints `test_blacksmith_list_issues: PASS`.
Also Run: `bash tests/scripts/test_backend_no_inline_gh.sh`
Expected: exit 0.

**Step 5: Commit** — `feat(blacksmith): list_issues harvest primitive (both forges) (#62)`

---

## Task 2: `bin/adopt-harvest.sh` — render the reconciliation tasklist

**Files:**
- Create: `bin/adopt-harvest.sh`
- Create: `tests/scripts/test_adopt_harvest.sh`

**Acceptance Criteria:**
- [ ] `adopt-harvest.sh <out_file>` writes a markdown tasklist with one `- [ ] #<n> <title> (<state>)` line per harvested issue.
- [ ] The artifact carries the machine marker `<!-- oskr:adopt-harvest -->`.
- [ ] PRs filtered upstream do not appear (e.g. no `#5`).
- [ ] Script sources `harness-lib.sh`, makes no inline `gh`/`curl`, and parses (`bash -n`).

**Step 1: Write the failing test** — `tests/scripts/test_adopt_harvest.sh`

```bash
#!/usr/bin/env bash
# adopt-harvest.sh: read all existing issues (via the blacksmith) into a markdown
# reconciliation tasklist. Backend-neutral; here proven on GitHub via gh-shim.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FIX="$REPO_ROOT/tests/scripts/fixtures"
source "$SCRIPT_DIR/lib/assert.sh"

SHIM_DIR=$(mktemp -d); OUT=$(mktemp); trap 'rm -rf "$SHIM_DIR" "$OUT"' EXIT
cp "$SCRIPT_DIR/lib/gh-shim.sh" "$SHIM_DIR/gh"; chmod +x "$SHIM_DIR/gh"
LOG="$SHIM_DIR/gh.log"; : > "$LOG"

PATH="$SHIM_DIR:$PATH" \
  HARNESS_CONFIG="$FIX/harness-config.sample.json" \
  GH_SHIM_CALL_LOG="$LOG" \
  GH_SHIM_FIXTURE="$FIX/gh-existing-issues.json" \
  "$REPO_ROOT/bin/adopt-harvest.sh" "$OUT"

grep -qF '<!-- oskr:adopt-harvest -->'              "$OUT" || { echo "FAIL: missing harvest marker" >&2; exit 1; }
grep -qF '- [ ] #12 Fix login redirect (open)'      "$OUT" || { echo "FAIL: open issue line missing" >&2; exit 1; }
grep -qF '- [ ] #8 CSV export (closed)'             "$OUT" || { echo "FAIL: closed issue line missing" >&2; exit 1; }
if grep -qF '#5' "$OUT"; then echo "FAIL: PR #5 leaked into the tasklist" >&2; exit 1; fi

echo "test_adopt_harvest: PASS"
```

**Step 2: Run test to verify it fails**
Run: `bash tests/scripts/test_adopt_harvest.sh`
Expected: FAIL — `bin/adopt-harvest.sh` does not exist (non-zero).

**Step 3: Write minimal implementation** — `bin/adopt-harvest.sh`

```bash
#!/usr/bin/env bash
# adopt-harvest.sh — full-migration adopt, step 1. Read ALL existing issues (via
# the blacksmith, so backend-neutral) into a markdown reconciliation tasklist. The
# developer then reconciles current state BY HAND (see docs/adopt-reintake.md)
# before adopt-reemit.sh re-emits the result. No forge calls inline — all through
# blacksmith_list_issues.
# Usage: adopt-harvest.sh <out_file>
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/harness-lib.sh"

out="${1:?usage: adopt-harvest.sh <out_file>}"
issues=$(blacksmith_list_issues) || exit 1
{
  echo "# Adopt harvest — reconcile current state, then re-emit"
  echo "<!-- oskr:adopt-harvest -->"
  echo
  echo "Reconcile this list by hand (see docs/adopt-reintake.md), then feed the"
  echo "reconciled plan to: adopt-reemit.sh <reconciled-plan.json>"
  echo
  printf '%s' "$issues" | jq -r '.[] | "- [ ] #\(.number) \(.title) (\(.state))"'
} > "$out"
echo "$out"
```

Then make it executable: `chmod +x bin/adopt-harvest.sh`.

**Step 4: Run test to verify it passes**
Run: `bash tests/scripts/test_adopt_harvest.sh`
Expected: PASS — prints `test_adopt_harvest: PASS`.
Also Run: `bash tests/scripts/test_backend_no_inline_gh.sh`
Expected: exit 0.

**Step 5: Commit** — `feat(adopt): adopt-harvest.sh — render reconciliation tasklist (#62)`

---

## Task 3: `blacksmith_create_milestone` — idempotent find-or-create (both forges)

**Files:**
- Modify: `bin/harness-lib.sh`
- Modify: `tests/scripts/lib/gh-shim.sh` (milestone-create POST route)
- Create: `tests/scripts/fixtures/gh-create-milestone.json`
- Create: `tests/scripts/test_blacksmith_create_milestone.sh`

**Acceptance Criteria:**
- [ ] `blacksmith_create_milestone <title>` echoes the milestone's native id (GitHub: number; Forgejo: id), creating it only if absent (idempotent find-or-create).
- [ ] When the title already exists, no create POST is issued.
- [ ] When the title is absent (GitHub), a `POST /milestones` with `title=<title>` is issued and its number returned.
- [ ] `bash -n bin/harness-lib.sh` parses; the full suite stays green (the new gh-shim route is opt-in).

**Step 1: Write the failing test** — `tests/scripts/test_blacksmith_create_milestone.sh`

```bash
#!/usr/bin/env bash
# blacksmith_create_milestone — idempotent find-or-create of an Epoch milestone by
# TITLE, echoing its native id. Adopt re-emit needs this because set_milestone only
# RESOLVES an existing milestone. Found-path issues no POST; absent-path creates.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB="$REPO_ROOT/bin/harness-lib.sh"
FIX="$REPO_ROOT/tests/scripts/fixtures"
source "$SCRIPT_DIR/lib/assert.sh"

SHIM_DIR=$(mktemp -d); trap 'rm -rf "$SHIM_DIR"' EXIT
cp "$SCRIPT_DIR/lib/gh-shim.sh"   "$SHIM_DIR/gh";   chmod +x "$SHIM_DIR/gh"
cp "$SCRIPT_DIR/lib/curl-shim.sh" "$SHIM_DIR/curl"; chmod +x "$SHIM_DIR/curl"

# --- GitHub found-path: "oskr v1" exists (number 3) -> no POST ---
LOG="$SHIM_DIR/found.log"; : > "$LOG"
n=$(PATH="$SHIM_DIR:$PATH" HARNESS_CONFIG="$FIX/harness-config.sample.json" \
  GH_SHIM_CALL_LOG="$LOG" GH_SHIM_FIXTURE="$FIX/gh-milestones.json" \
  GH_SHIM_MILESTONES_FIXTURE="$FIX/gh-milestones.json" \
  bash -c "source '$LIB'; blacksmith_create_milestone 'oskr v1'")
assert_eq "3" "$n" "github found-path returns existing milestone number" || exit 1
if grep -qF 'title=' "$LOG"; then echo "FAIL: found-path must not POST a create" >&2; exit 1; fi

# --- GitHub create-path: "New Epoch" absent -> POST create, number 9 ---
LOG2="$SHIM_DIR/create.log"; : > "$LOG2"
n2=$(PATH="$SHIM_DIR:$PATH" HARNESS_CONFIG="$FIX/harness-config.sample.json" \
  GH_SHIM_CALL_LOG="$LOG2" GH_SHIM_FIXTURE="$FIX/gh-milestones.json" \
  GH_SHIM_MILESTONES_FIXTURE="$FIX/gh-milestones.json" \
  GH_SHIM_CREATE_MILESTONE_FIXTURE="$FIX/gh-create-milestone.json" \
  bash -c "source '$LIB'; blacksmith_create_milestone 'New Epoch'")
assert_eq "9" "$n2" "github create-path returns new milestone number" || exit 1
grep -qF 'title=New Epoch' "$LOG2" || { echo "FAIL: create-path must POST title=New Epoch" >&2; exit 1; }

# --- Forgejo found-path: "oskr v1" exists (id 42) ---
LOG3="$SHIM_DIR/fj.log"; : > "$LOG3"
fid=$(PATH="$SHIM_DIR:$PATH" HARNESS_CONFIG="$FIX/harness-config.forgejo.json" \
  FORGEJO_TOKEN="test-token" CURL_SHIM_CALL_LOG="$LOG3" \
  CURL_SHIM_MILESTONES_FIXTURE="$FIX/forgejo-milestones.json" \
  bash -c "source '$LIB'; blacksmith_create_milestone 'oskr v1'")
assert_eq "42" "$fid" "forgejo found-path returns existing milestone id" || exit 1

echo "test_blacksmith_create_milestone: PASS"
```

And the fixture — `tests/scripts/fixtures/gh-create-milestone.json`:

```json
{ "number": 9, "title": "New Epoch", "state": "open" }
```

**Step 2: Run test to verify it fails**
Run: `bash tests/scripts/test_blacksmith_create_milestone.sh`
Expected: FAIL — `_blacksmith_github_create_milestone` missing → dispatch dies (non-zero).

**Step 3: Write minimal implementation**

First add the **opt-in gh-shim route** in `tests/scripts/lib/gh-shim.sh`, immediately **after** the `addProjectV2ItemById` block (so it precedes the generic `title=` and `/milestones` routes):

```bash
if [[ "$args" == */milestones* && "$args" == *"title="* ]]; then   # POST create milestone (opt-in)
  emit < "${GH_SHIM_CREATE_MILESTONE_FIXTURE:-/dev/null}"; exit 0
fi
```

Then the GitHub impl in `bin/harness-lib.sh` (next to `_blacksmith_github_set_milestone`, near line 674):

```bash
# Find-or-create a milestone by TITLE; echo its number. Idempotent: returns the
# existing milestone's number if present, else POSTs a new open milestone. Adopt
# re-emit uses this to materialize the Epoch (set_milestone only RESOLVES one).
#   create_milestone <title>
_blacksmith_github_create_milestone() {
  local title="$1" owner repo raw number
  [[ -n "$title" ]] || { _blacksmith_die "create_milestone: title required"; return 1; }
  owner=$(blacksmith_config_get '.github.owner') || return 1
  repo=$(blacksmith_config_get '.github.repo')   || return 1
  raw=$(gh api "repos/${owner}/${repo}/milestones?state=all&per_page=100" 2>/dev/null) \
    || { _blacksmith_die "create_milestone: cannot list milestones"; return 1; }
  number=$(printf '%s' "$raw" | jq -r --arg t "$title" 'map(select(.title==$t)) | .[0].number // empty')
  if [[ -z "$number" ]]; then
    raw=$(gh api "repos/${owner}/${repo}/milestones" -f title="$title" 2>/dev/null) \
      || { _blacksmith_die "create_milestone: create failed for '$title'"; return 1; }
    number=$(printf '%s' "$raw" | jq -er '.number') \
      || { _blacksmith_die "create_milestone: no number in create response"; return 1; }
  fi
  printf '%s' "$number"
}
```

And the Forgejo impl (next to `_blacksmith_forgejo_set_milestone`, near line 1005):

```bash
# Forgejo find-or-create milestone by TITLE; echo its id. Same idempotent contract.
_blacksmith_forgejo_create_milestone() {
  local title="$1" owner repo raw mid
  [[ -n "$title" ]] || { _blacksmith_die "create_milestone: title required"; return 1; }
  owner=$(blacksmith_config_get '.forgejo.owner') || return 1
  repo=$(blacksmith_config_get '.forgejo.repo')   || return 1
  raw=$(_blacksmith_forgejo_curl GET "/repos/${owner}/${repo}/milestones?state=all&limit=100") \
    || { _blacksmith_die "create_milestone (forgejo): cannot list milestones"; return 1; }
  mid=$(printf '%s' "$raw" | jq -r --arg t "$title" 'map(select(.title==$t)) | .[0].id // empty')
  if [[ -z "$mid" ]]; then
    raw=$(_blacksmith_forgejo_curl POST "/repos/${owner}/${repo}/milestones" \
          "$(jq -nc --arg t "$title" '{title:$t}')") \
      || { _blacksmith_die "create_milestone (forgejo): create failed for '$title'"; return 1; }
    mid=$(printf '%s' "$raw" | jq -er '.id') \
      || { _blacksmith_die "create_milestone (forgejo): no id in create response"; return 1; }
  fi
  printf '%s' "$mid"
}
```

(The public verb `blacksmith_create_milestone` was already added in Task 1.)

**Step 4: Run test to verify it passes**
Run: `bash tests/scripts/test_blacksmith_create_milestone.sh`
Expected: PASS.
Also Run: `bash tests/scripts/run-tests.sh`
Expected: exit 0 (the opt-in route leaves every existing test green).

**Step 5: Commit** — `feat(blacksmith): create_milestone find-or-create (both forges) (#62)`

---

## Task 4: `bin/adopt-reemit.sh` — Epoch milestone + Area umbrellas

**Files:**
- Create: `bin/adopt-reemit.sh`
- Create: `tests/scripts/fixtures/reconciled-plan.json`
- Create: `tests/scripts/fixtures/gh-milestones-adopt.json`
- Modify: `tests/scripts/lib/gh-shim.sh` (single-issue GET/PATCH route)
- Create: `tests/scripts/test_adopt_reemit.sh`

**Acceptance Criteria:**
- [ ] `adopt-reemit.sh <plan.json>` materializes the Epoch milestone via `blacksmith_create_milestone` (idempotent).
- [ ] Each `areas[]` entry becomes an umbrella issue created with labels `type/umbrella` + `area/<slug>` and the Epoch milestone set.
- [ ] The labels it attaches (`type/umbrella`, `area/<slug>`) are ensured to exist first.
- [ ] Missing/absent plan file exits non-zero with a clear message.

**Step 1: Write the failing test** — `tests/scripts/test_adopt_reemit.sh`

```bash
#!/usr/bin/env bash
# adopt-reemit.sh: re-emit a reconciled adopt plan into oskr board structure —
# 1 Epoch milestone, each phase an Area umbrella (type/umbrella + area/<slug>),
# each task a slim ## Parent/## What/## AC issue (delivery/manual) linked beneath.
# Proven hermetically via gh-shim replay (Task 4 = Epoch+umbrellas; Task 5 = tasks).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FIX="$REPO_ROOT/tests/scripts/fixtures"
source "$SCRIPT_DIR/lib/assert.sh"

SHIM_DIR=$(mktemp -d); CACHE_DIR=$(mktemp -d); trap 'rm -rf "$SHIM_DIR" "$CACHE_DIR"' EXIT
cp "$SCRIPT_DIR/lib/gh-shim.sh" "$SHIM_DIR/gh"; chmod +x "$SHIM_DIR/gh"
LOG="$SHIM_DIR/gh.log"; : > "$LOG"

PATH="$SHIM_DIR:$PATH" \
  HARNESS_CONFIG="$FIX/harness-config.sample.json" \
  GH_SHIM_CALL_LOG="$LOG" \
  GH_SHIM_FIXTURE="$FIX/gh-project-discovery.json" \
  GH_SHIM_CREATE_ISSUE_FIXTURE="$FIX/gh-create-issue.json" \
  GH_SHIM_MILESTONES_FIXTURE="$FIX/gh-milestones-adopt.json" \
  GH_SHIM_ISSUE_FIXTURE="$FIX/gh-issue-single.json" \
  XDG_CACHE_HOME="$CACHE_DIR" \
  "$REPO_ROOT/bin/adopt-reemit.sh" "$FIX/reconciled-plan.json"

# Epoch milestone resolved (found-path against gh-milestones-adopt.json -> number 1)
grep -qF 'milestones?state=all' "$LOG"          || { echo "FAIL: epoch milestone not resolved" >&2; exit 1; }
# Two Area umbrellas, each with type/umbrella + its area/<slug>
grep -qF 'title=[Area] Patient intake' "$LOG"   || { echo "FAIL: intake umbrella not created" >&2; exit 1; }
grep -qF 'title=[Area] Billing'        "$LOG"   || { echo "FAIL: billing umbrella not created" >&2; exit 1; }
grep -qF 'labels[]=type/umbrella'      "$LOG"   || { echo "FAIL: umbrella label missing" >&2; exit 1; }
grep -qF 'labels[]=area/intake'        "$LOG"   || { echo "FAIL: area/intake label missing" >&2; exit 1; }
grep -qF 'labels[]=area/billing'       "$LOG"   || { echo "FAIL: area/billing label missing" >&2; exit 1; }
# Umbrella milestone set to the Epoch (number 1)
grep -qE 'issues/42 .*milestone=1'     "$LOG"   || { echo "FAIL: umbrella milestone not set" >&2; exit 1; }
# Labels ensured before attachment
grep -qF 'label create type/umbrella'  "$LOG"   || { echo "FAIL: type/umbrella not ensured" >&2; exit 1; }
grep -qF 'label create area/intake'    "$LOG"   || { echo "FAIL: area/intake not ensured" >&2; exit 1; }

# Absent plan file fails clearly
if "$REPO_ROOT/bin/adopt-reemit.sh" /no/such/plan.json 2>/dev/null; then
  echo "FAIL: missing plan file must exit non-zero" >&2; exit 1
fi

echo "test_adopt_reemit (umbrellas): PASS"
```

And the fixtures — `tests/scripts/fixtures/gh-milestones-adopt.json`:

```json
[
  { "number": 1, "title": "coremyotherapy v1", "state": "open" }
]
```

`tests/scripts/fixtures/reconciled-plan.json`:

```json
{
  "epoch": "coremyotherapy v1",
  "areas": [
    {
      "slug": "intake",
      "title": "[Area] Patient intake",
      "what": "Patients self-register and get triaged.",
      "ac": "- [ ] Registration persists.\n- [ ] Triage assigns a tier.",
      "tasks": [
        { "title": "Registration form", "what": "Build the self-registration form.", "ac": "- [ ] Form submits and persists." },
        { "title": "Triage rules",       "what": "Encode triage tiering.",            "ac": "- [ ] Rules assign a tier." }
      ]
    },
    {
      "slug": "billing",
      "title": "[Area] Billing",
      "what": "Generate invoices from visits.",
      "ac": "- [ ] An invoice is emitted per visit.",
      "tasks": [
        { "title": "Invoice model", "what": "Model invoices.", "ac": "- [ ] Invoice row saved." }
      ]
    }
  ]
}
```

**Step 2: Run test to verify it fails**
Run: `bash tests/scripts/test_adopt_reemit.sh`
Expected: FAIL — `bin/adopt-reemit.sh` does not exist (non-zero).

**Step 3: Write minimal implementation**

First add the **opt-in single-issue gh-shim route** in `tests/scripts/lib/gh-shim.sh`, placed **after** the `dependencies/blocked_by` route and immediately **before** the final default `emit < "$GH_SHIM_FIXTURE"` line (the compound `.../sub_issues` path is already consumed earlier, so this only catches bare `GET/PATCH /issues/<n>`):

```bash
if [[ "$args" == *"/issues/"* && -n "${GH_SHIM_ISSUE_FIXTURE:-}" ]]; then   # GET/PATCH single issue (opt-in)
  emit < "$GH_SHIM_ISSUE_FIXTURE"; exit 0
fi
```

Then `bin/adopt-reemit.sh` (this task implements the Epoch + umbrella loop; Task 5 adds the inner task loop):

```bash
#!/usr/bin/env bash
# adopt-reemit.sh — full-migration adopt, step 3. Re-emit a reconciled plan into
# oskr board structure: one Epoch milestone, each phase an Area umbrella
# (type/umbrella + area/<slug>), each task a slim ## Parent/## What/## AC issue
# (delivery/manual) linked beneath its umbrella. Backend-neutral — every forge op
# goes through the blacksmith. The board lands "dispatch off": no issue is moved
# into an actionable column here.
# Usage: adopt-reemit.sh <reconciled-plan.json>
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/harness-lib.sh"

plan="${1:?usage: adopt-reemit.sh <reconciled-plan.json>}"
[[ -f "$plan" ]] || { echo "[adopt-reemit] plan file not found: $plan" >&2; exit 1; }

epoch=$(jq -er '.epoch' "$plan") || { echo "[adopt-reemit] plan has no .epoch" >&2; exit 1; }

# Ensure the structural labels adopt attaches exist before use (idempotent).
blacksmith_ensure_label "type/umbrella"   "Area umbrella"                      "5319e7"
blacksmith_ensure_label "delivery/manual" "Manual delivery (no auto-dispatch)" "c5def5"

# Materialize the Epoch milestone (idempotent find-or-create).
blacksmith_create_milestone "$epoch" >/dev/null

area_count=$(jq '.areas | length' "$plan")
for (( ai = 0; ai < area_count; ai++ )); do
  slug=$(jq -er ".areas[$ai].slug"  "$plan")
  atitle=$(jq -er ".areas[$ai].title" "$plan")
  awhat=$(jq -r  ".areas[$ai].what"  "$plan")
  aac=$(jq -r    ".areas[$ai].ac"    "$plan")

  blacksmith_ensure_label "area/${slug}" "Area: ${slug}" "0e8a16"
  abody=$(printf '## What\n\n%s\n\n## AC\n\n%s\n' "$awhat" "$aac")
  umbrella=$(blacksmith_create_issue "$atitle" "$abody" "type/umbrella,area/${slug}" | jq -er '.number') \
    || { echo "[adopt-reemit] failed to create umbrella for $slug" >&2; exit 1; }
  blacksmith_set_milestone "$umbrella" "$epoch"
done
```

Then make it executable: `chmod +x bin/adopt-reemit.sh`.

**Step 4: Run test to verify it passes**
Run: `bash tests/scripts/test_adopt_reemit.sh`
Expected: PASS — prints `test_adopt_reemit (umbrellas): PASS`.
Also Run: `bash tests/scripts/run-tests.sh`
Expected: exit 0 (opt-in `GH_SHIM_ISSUE_FIXTURE` route leaves existing tests green).

**Step 5: Commit** — `feat(adopt): adopt-reemit.sh — Epoch milestone + Area umbrellas (#62)`

---

## Task 5: `adopt-reemit.sh` — slim task issues, linked, delivery/manual, dispatch off

**Files:**
- Modify: `bin/adopt-reemit.sh`
- Modify: `tests/scripts/test_adopt_reemit.sh`

**Acceptance Criteria:**
- [ ] Each `areas[].tasks[]` entry becomes an issue with body `## Parent\n#<umbrella>` + `## What` + `## AC` and label `delivery/manual` + `area/<slug>`.
- [ ] Task bodies carry **no** `touches:` and no TDD-shaped ACs.
- [ ] Each task is linked beneath its Area umbrella (native sub-issue) and gets the Epoch milestone.
- [ ] Re-emit performs **no** Status move (no `updateProjectV2ItemFieldValue`) — the "dispatch off" landing.

**Step 1: Write the failing test** — append to `tests/scripts/test_adopt_reemit.sh` (before the final `echo`)

```bash
# ---- Task arm: slim issues, linked beneath umbrellas, delivery/manual, no move ----
grep -qF 'title=Registration form' "$LOG" || { echo "FAIL: task 'Registration form' not created" >&2; exit 1; }
grep -qF 'title=Triage rules'       "$LOG" || { echo "FAIL: task 'Triage rules' not created" >&2; exit 1; }
grep -qF 'title=Invoice model'      "$LOG" || { echo "FAIL: task 'Invoice model' not created" >&2; exit 1; }
grep -qF 'labels[]=delivery/manual' "$LOG" || { echo "FAIL: task missing delivery/manual" >&2; exit 1; }
grep -qF 'label create delivery/manual' "$LOG" || { echo "FAIL: delivery/manual not ensured" >&2; exit 1; }
# Slim body contract
grep -qF '## Parent' "$LOG" || { echo "FAIL: task body missing ## Parent" >&2; exit 1; }
grep -qF '## What'   "$LOG" || { echo "FAIL: task body missing ## What" >&2; exit 1; }
grep -qF '## AC'     "$LOG" || { echo "FAIL: task body missing ## AC" >&2; exit 1; }
if grep -qF 'touches:' "$LOG"; then echo "FAIL: re-emitted task carries forbidden touches:" >&2; exit 1; fi
# Linked beneath the umbrella (native sub-issue; child DB id 9001 from gh-issue-single.json)
grep -qF 'sub_issues'       "$LOG" || { echo "FAIL: tasks not linked under umbrellas" >&2; exit 1; }
grep -qF 'sub_issue_id=9001' "$LOG" || { echo "FAIL: link did not use child DB id" >&2; exit 1; }
# Dispatch off: NO Status move into an actionable column
if grep -qF 'updateProjectV2ItemFieldValue' "$LOG"; then echo "FAIL: re-emit moved an issue (dispatch must be off)" >&2; exit 1; fi
```

**Step 2: Run test to verify it fails**
Run: `bash tests/scripts/test_adopt_reemit.sh`
Expected: FAIL — no task creates in the log (the inner loop does not exist yet).

**Step 3: Write minimal implementation** — add the inner task loop inside the `for (( ai ... ))` body in `bin/adopt-reemit.sh`, **after** `blacksmith_set_milestone "$umbrella" "$epoch"`:

```bash
  task_count=$(jq ".areas[$ai].tasks | length" "$plan")
  for (( ti = 0; ti < task_count; ti++ )); do
    ttitle=$(jq -er ".areas[$ai].tasks[$ti].title" "$plan")
    twhat=$(jq -r  ".areas[$ai].tasks[$ti].what"  "$plan")
    tac=$(jq -r    ".areas[$ai].tasks[$ti].ac"    "$plan")
    # Slim body: ## Parent / ## What / ## AC only — no touches:, no TDD-ACs.
    tbody=$(printf '## Parent\n#%s\n\n## What\n\n%s\n\n## AC\n\n%s\n' "$umbrella" "$twhat" "$tac")
    child=$(blacksmith_create_issue "$ttitle" "$tbody" "delivery/manual,area/${slug}" | jq -er '.number') \
      || { echo "[adopt-reemit] failed to create task '$ttitle'" >&2; exit 1; }
    blacksmith_set_milestone "$child" "$epoch"
    blacksmith_link_parent "$umbrella" "$child"
  done
```

(No move/dispatch call is added — issues land un-columned, which is the "dispatch off" landing the test asserts.)

**Step 4: Run test to verify it passes**
Run: `bash tests/scripts/test_adopt_reemit.sh`
Expected: PASS — prints both `test_adopt_reemit (umbrellas): PASS` and the file completes (task arm assertions green).
Also Run: `bash tests/scripts/test_backend_no_inline_gh.sh`
Expected: exit 0.

**Step 5: Commit** — `feat(adopt): adopt-reemit.sh — slim linked tasks, delivery/manual, dispatch off (#62)`

---

## Task 6: `docs/adopt-reintake.md` — the reconcile guided checklist  *(HARNESS/PROSE TASK)*

**TDD substitution (deliberate, per agent definition):** this deliverable is prose, not executable code. Verification is **write-AC → grep/structural check → implement**, not a RED unit test. The whole point of the AC is that reconcile is the **manual** step — so the verification asserts both that the checklist exists AND that no automated reconcile test exists.

**Files:**
- Create: `docs/adopt-reintake.md`

**Acceptance Criteria (each a runnable check from repo root):**
- [ ] AC6.1 the doc is labeled a guided checklist: `grep -qiF 'guided checklist' docs/adopt-reintake.md`
- [ ] AC6.2 it walks the full pipeline order: `grep -qiF 'harvest' docs/adopt-reintake.md && grep -qiF 'reconcile' docs/adopt-reintake.md && grep -qiF 're-emit' docs/adopt-reintake.md`
- [ ] AC6.3 it names both bin verbs: `grep -qF 'adopt-harvest.sh' docs/adopt-reintake.md && grep -qF 'adopt-reemit.sh' docs/adopt-reintake.md`
- [ ] AC6.4 it documents the reconciled-plan input shape: `grep -qF 'reconciled-plan.json' docs/adopt-reintake.md && grep -qF '"epoch"' docs/adopt-reintake.md`
- [ ] AC6.5 reconcile is explicitly manual / not automated: `grep -qiE 'not an automated test|by hand|manual' docs/adopt-reintake.md`
- [ ] AC6.6 no automated reconcile test is shipped: `! test -f tests/scripts/test_adopt_reconcile.sh`

**Step 1: Write the acceptance criteria** — the six checks above (the contract; no RED unit test for prose).

**Step 2: Verify they fail**
Run: `grep -qiF 'guided checklist' docs/adopt-reintake.md`
Expected: FAIL — file does not exist (non-zero).

**Step 3: Implement** — `docs/adopt-reintake.md` (complete content):

```markdown
# Adopt — full re-intake (harvest → reconcile → re-emit)

The heavy adopt path for a **brownfield** project: take a repo with an off-board
backlog and re-shape it into oskr board structure — one Epoch milestone, phases as
Area umbrellas, slim task issues linked beneath. Use it when `init` adopt detects
existing issues/a board and you choose **full migration** over register-only.

The middle step — **reconcile** — is a **guided checklist done by hand**, not an
automated test. A lot of "what is actually true now" lives only in your head; the
tooling harvests and re-emits, but you decide the shape.

## Step 1 — Harvest (scripted)

Read every existing issue into a reconciliation tasklist:

    adopt-harvest.sh harvest.md

`harvest.md` lists `- [ ] #<n> <title> (<state>)` for each issue (pull requests
excluded). It is your raw material, not the final plan.

## Step 2 — Reconcile (manual — by hand, not an automated test)

Work through `harvest.md` and decide current state. There is no script for this; it
is the developer's judgment call. Produce a `reconciled-plan.json`:

    {
      "epoch": "<project> v1",
      "areas": [
        {
          "slug": "intake",
          "title": "[Area] Patient intake",
          "what": "<end-to-end behavior>",
          "ac": "- [ ] ...",
          "tasks": [
            { "title": "...", "what": "...", "ac": "- [ ] ..." }
          ]
        }
      ]
    }

Reconcile checklist:
- [ ] Collapse each project phase into one Area (`slug` + `[Area] <title>`).
- [ ] Drop dead/won't-do issues; merge duplicates.
- [ ] For each surviving issue, write a slim `## What` + `## AC` (no file paths,
      no TDD-shaped ACs — the per-task plan owns those later).
- [ ] Name the Epoch (the single milestone all Areas share).

## Step 3 — Re-emit (scripted)

Feed the reconciled plan back:

    adopt-reemit.sh reconciled-plan.json

This creates the Epoch milestone, one `type/umbrella` + `area/<slug>` umbrella per
Area, and one `delivery/manual` task per task — each carrying a slim
`## Parent` / `## What` / `## AC` body and linked beneath its umbrella. The board
lands **dispatch off**: nothing is moved into an actionable column, so you review
before any work starts.

> The live coremyotherapy migration is Area 5; this slice builds and fixture-proves
> the capability only.
```

**Step 4: Verify all ACs pass**
Run: `bash -c ' grep -qiF "guided checklist" docs/adopt-reintake.md && grep -qiF "harvest" docs/adopt-reintake.md && grep -qiF "reconcile" docs/adopt-reintake.md && grep -qiF "re-emit" docs/adopt-reintake.md && grep -qF "adopt-harvest.sh" docs/adopt-reintake.md && grep -qF "adopt-reemit.sh" docs/adopt-reintake.md && grep -qF "reconciled-plan.json" docs/adopt-reintake.md && grep -qF "\"epoch\"" docs/adopt-reintake.md && grep -qiE "not an automated test|by hand|manual" docs/adopt-reintake.md && ! test -f tests/scripts/test_adopt_reconcile.sh && echo ALL_AC_PASS'`
Expected: prints `ALL_AC_PASS` (exit 0).

**Step 5: Commit** — `docs(adopt): full re-intake reconcile guided checklist (#62)`

---

## Task 7: Wire the full-migration arm into `init` adopt  *(HARNESS/PROSE TASK)*

**TDD substitution (deliberate, per agent definition):** `skills/init/SKILL.md` is agent-instruction prose. Verification is grep/structural over the skill body. **Cross-task dependency:** the adopt **consent gate** (full-migration vs register-only) is built by **T6**; this task adds the full-migration *arm* the gate routes into. If T6's gate is already present at execution time, attach to it; if not yet merged, add a minimal "Adopt — full migration" subsection that the gate will point at (do not re-implement the consent prompt — that is T6's).

**Files:**
- Modify: `skills/init/SKILL.md`

**Acceptance Criteria (each a runnable check from repo root):**
- [ ] AC7.1 the skill references the harvest verb: `grep -qF 'adopt-harvest.sh' skills/init/SKILL.md`
- [ ] AC7.2 the skill references the re-emit verb: `grep -qF 'adopt-reemit.sh' skills/init/SKILL.md`
- [ ] AC7.3 the skill points at the reconcile checklist doc: `grep -qF 'docs/adopt-reintake.md' skills/init/SKILL.md`
- [ ] AC7.4 the full-migration arm states reconcile is the manual middle step: `grep -qiE 'reconcile.*(by hand|manual|guided)' skills/init/SKILL.md`
- [ ] AC7.5 the three steps are named in order: `grep -qiF 'harvest' skills/init/SKILL.md && grep -qiF 're-emit' skills/init/SKILL.md`

**Step 1: Write the acceptance criteria** — the five greps above.

**Step 2: Verify they fail**
Run: `grep -qF 'adopt-harvest.sh' skills/init/SKILL.md`
Expected: FAIL (non-zero) — the arm is not wired yet.

**Step 3: Implement** — add an "Adopt — full migration" subsection to `skills/init/SKILL.md` (under the adopt consent gate T6 establishes; if absent, add it as a standalone subsection). Suggested content:

```markdown
### Adopt — full migration (harvest → reconcile → re-emit)

When the developer chooses **full migration** at the adopt consent gate (a brownfield
project with an off-board backlog), run the three-step re-intake. Reconcile is a
**manual, by-hand guided** step — see `docs/adopt-reintake.md`.

1. **Harvest** (scripted): `adopt-harvest.sh harvest.md` — reads every existing issue
   into a reconciliation tasklist (pull requests excluded).
2. **Reconcile** (manual): walk `harvest.md` with the developer per the guided
   checklist in `docs/adopt-reintake.md`; produce `reconciled-plan.json`
   (`epoch` + `areas[]` with slim `what`/`ac` and `tasks[]`).
3. **Re-emit** (scripted): `adopt-reemit.sh reconciled-plan.json` — creates the Epoch
   milestone, one `type/umbrella` + `area/<slug>` umbrella per Area, and one
   `delivery/manual` task per task (slim `## Parent`/`## What`/`## AC`), linked beneath
   its umbrella. The board lands **dispatch off** — review before any work starts.

For a project that already runs its own board/workflow, prefer the **register-only**
arm of the consent gate instead. The live coremyotherapy migration is Area 5.
```

**Step 4: Verify all ACs pass**
Run: `bash -c ' grep -qF "adopt-harvest.sh" skills/init/SKILL.md && grep -qF "adopt-reemit.sh" skills/init/SKILL.md && grep -qF "docs/adopt-reintake.md" skills/init/SKILL.md && grep -qiE "reconcile.*(by hand|manual|guided)" skills/init/SKILL.md && grep -qiF "harvest" skills/init/SKILL.md && grep -qiF "re-emit" skills/init/SKILL.md && echo ALL_AC_PASS'`
Expected: prints `ALL_AC_PASS` (exit 0).

**Step 5: Commit** — `feat(init): wire adopt full-migration arm to harvest/re-emit verbs (#62)`

---

## Task 8: Version bump + full-suite regression

**Files:**
- Modify: `.claude-plugin/plugin.json`

**Acceptance Criteria:**
- [ ] AC8.1 `plugin.json` `version` differs from the `main` baseline `0.3.5` and is valid semver (new bin verbs + adopt capability = a feature → minor `0.4.0`).
- [ ] AC8.2 the whole hermetic suite is green, including all four new tests and the untouched `test_harness_config.sh` precedence regression.

**Step 1: Write the checks (no RED unit test — config edit).**

**Step 2: Verify the suite is the gate**
Run: `bash tests/scripts/run-tests.sh`
Expected: PASS already at this point (Tasks 1–7 each kept it green) — this task only bumps the version.

**Step 3: Implement** — bump `.claude-plugin/plugin.json` `version` from `0.3.5` to `0.4.0`. If a sibling child PR on the Area branch already moved the version, bump to the next free value above the current instead — AC8.1 only requires "differs from `0.3.5` + valid semver", so collisions are non-fatal.

**Step 4: Verify**
Run: `bash -c ' V=$(jq -r .version .claude-plugin/plugin.json) && [ "$V" != "0.3.5" ] && printf "%s" "$V" | grep -qE "^[0-9]+\.[0-9]+\.[0-9]+$" && echo VERSION_OK'`
Expected: prints `VERSION_OK`.
Run: `bash tests/scripts/run-tests.sh`
Expected: exit 0 — `Results: N/N passed, 0 failed`, including `test_blacksmith_list_issues`, `test_blacksmith_create_milestone`, `test_adopt_harvest`, `test_adopt_reemit`, and an untouched `test_harness_config: PASS`.

**Step 5: Commit** — `chore: bump version 0.3.5 -> 0.4.0 for adopt full re-intake (#62)`

---

## Dependencies

- **Cross-task (Area #27 DAG):** T7/#62 is **blocked-by T6** (adopt consent gate + register-only path). Task 7 attaches the full-migration arm to the consent gate T6 builds in `skills/init/SKILL.md`; T6 also owns the **project-config-level** "dispatch off" (`delivery: manual` default + loop disabled). T7's "dispatch off" is the **issue-level** half only (per-task `delivery/manual` label + no Status move). If T6 is not yet merged at execution, add the full-migration subsection standalone and do **not** re-implement the consent prompt.
- **Shared files (merge hazards):**
  - `bin/harness-lib.sh` — Tasks 1 & 3 add verbs; other #27 children (T1 config resolver) also touch this file. Add new functions at the section boundaries indicated; do not reorder existing functions.
  - `tests/scripts/lib/gh-shim.sh` — Tasks 3 & 4 add two **opt-in** routes (guarded by `GH_SHIM_CREATE_MILESTONE_FIXTURE` / `GH_SHIM_ISSUE_FIXTURE`, both unset in every existing test), so the additions are non-breaking; place them exactly where each task specifies relative to the existing route order.
  - `skills/init/SKILL.md` — also edited by T6; Task 7 adds a new subsection only.
  - `.claude-plugin/plugin.json` `version` — bumped by every sibling child PR; AC8.1 is collision-tolerant.
- **Reuses (no change needed):** `blacksmith_create_issue`, `blacksmith_set_milestone`, `blacksmith_link_parent`, `blacksmith_ensure_label` — landed (#26). Re-emit composes them; the only new write verb is `blacksmith_create_milestone`.
- **No live forge:** every behavior is gh-shim/curl-shim replayed. Live Forgejo provisioning and the live coremyotherapy migration run stay **Area 5** — not a #27 acceptance criterion.
```