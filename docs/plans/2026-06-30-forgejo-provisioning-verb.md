# Forgejo board-provisioning verb (behind the seam) — Implementation Plan

**Goal:** Give `forge: forgejo` projects working board provisioning — a `blacksmith_provision_board` verb that creates the 8 status columns + priority/size/category taxonomy as **exclusive** scoped labels and asserts the per-repo issue-dependencies unit — proven hermetically via curl-shim replay, with live acceptance deferred to Area 5.
**Architecture:** All new code lives inside `bin/harness-lib.sh` (the blacksmith), so the seam guard's "no inline `curl` outside the adapter" invariant holds for free. A new public one-line dispatcher `blacksmith_provision_board` routes to `_blacksmith_forgejo_provision_board`, which (1) asserts the deps unit via a `GET /repos/{owner}/{repo}` read of `internal_tracker.enable_issue_dependencies` and fails loudly if off, then (2) idempotently POSTs each scoped label with `exclusive:true` via a new `_blacksmith_forgejo_ensure_exclusive_label` helper. The hermetic test drives the verb through the public seam against the `lib/curl-shim.sh` PATH-boundary replay (extended with a repo-GET route + two repo fixtures).
**Tech Stack:** Bash (`bin/` shell layer), `jq`, `curl` (shimmed in test), the `tests/scripts/` subshell + `lib/curl-shim.sh` replay harness (`run-tests.sh`, `lib/assert.sh`).
**Issue:** #58 (child of Area #27; PRD Task **T8** — "Forgejo provisioning code behind the seam; curl-shim unit; live → Area 5")

---

## Definition of Done

This plan satisfies the frozen Plan DoD:

1. **Deliverables:**
   - Modify `bin/harness-lib.sh` — add `blacksmith_provision_board` dispatcher + `_blacksmith_forgejo_provision_board` + `_blacksmith_forgejo_assert_deps_unit` + `_blacksmith_forgejo_ensure_exclusive_label` (all inside the blacksmith adapter).
   - Modify `tests/scripts/lib/curl-shim.sh` — add a `CURL_SHIM_REPO_FIXTURE`-gated route for the bare `GET /repos/{owner}/{repo}` call (the deps-unit read).
   - Create `tests/scripts/fixtures/forgejo-repo-deps-on.json` + `tests/scripts/fixtures/forgejo-repo-deps-off.json` — repo objects with `internal_tracker.enable_issue_dependencies` true/false.
   - Create `tests/scripts/test_blacksmith_forgejo_provision.sh` — hermetic curl-shim test of the verb (label creation + deps assertion).
   - Modify `bin/smoke/forgejo-roundtrip.sh` — wire the verb into its live home + mark live acceptance as the Area-5 gate (no CI run in #27).
   - Modify `.claude-plugin/plugin.json` — version bump (every PR bumps; new blacksmith verb ⇒ minor `0.3.5 → 0.4.0`).
2. **Testing tier:** **unit/hermetic — curl-shim PATH-boundary replay.** Justification: provisioning is a forge-touching verb, so per the umbrella's Named Seam it is proven by `lib/curl-shim.sh` replay (not subshell-pure), asserting the exact REST shape (`exclusive:true` label POSTs + the deps-unit GET) at the public verb boundary. Live Forgejo acceptance is **out of scope** (Area 5's `bin/smoke/forgejo-roundtrip.sh` gate). Prior art: `tests/scripts/test_blacksmith_forgejo_ops.sh` and `tests/scripts/test_blacksmith_add_dep.sh` (curl-shim call-log assertion style).
3. **Task granularity:** 4 tasks, each ≤ ~5 min of implementer work.
4. **Verification:** every acceptance criterion below has a runnable command (see AC → Verification map). No prose-only ACs.
5. **Dependencies:** declared in "Cross-task dependencies." Internal ordering is strictly sequential T1→T2→T3→T4; cross-issue, this slice has **no code dependency** on the Area's T1 (workspace resolver) — see that section.
6. **Seam fidelity:** all forge calls stay inside `bin/harness-lib.sh`; the existing seam guard `test_backend_no_inline_gh.sh` is the structural proof and is run in T4. The neutral `_blacksmith_forgejo_ensure_label` (non-exclusive) is left **unchanged** — exclusivity is a new, provisioning-only helper, so no existing caller's behavior moves.

### Harness-infrastructure TDD substitution (declared)

- **Tasks 2 & 3** are genuine shell logic and follow the full **5-step TDD pattern (RED test first)** against `tests/scripts/test_blacksmith_forgejo_provision.sh`.
- **Task 1 (test-harness infra)** edits the curl-shim and adds JSON fixtures — this is *test code*, not product code. Per the agent contract, TDD is substituted with **"write acceptance criterion → grep/structural check → implement"**: a `grep` for the new route token + a `jq` validity check on the fixtures + a no-regression `run-tests.sh`. The substitution is deliberate and noted so plan-reviewer does not flag a missing RED test; the real RED/GREEN coverage is Tasks 2 & 3, which consume this infra.
- **Task 4** wires the verb into the opt-in live smoke (prose comment + one verb call), bumps the version, and runs the suite/guard — verified by `grep` + `jq` + `run-tests.sh`/guard exit codes.

### Playwright tier — exemption (justified)

This issue touches **no** UI components, navigation, auth, or browser-observable behavior. The only observable surface is **forge REST traffic from a `bin/` shell verb**, asserted by capturing the curl-shim call log and `grep`-ing it. There is no web surface to drive, so the Playwright AC class does not apply. **Exempt.** (The Q&A for this Area declared no Playwright-scope block; this slice is backend-only, so there is no UI gap to surface.)

### Design/quality-rule ACs

The project declares no `.claude/rules/` directory (verified: `Glob .claude/rules/**` → no files). The design/quality-rule AC requirement is a **no-op** for this plan.

---

## AC → Verification map

The task's four acceptance criteria (#58) map to runnable commands. All paths are relative to the repo root `.`; run commands from there (or `cd` first).

| # | Acceptance criterion (#58) | Verification command | Expected | Task |
|---|---|---|---|---|
| 1 | A Forgejo provisioning verb creates the 8 status columns as exclusive scoped labels (`exclusive:true`), plus the priority / size / category scoped labels | `bash tests/scripts/test_blacksmith_forgejo_provision.sh` (label-creation block) | exit 0 | T1, T3 |
| 2 | Provisioning asserts the per-repo issue-dependencies unit is enabled and fails loudly if it is not | `bash tests/scripts/test_blacksmith_forgejo_provision.sh` (deps-off block) | exit 0 | T1, T2 |
| 3 | The verb lives behind the board-ops seam (no inline curl outside the adapter) | `bash tests/scripts/test_backend_no_inline_gh.sh` | exit 0 | T2, T4 |
| 4 | Curl-shim tests cover label creation (exclusive flag present) and the deps-unit assertion; live acceptance is explicitly deferred to Area 5 | `bash tests/scripts/test_blacksmith_forgejo_provision.sh && grep -qF 'blacksmith_provision_board' bin/smoke/forgejo-roundtrip.sh && grep -qiF 'Area 5' bin/smoke/forgejo-roundtrip.sh` | exit 0 | T1–T4 |
| — | Whole suite stays green | `bash tests/scripts/run-tests.sh` | exit 0 | T4 |
| — | Version bumped | `[[ "$(jq -r .version .claude-plugin/plugin.json)" == 0.4.0 ]]` | exit 0 | T4 |

---

## Task 1: Extend the curl-shim with a repo-GET route + repo deps-unit fixtures

**Harness-infrastructure substitution:** this is *test code* — TDD is replaced by **write AC → grep/structural check → implement** (declared in the DoD). The route is gated on a new env var, so existing tests (which never set it) are byte-for-byte unaffected — a no-op regression-wise.

**Files:**
- Modify: `tests/scripts/lib/curl-shim.sh`
- Create: `tests/scripts/fixtures/forgejo-repo-deps-on.json`
- Create: `tests/scripts/fixtures/forgejo-repo-deps-off.json`

**Acceptance Criteria (grep / structural):**
- [ ] `grep -qF 'CURL_SHIM_REPO_FIXTURE' tests/scripts/lib/curl-shim.sh` → exit 0
- [ ] `jq -e '.internal_tracker.enable_issue_dependencies == true' tests/scripts/fixtures/forgejo-repo-deps-on.json` → exit 0
- [ ] `jq -e '.internal_tracker.enable_issue_dependencies == false' tests/scripts/fixtures/forgejo-repo-deps-off.json` → exit 0
- [ ] `bash tests/scripts/run-tests.sh` still exits 0 (no regression — the route is env-gated)

**Step 1: Write the acceptance criterion (the checks)**
Run: `grep -qF 'CURL_SHIM_REPO_FIXTURE' tests/scripts/lib/curl-shim.sh && jq -e '.internal_tracker.enable_issue_dependencies == true' tests/scripts/fixtures/forgejo-repo-deps-on.json && jq -e '.internal_tracker.enable_issue_dependencies == false' tests/scripts/fixtures/forgejo-repo-deps-off.json`
Expected (before implementing): FAIL (exit non-zero) — neither the route token nor the fixture files exist yet.

**Step 2: Implement — extend the shim.** In `tests/scripts/lib/curl-shim.sh`, insert this route **immediately before** the final `echo "curl-shim: no route for: $args" >&2` line:

```bash
if [[ -n "${CURL_SHIM_REPO_FIXTURE:-}" && "$args" == */repos/* ]]; then   # GET repo object (deps-unit assertion)
  cat "$CURL_SHIM_REPO_FIXTURE"; exit 0
fi
```

> Placement rationale: every `/repos/{owner}/{repo}/<subpath>` route (labels, issues, milestones, dependencies) is matched **earlier** and returns, so by the time control reaches this branch the only remaining `*/repos/*` call is the bare repo GET. The branch is gated on `CURL_SHIM_REPO_FIXTURE`, so any test that does not set it is unchanged (falls through to the existing `exit 22`). No existing test makes a bare repo GET, so the suite is unaffected.

Also update the shim's header "Fixture routing" comment to list the new route (one line, keeps the file self-documenting):

```bash
#   .../repos/{o}/{r}  + $CURL_SHIM_REPO_FIXTURE -> that fixture (repo object; deps-unit read)
```

**Step 3: Implement — create the fixtures.**

`tests/scripts/fixtures/forgejo-repo-deps-on.json`:

```json
{
  "name": "sluice",
  "full_name": "squirrlylabs/sluice",
  "has_issues": true,
  "internal_tracker": {
    "enable_time_tracker": true,
    "allow_only_contributors_to_track_time": false,
    "enable_issue_dependencies": true
  }
}
```

`tests/scripts/fixtures/forgejo-repo-deps-off.json`:

```json
{
  "name": "sluice",
  "full_name": "squirrlylabs/sluice",
  "has_issues": true,
  "internal_tracker": {
    "enable_time_tracker": true,
    "allow_only_contributors_to_track_time": false,
    "enable_issue_dependencies": false
  }
}
```

**Step 4: Run the acceptance criterion to verify it passes**
Run: `grep -qF 'CURL_SHIM_REPO_FIXTURE' tests/scripts/lib/curl-shim.sh && jq -e '.internal_tracker.enable_issue_dependencies == true' tests/scripts/fixtures/forgejo-repo-deps-on.json && jq -e '.internal_tracker.enable_issue_dependencies == false' tests/scripts/fixtures/forgejo-repo-deps-off.json && bash tests/scripts/run-tests.sh`
Expected: PASS (exit 0) — checks pass and `run-tests.sh` prints `Results: N/N passed, 0 failed`.

**Step 5: Commit** — `git add tests/scripts/lib/curl-shim.sh tests/scripts/fixtures/forgejo-repo-deps-on.json tests/scripts/fixtures/forgejo-repo-deps-off.json && git commit -m "test(forgejo): curl-shim repo-GET route + deps-unit fixtures (#58)"`

---

## Task 2: `blacksmith_provision_board` dispatcher + deps-unit assertion gate

**Files:**
- Modify: `bin/harness-lib.sh` (add public dispatcher + Forgejo gate impl)
- Create (test): `tests/scripts/test_blacksmith_forgejo_provision.sh`

**Acceptance Criteria:**
- [ ] `blacksmith_provision_board` exists as a public one-line dispatcher (verb behind the seam).
- [ ] With the deps unit **enabled** (`forgejo-repo-deps-on.json`), `blacksmith_provision_board` exits 0.
- [ ] With the deps unit **disabled** (`forgejo-repo-deps-off.json`), it exits non-zero **and** writes a loud `issue-dependencies` error to stderr, **before** creating any label.
- [ ] `tests/scripts/test_blacksmith_forgejo_provision.sh` passes (deps blocks).

**Step 1: Write the failing test** — create `tests/scripts/test_blacksmith_forgejo_provision.sh`:

```bash
#!/usr/bin/env bash
# Forgejo board provisioning (#27 / #58) — hermetic, via curl-shim. provision_board
# asserts the per-repo issue-dependencies unit, then creates the 8 status columns +
# the priority/size/category taxonomy as EXCLUSIVE scoped labels. Live acceptance is
# Area 5 (bin/smoke/forgejo-roundtrip.sh); here we prove the REST shape only.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB="$REPO_ROOT/bin/harness-lib.sh"
FCFG="$REPO_ROOT/tests/scripts/fixtures/harness-config.forgejo.json"
FIX="$REPO_ROOT/tests/scripts/fixtures"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"

SHIM_DIR=$(mktemp -d); trap 'rm -rf "$SHIM_DIR"' EXIT
cp "$SCRIPT_DIR/lib/curl-shim.sh" "$SHIM_DIR/curl"; chmod +x "$SHIM_DIR/curl"
# $1 = call log, $2 = repo fixture (deps on/off), $3 = verb expression
run() { PATH="$SHIM_DIR:$PATH" HARNESS_CONFIG="$FCFG" FORGEJO_TOKEN="test-token" \
        CURL_SHIM_CALL_LOG="$1" CURL_SHIM_REPO_FIXTURE="$2" \
        bash -c "source '$LIB'; ${3}"; }

# --- deps unit ENABLED: provision succeeds -------------------------------------
L1="$SHIM_DIR/ok.log"; : > "$L1"
run "$L1" "$FIX/forgejo-repo-deps-on.json" "blacksmith_provision_board" \
  || { echo "FAIL: provision_board returned nonzero with the deps unit enabled" >&2; exit 1; }

# --- deps unit DISABLED: provision FAILS LOUDLY before touching labels ----------
L2="$SHIM_DIR/off.log"; : > "$L2"
if run "$L2" "$FIX/forgejo-repo-deps-off.json" "blacksmith_provision_board" 2>"$SHIM_DIR/off.err"; then
  echo "FAIL: provision_board succeeded with the deps unit DISABLED" >&2; exit 1
fi
grep -qiF 'issue-dependencies' "$SHIM_DIR/off.err" \
  || { echo "FAIL: no loud issue-dependencies error on stderr" >&2; cat "$SHIM_DIR/off.err" >&2; exit 1; }
if grep -qF '/labels' "$L2"; then
  echo "FAIL: labels created despite a disabled deps unit (gate must run first)" >&2; exit 1
fi

echo "test_blacksmith_forgejo_provision: PASS"
```

**Step 2: Run test to verify it fails**
Run: `bash tests/scripts/test_blacksmith_forgejo_provision.sh`
Expected: FAIL — `blacksmith_provision_board` is undefined, so `_blacksmith_dispatch` dies with "forge 'forgejo' has no implementation for 'provision_board'"; the deps-on `run` returns non-zero and the test exits 1 at "returned nonzero with the deps unit enabled".

**Step 3: Write minimal implementation.**

(a) In `bin/harness-lib.sh`, add the public dispatcher in the "public forge ops" block — **immediately after** the `blacksmith_base_branch()  { _blacksmith_dispatch base_branch "$@"; }` line:

```bash
blacksmith_provision_board()   { _blacksmith_dispatch provision_board "$@"; }
```

(b) In the **FORGEJO BACKEND** section, **immediately after** the `_blacksmith_forgejo_ensure_label()` function's closing brace, add the gate helper + the verb (label loop added in Task 3):

```bash
# Assert the per-repo issue-dependencies unit is enabled. If it is off, Forgejo's
# /dependencies endpoints 404 and read_deps/add_dep silently degrade — so this is a
# LOUD gate at provisioning time, not a silent skip. Reads internal_tracker off the
# repo object. See docs/research/2026-06-27-backend-capability.md:41,124.
#   _blacksmith_forgejo_assert_deps_unit <owner> <repo>
_blacksmith_forgejo_assert_deps_unit() {
  local owner="$1" repo="$2" raw enabled
  raw=$(_blacksmith_forgejo_curl GET "/repos/${owner}/${repo}") \
    || { _blacksmith_die "provision_board: cannot read repo ${owner}/${repo} to verify the issue-dependencies unit"; return 1; }
  enabled=$(printf '%s' "$raw" | jq -r '.internal_tracker.enable_issue_dependencies // false')
  [[ "$enabled" == "true" ]] \
    || { _blacksmith_die "provision_board: issue-dependencies unit is DISABLED on ${owner}/${repo}; enable it (repo Settings -> Units) before onboarding"; return 1; }
}

# Provision a Forgejo repo's board behind the seam: assert the issue-dependencies
# unit, then create the 8 status columns + priority/size/category taxonomy as
# EXCLUSIVE scoped labels. Idempotent on labels; fails LOUDLY if the deps unit is off.
# Live acceptance is Area 5's gate (bin/smoke/forgejo-roundtrip.sh); curl-shim-proven here.
#   provision_board
_blacksmith_forgejo_provision_board() {
  local owner repo
  owner=$(blacksmith_config_get '.forgejo.owner') || return 1
  repo=$(blacksmith_config_get '.forgejo.repo')   || return 1
  _blacksmith_forgejo_assert_deps_unit "$owner" "$repo" || return 1
}
```

**Step 4: Run test to verify it passes**
Run: `bash tests/scripts/test_blacksmith_forgejo_provision.sh`
Expected: PASS — prints `test_blacksmith_forgejo_provision: PASS`. (Deps-on returns 0; deps-off dies loudly with the `issue-dependencies` message before any `/labels` POST.)

**Step 5: Commit** — `git add bin/harness-lib.sh tests/scripts/test_blacksmith_forgejo_provision.sh && git commit -m "feat(forgejo): provision_board dispatcher + deps-unit assertion gate (#58)"`

---

## Task 3: Create the 8 status columns + taxonomy as exclusive scoped labels

**Files:**
- Modify: `bin/harness-lib.sh` (add the exclusive-label helper + label loop)
- Modify (test): `tests/scripts/test_blacksmith_forgejo_provision.sh` (extend the deps-on block)

**Acceptance Criteria:**
- [ ] On the deps-enabled path, every label is POSTed with `"exclusive":true`.
- [ ] All 8 status columns are provisioned: `status/{backlog,scoping,planning,plan_approval,ready,in_progress,in_review,done}`.
- [ ] The priority (`p1..p3`), size (`xs,s,m,l,xl`), and category (`feature,bug,chore,spike,docs`) scoped labels are provisioned.
- [ ] The retired 9-col slugs `status/research` and `status/needs_input` are **not** provisioned (the board is the reshaped 8).
- [ ] `tests/scripts/test_blacksmith_forgejo_provision.sh` passes (label + deps blocks).

**Step 1: Write the failing test** — in `tests/scripts/test_blacksmith_forgejo_provision.sh`, insert these assertions **immediately after** the deps-ENABLED `run "$L1" ...` line (i.e. before the `# --- deps unit DISABLED` comment):

```bash
# every label POST carries exclusive:true (single-select / server-enforced eviction).
grep -qF '"exclusive":true' "$L1" \
  || { echo "FAIL: labels not created with exclusive:true" >&2; exit 1; }
# all 8 reshaped status columns are provisioned (the 8-col scheme).
for s in backlog scoping planning plan_approval ready in_progress in_review done; do
  grep -qF "\"name\":\"status/$s\"" "$L1" \
    || { echo "FAIL: status/$s column not provisioned" >&2; exit 1; }
done
# priority / size / category taxonomy (spot-check one slug per scope).
grep -qF '"name":"priority/p1"'      "$L1" || { echo "FAIL: priority taxonomy missing" >&2; exit 1; }
grep -qF '"name":"size/xs"'          "$L1" || { echo "FAIL: size taxonomy missing"     >&2; exit 1; }
grep -qF '"name":"category/feature"' "$L1" || { echo "FAIL: category taxonomy missing" >&2; exit 1; }
# retired 9-col slugs must NOT be provisioned (this is the reshaped 8, not the legacy 9).
if grep -qF '"name":"status/research"' "$L1" || grep -qF '"name":"status/needs_input"' "$L1"; then
  echo "FAIL: a retired 9-col status slug was provisioned" >&2; exit 1
fi
```

**Step 2: Run test to verify it fails**
Run: `bash tests/scripts/test_blacksmith_forgejo_provision.sh`
Expected: FAIL — the verb currently only runs the deps gate and creates no labels, so `grep -qF '"exclusive":true' "$L1"` fails with "labels not created with exclusive:true".

**Step 3: Write minimal implementation** — in `bin/harness-lib.sh`:

(a) Add the exclusive-label helper **immediately after** the `_blacksmith_forgejo_ensure_label()` closing brace (right before `_blacksmith_forgejo_assert_deps_unit`):

```bash
# Idempotent EXCLUSIVE scoped-label create (a single-select board column). Unlike
# the neutral _blacksmith_forgejo_ensure_label, sets exclusive:true so assigning one
# label in a scope auto-evicts the prior same-scope label (server-enforced; see
# docs/research/2026-06-27-backend-capability.md:43-49). Never fails the caller
# (re-creating an existing label 422s and is tolerated for idempotency).
#   _blacksmith_forgejo_ensure_exclusive_label <name> [description] [color]
_blacksmith_forgejo_ensure_exclusive_label() {
  local name="$1" description="${2:-}" color="${3:-ededed}" owner repo
  owner=$(blacksmith_config_get '.forgejo.owner') || return 1
  repo=$(blacksmith_config_get '.forgejo.repo')   || return 1
  [[ "$color" == \#* ]] || color="#$color"
  _blacksmith_forgejo_curl POST "/repos/${owner}/${repo}/labels" \
    "$(jq -nc --arg n "$name" --arg d "$description" --arg c "$color" \
        '{name:$n, exclusive:true, color:$c, description:$d}')" \
    >/dev/null 2>&1 || true
}
```

(b) Replace the **body** of `_blacksmith_forgejo_provision_board` (added in Task 2) with the full version that creates the labels after the gate:

```bash
_blacksmith_forgejo_provision_board() {
  local owner repo slug
  owner=$(blacksmith_config_get '.forgejo.owner') || return 1
  repo=$(blacksmith_config_get '.forgejo.repo')   || return 1
  _blacksmith_forgejo_assert_deps_unit "$owner" "$repo" || return 1

  # The reshaped 8-column status scheme (slugs only; display names live in
  # _blacksmith_default_name_for_slug, owned by the T5 reshape — independent here).
  for slug in backlog scoping planning plan_approval ready in_progress in_review done; do
    _blacksmith_forgejo_ensure_exclusive_label "status/${slug}" "oskr status column" "ededed"
  done
  # Priority / Size / Category taxonomy (each scope single-select).
  for slug in p1 p2 p3;                      do _blacksmith_forgejo_ensure_exclusive_label "priority/${slug}" "oskr priority" "d73a4a"; done
  for slug in xs s m l xl;                   do _blacksmith_forgejo_ensure_exclusive_label "size/${slug}"     "oskr size"     "0e8a16"; done
  for slug in feature bug chore spike docs;  do _blacksmith_forgejo_ensure_exclusive_label "category/${slug}" "oskr category" "5319e7"; done
}
```

> Note: the status slug list is intentionally local to this verb — it provisions `status/<slug>` labels directly and does **not** read `_blacksmith_default_name_for_slug` (which still encodes the legacy 9 and is the Area's T5/#52 reshape). This keeps #58 parallelizable (PRD: "T8 … ∥") with no edit to the shared display-name map.

**Step 4: Run test to verify it passes**
Run: `bash tests/scripts/test_blacksmith_forgejo_provision.sh`
Expected: PASS — prints `test_blacksmith_forgejo_provision: PASS`.

**Step 5: Commit** — `git add bin/harness-lib.sh tests/scripts/test_blacksmith_forgejo_provision.sh && git commit -m "feat(forgejo): provision 8 status + taxonomy as exclusive scoped labels (#58)"`

---

## Task 4: Wire the verb into the live smoke, bump version, suite + seam guard green

**Files:**
- Modify: `bin/smoke/forgejo-roundtrip.sh` (call the verb in its live home + Area-5 deferral note)
- Modify: `.claude-plugin/plugin.json` (version bump)

**Harness-infrastructure substitution:** the smoke edit is opt-in live-test wiring + a prose deferral note — verified by `grep` (not a CI run; the smoke needs network + a PAT and is explicitly Area 5's gate).

**Acceptance Criteria:**
- [ ] `bin/smoke/forgejo-roundtrip.sh` invokes `blacksmith_provision_board` (its live home) and the header carries the `Area 5` live-acceptance deferral note.
- [ ] `.claude-plugin/plugin.json` `version` is `0.4.0` (minor — a new blacksmith verb is a new capability per the versioning convention).
- [ ] The seam guard `test_backend_no_inline_gh.sh` passes (the verb is inside `harness-lib.sh`; no inline `curl` enters any other `bin/` script; every `bin/*.sh` parses).
- [ ] `tests/scripts/run-tests.sh` exits 0 (whole suite green, including the new provision test; `test_harness_config.sh` unchanged and green).

**Step 1: Write the acceptance criterion**
Run: `grep -qF 'blacksmith_provision_board' bin/smoke/forgejo-roundtrip.sh && grep -qiF 'Area 5' bin/smoke/forgejo-roundtrip.sh && [[ "$(jq -r .version .claude-plugin/plugin.json)" == 0.4.0 ]]`
Expected (before): FAIL — the smoke does not reference the verb and version is still `0.3.5`.

**Step 2: Implement — wire the smoke.** In `bin/smoke/forgejo-roundtrip.sh`:

(a) Replace the header sentence about pre-provisioned labels (currently "whose exclusive status/* labels are already provisioned (the manual setup step, owned by #27)") with:

```bash
# whose board is provisioned by `blacksmith_provision_board` (run below). That verb is
# curl-shim-proven hermetically in #27; THIS live round-trip against a real Forgejo is
# its acceptance gate and is deferred to Area 5. Each run leaves a few test issues
# behind — delete the repo to reset.
```

(b) Immediately after the `export HARNESS_CONFIG="$CFG"` line, add the provisioning call (it runs only under the opt-in live smoke, never in CI):

```bash
blacksmith_provision_board && ok "board provisioned (8 status + taxonomy, exclusive labels)" \
  || no "blacksmith_provision_board failed"
```

> Seam-guard safety: this adds only a verb call (no `curl`, no `api/v1`) to `bin/smoke/`, so `test_backend_no_inline_gh.sh` still passes. The `ok`/`no` helpers are defined later in the script — move the new call to **after** their definitions (after line ~36, just before the first `blacksmith_create_issue`) if the implementer prefers a single insertion point; either placement keeps the guard and `bash -n` green.

**Step 3: Implement — bump the version.** In `.claude-plugin/plugin.json`, change `"version": "0.3.5",` to:

```json
  "version": "0.4.0",
```

Rationale: pre-1.0, a new capability (the `blacksmith_provision_board` verb) is a **minor** bump per `CLAUDE.md` § Versioning. (Sibling #27 children also target `0.4.0` on this Area branch — if one already landed the bump at merge, reconcile to the next free minor; the bump is a tracking signal, not load-bearing.)

**Step 4: Run the full verification**
Run: `grep -qF 'blacksmith_provision_board' bin/smoke/forgejo-roundtrip.sh && grep -qiF 'Area 5' bin/smoke/forgejo-roundtrip.sh && [[ "$(jq -r .version .claude-plugin/plugin.json)" == 0.4.0 ]] && bash tests/scripts/test_backend_no_inline_gh.sh && bash tests/scripts/run-tests.sh`
Expected: PASS — greps pass, version assertion passes, the seam guard prints `test_backend_no_inline_gh: PASS`, and `run-tests.sh` prints `Results: N/N passed, 0 failed` (exit 0).

**Step 5: Commit** — `git add bin/smoke/forgejo-roundtrip.sh .claude-plugin/plugin.json && git commit -m "chore(forgejo): wire provision_board into live smoke; bump 0.3.5 -> 0.4.0 (#58)"`

---

## Cross-task dependencies

- **Internal ordering is strictly sequential:** T1 (shim route + fixtures) → T2 (dispatcher + deps gate; consumes the T1 fixtures) → T3 (label loop; extends T2's verb + test) → T4 (live-smoke wiring + version bump + suite/guard green; requires all prior tasks landed). Each later task edits the artifacts the earlier one created.
- **Cross-issue — no code dependency on the Area's T1 (workspace resolver / two-tier config).** The PRD Task DAG marks T8 "blocked-by T1; ∥", but that edge is *sequencing*, not code: this verb only uses `blacksmith_config_get '.forgejo.*'` + `_blacksmith_forgejo_curl`, both already on `main` (Area 2 / the blacksmith landed). It is implementable against current `main` today; it reads **no** global `.oskr/config.json` and touches **no** workspace-root logic. Honest tradeoff to surface: if the reviewer wants strict DAG adherence, this slice can wait behind T1, but nothing technical forces it.
- **No code dependency on the Area's T5 (#52 8-column reshape).** This verb provisions `status/<slug>` labels by literal slug and deliberately does **not** read `_blacksmith_default_name_for_slug` (which still maps the legacy 9 columns until T5 lands). So #58 and #52 can proceed in parallel with no shared-edit conflict in `harness-lib.sh`'s display-name map. (If T5 later introduces a single canonical 8-slug list helper, a follow-up could DRY this verb onto it — out of scope here.)
- **Shared-file contention with sibling #27 children:** `.claude-plugin/plugin.json` (`version` line) is the only file every child touches — reconcile the version at merge as noted. `bin/harness-lib.sh` is also edited by T4/T5 of the Area, but in **disjoint regions** (this slice adds a new public verb line + a new Forgejo function block; T5 edits `_blacksmith_default_name_for_slug` + the GitHub provisioning path) — a clean three-way merge is expected.
- **Untouched on purpose:** `tests/scripts/test_harness_config.sh` and the project-tier config resolver (`blacksmith_config_path`) are not modified — the precedence-unchanged guarantee holds trivially because this slice never touches them. The neutral `_blacksmith_forgejo_ensure_label` is left as-is (exclusivity is a separate, provisioning-only helper).
