# Dev-vs-installed toggle + active-copy doctor — Implementation Plan

**Goal:** Make working *on* oskr while *using* it safe and diagnosable: a `bin/doctor.sh` verb that reports which oskr copy is active (dev checkout vs marketplace cache) and warns on a dev/installed double-enable collision, plus the documented default-installed / explicit-`--plugin-dir` convention.
**Architecture:** A new sourceable+standalone `bin/doctor.sh` exposes pure env-read functions (classify `$CLAUDE_PLUGIN_ROOT` against the cache prefix; scan `$PATH` for oskr `bin/` dirs) wired into a `main` human report. The logic is hermetically tested against a fixture env tree in `tests/scripts/test_doctor.sh`. The convention itself is prose in `CONTRIBUTING.md`. No forge, no network — pure `$CLAUDE_PLUGIN_ROOT`/`$PATH` reads, the umbrella's "active-copy doctor" Named Seam.
**Tech Stack:** Bash (the `bin/` shell layer), the hermetic `tests/scripts/` subshell-fixture harness (`run-tests.sh`, `lib/assert.sh`), `jq` not needed here.
**Issue:** #55 (child of Area #27)

> **Implementer preflight (read first):** Execute *this* file —
> `docs/plans/2026-06-30-dev-vs-installed-doctor.md` (issue **#55**, the
> dev-vs-installed doctor). Do **not** confuse it with
> `docs/plans/2026-05-18-extract-harness-core-scripts.md`, an unrelated 13-task
> harness-lib plan for **#1** that also lives in `docs/plans/`. Confirm the plan
> says `**Issue:** #55` before the first commit.

---

## Definition of Done

This plan satisfies the frozen Plan DoD:

1. **Deliverables:**
   - Create `bin/doctor.sh` — the active-copy doctor verb (sourceable pure functions + standalone `main`).
   - Create `tests/scripts/test_doctor.sh` — hermetic fixture-env test of the env-read logic.
   - Modify `CONTRIBUTING.md` — document the default-installed vs explicit-`--plugin-dir` dev convention + the doctor.
   - Modify `.claude-plugin/plugin.json` — version bump (every PR bumps; new command ⇒ minor `0.3.5 → 0.4.0`).
2. **Testing tier:** **unit/hermetic** (subshell + fixture-env). Justification: the Named Seam for this child is explicitly "the dev-vs-installed active-copy doctor (a pure `$CLAUDE_PLUGIN_ROOT`/PATH env read)" — pure resolution at the `bin/` verb boundary, no forge, so no gh/curl-shim replay is needed. Prior art: `tests/scripts/test_harness_config.sh` (subshell-fixture style) and `tests/scripts/test_harness_cache.sh` (fixture-env, `mktemp` tree).
3. **Task granularity:** 4 tasks, each ≤ ~5 min of implementer work. **Flag:** Task 1 is the heaviest unit (two ~55-line files + two test runs + a commit) and sits at the *top edge* of the 2–5 min band; it is kept as one atomic RED→GREEN test+impl pair because the test is meaningless without the functions it exercises, and all code is supplied verbatim. Tasks 2–4 are comfortably inside the band.
4. **Verification:** every acceptance criterion below has a runnable command (see the AC → Verification map). No prose-only ACs.
5. **Dependencies:** see "Cross-task dependencies" — this child is **independent / parallelizable** (PRD Task DAG: "T9 — independent; ∥").
6. **Seam fidelity:** the doctor is a pure env read (no forge); two-tier config / project precedence is untouched by this slice (`test_harness_config.sh` is not modified and stays green).

### Harness-infrastructure TDD substitution (declared)

- **Tasks 1 & 2** are genuine shell logic and follow the full **5-step TDD pattern (RED test first)** against `tests/scripts/test_doctor.sh`.
- **Task 3 (documentation)** is prose. Per the agent contract, TDD is substituted with **"write acceptance criterion → grep/structural check → implement."** The implementer writes verbatim anchor strings into `CONTRIBUTING.md`, then a `grep -qF`/`grep -qFe` over the file is the verification. This substitution is deliberate and noted so plan-reviewer does not flag a missing test.
- **Task 4 (version bump + suite green)** is a config edit + a structural run; verified by `jq` read + `run-tests.sh` exit 0.

### Playwright tier — exemption (justified)

This issue touches **no** UI components, navigation, auth, or browser-observable behavior. The only user-facing surface is **CLI stdout/stderr from `bin/doctor.sh`**, which is asserted directly by capturing output and `grep`-ing it in `test_doctor.sh`. There is no web surface to drive, so the Playwright AC class does not apply. **Exempt.**

### Design/quality-rule ACs

The project declares no `.claude/rules/` directory (verified: `Glob .claude/rules/**` → no files). The design/quality-rule AC requirement is therefore a **no-op** for this plan.

---

## AC → Verification map

The task's four acceptance criteria (from #55) map to runnable commands as follows:

| # | Acceptance criterion (#55) | Verification command | Expected | Task |
|---|---|---|---|---|
| 1 | Doctor reports the active oskr copy (dev vs cached) by reading `$CLAUDE_PLUGIN_ROOT` / PATH | `bash tests/scripts/test_doctor.sh` (Test 1,2,6,7) | exit 0 | T1, T2 |
| 2 | Doctor detects + warns on a double-enable collision | `bash tests/scripts/test_doctor.sh` (Test 4,5) | exit 0 | T1, T2 |
| 3 | Default-installed vs explicit-`--plugin-dir`-dev convention is documented | `grep -qFe '--plugin-dir' CONTRIBUTING.md && grep -qF 'is the default' CONTRIBUTING.md && grep -qF 'bin/doctor.sh' CONTRIBUTING.md && grep -qF 'double-enable' CONTRIBUTING.md` | exit 0 | T3 |
| 4 | Doctor's env-read logic covered by a hermetic test (fixture env) | `bash tests/scripts/test_doctor.sh` | exit 0 | T1, T2 |
| — | Whole suite stays green; doctor parses + passes seam guard | `bash tests/scripts/run-tests.sh` | exit 0 | T4 |
| — | Version bumped | `[[ "$(jq -r .version .claude-plugin/plugin.json)" == 0.4.0 ]]` | exit 0 | T4 |

All paths are relative to the repo root `.`. Run commands from that directory (or prefix with it).

> **Why `grep -qFe '--plugin-dir'` and not `grep -qF '--plugin-dir'`:** the
> pattern starts with `--`, so plain `grep` parses it as a (nonexistent) long
> option and exits **2** ("invalid option") — the criterion could never reach a
> true exit-0 GREEN. `-e` (or a `--` separator) forces the next token to be read
> as the *pattern*. Verified on both `/usr/bin/grep` and this repo's `ugrep`
> shim: `grep -qF '--plugin-dir'` → exit 2; `grep -qFe '--plugin-dir'` → exit 0.
> Keep the `-e`; do not "simplify" it back to `-qF`. The other three anchors do
> not start with `-`, so plain `grep -qF` is correct for them.

---

## Task 1: `bin/doctor.sh` — pure env-read functions (classify + PATH scan)

> **Granularity flag:** this is the heaviest task in the plan (creates two files
> + two test runs + a commit). It is deliberately *not* split because the test
> (`test_doctor.sh`) and the functions it exercises are a single RED→GREEN unit —
> splitting them would leave a half with no runnable verification. All code is
> supplied verbatim below, so the implementer types nothing from scratch.

**Files:**
- Create: `bin/doctor.sh`
- Create (test): `tests/scripts/test_doctor.sh`

**Acceptance Criteria:**
- [ ] `oskr_doctor_classify <root> <cache_prefix>` echoes `installed` when `<root>` is under `<cache_prefix>`, else `dev`.
- [ ] `oskr_doctor_path_copies <path_value> <marker>` echoes the count of distinct `PATH` dirs that contain `<marker>` (the oskr `bin/` signature file `harness-lib.sh`).
- [ ] `tests/scripts/test_doctor.sh` Tests 1–4 pass.
- [ ] `bash -n bin/doctor.sh` parses (auto-covered by the seam guard in T4).

**Step 1: Write the failing test** — create `tests/scripts/test_doctor.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"

DOCTOR="$REPO_ROOT/bin/doctor.sh"

# --- Fixture env: a cache-rooted "installed" copy + a "dev" checkout. ---------
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
CACHE="$TMP/.claude/plugins/cache"
INSTALLED="$CACHE/oskr/0.3.5/bin"
DEV="$TMP/projects/oskr/bin"
mkdir -p "$INSTALLED" "$DEV"
# harness-lib.sh is the signature file that marks a dir as an oskr bin/ dir.
touch "$INSTALLED/harness-lib.sh" "$DEV/harness-lib.sh"

# Test 1: a cache-rooted plugin root classifies as "installed".
out=$(source "$DOCTOR" && oskr_doctor_classify "$CACHE/oskr/0.3.5" "$CACHE")
assert_eq "installed" "$out" "classify installed"

# Test 2: a dev checkout classifies as "dev".
out=$(source "$DOCTOR" && oskr_doctor_classify "$TMP/projects/oskr" "$CACHE")
assert_eq "dev" "$out" "classify dev"

# Test 3: one oskr bin dir on PATH -> count 1 (no collision).
out=$(source "$DOCTOR" && oskr_doctor_path_copies "$DEV:/usr/bin:/bin" "harness-lib.sh")
assert_eq "1" "$out" "single copy count"

# Test 4: both copies on PATH -> count 2 (the double-enable condition).
out=$(source "$DOCTOR" && oskr_doctor_path_copies "$DEV:$INSTALLED:/usr/bin" "harness-lib.sh")
assert_eq "2" "$out" "double-enable count"

echo "test_doctor: PASS"
```

**Step 2: Run test to verify it fails**
Run: `bash tests/scripts/test_doctor.sh`
Expected: FAIL — `bin/doctor.sh` does not exist yet, so `source "$DOCTOR"` errors with "No such file or directory" (non-zero exit at Test 1's command substitution).

**Step 3: Write minimal implementation** — create `bin/doctor.sh`:

```bash
#!/usr/bin/env bash
# doctor.sh — report which oskr copy is active and flag a dev/installed double-enable.
#
# oskr lives at projects/oskr inside the workspace AND is the plugin Claude Code loads.
# A `--plugin-dir` dev checkout and a marketplace-cached copy can BOTH be enabled at once,
# yielding duplicate /oskr:* skills and two oskr bin/ dirs on PATH with ambiguous precedence.
# This verb does PURE env reads — $CLAUDE_PLUGIN_ROOT + $PATH, no forge, no network — and reports:
#   - the active copy: a dev checkout vs the marketplace cache (~/.claude/plugins/cache)
#   - a double-enable collision when >1 oskr bin/ dir is on PATH
#
# Sourceable (pure functions, hermetically testable) + standalone (`main` prints a report
# and exits non-zero on collision). See docs/design/platform-reframe.md
# "Dev-vs-installed plugin toggle".
set -euo pipefail

# The marketplace cache prefix Claude Code copies installed plugins under
# (`~/.claude/plugins/cache` per the plugins-reference). OSKR_DOCTOR_CACHE_ROOT
# overrides it for hermetic tests; CLAUDE_CONFIG_DIR relocates ~/.claude if set.
oskr_doctor_cache_root() {
  printf '%s' "${OSKR_DOCTOR_CACHE_ROOT:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache}"
}

# Classify a plugin-root path. Echo "installed" if it sits under the cache prefix,
# else "dev". Pure over its two args.
# Usage: oskr_doctor_classify <plugin_root> <cache_prefix>
oskr_doctor_classify() {
  local root="$1" cache="$2"
  case "$root" in
    "$cache"/*) printf 'installed' ;;
    *)          printf 'dev' ;;
  esac
}

# Print, one per line, each distinct PATH dir that contains <marker> (an oskr bin/
# signature file, e.g. harness-lib.sh). Pure over its two args.
# Usage: oskr_doctor_oskr_bins <path_value> <marker>
oskr_doctor_oskr_bins() {
  local path_value="$1" marker="$2"
  local seen="" dir
  while IFS= read -r dir; do
    [[ -n "$dir" ]] || continue
    [[ -f "$dir/$marker" ]] || continue
    case ":$seen:" in *":$dir:"*) continue ;; esac
    seen="${seen:+$seen:}$dir"
    printf '%s\n' "$dir"
  done < <(printf '%s' "$path_value" | tr ':' '\n')
}

# Count of distinct oskr bin/ dirs on PATH. >1 ⇒ double-enable collision.
# Usage: oskr_doctor_path_copies <path_value> <marker>
oskr_doctor_path_copies() {
  local n
  n=$(oskr_doctor_oskr_bins "$1" "$2" | grep -c . || true)
  printf '%s' "$n"
}
```

**Step 4: Run test to verify it passes**
Run: `bash tests/scripts/test_doctor.sh`
Expected: PASS — prints `test_doctor: PASS`.

**Step 5: Commit** — `git add bin/doctor.sh tests/scripts/test_doctor.sh && git commit -m "feat(doctor): pure dev-vs-installed env-read functions (#55)"`

---

## Task 2: `bin/doctor.sh` — `main` report + collision exit

**Files:**
- Modify: `bin/doctor.sh` (append `main` + standalone guard)
- Modify (test): `tests/scripts/test_doctor.sh` (append integration asserts)

**Acceptance Criteria:**
- [ ] Running `bash bin/doctor.sh` with `CLAUDE_PLUGIN_ROOT` set to a dev path prints `active copy:  dev (<path>)`.
- [ ] Running it with `CLAUDE_PLUGIN_ROOT` set to a cache path prints `active copy:  installed (<path>)`.
- [ ] When `PATH` contains two oskr bin dirs, `main` prints a `double-enable collision` warning and exits non-zero.
- [ ] When `PATH` contains one oskr bin dir, `main` exits 0.
- [ ] `tests/scripts/test_doctor.sh` Tests 5–7 pass (and 1–4 still pass).

**Step 1: Write the failing test** — append to `tests/scripts/test_doctor.sh`, **immediately before** the final `echo "test_doctor: PASS"` line:

```bash
# Test 5: main warns + exits non-zero on a double-enable collision (PATH has both copies).
collision_out=$(
  CLAUDE_PLUGIN_ROOT="$TMP/projects/oskr" \
  OSKR_DOCTOR_CACHE_ROOT="$CACHE" \
  PATH="$DEV:$INSTALLED:/usr/bin:/bin" \
  bash "$DOCTOR" 2>&1
) && { echo "FAIL: doctor should exit non-zero on collision" >&2; exit 1; } || true
grep -qF "double-enable collision" <<<"$collision_out" \
  || { echo "FAIL: collision message missing" >&2; echo "$collision_out" >&2; exit 1; }

# Test 6: main reports the active DEV copy + exits 0 when only one copy is enabled.
single_out=$(
  CLAUDE_PLUGIN_ROOT="$TMP/projects/oskr" \
  OSKR_DOCTOR_CACHE_ROOT="$CACHE" \
  PATH="$DEV:/usr/bin:/bin" \
  bash "$DOCTOR" 2>&1
)
grep -qF "active copy:  dev" <<<"$single_out" \
  || { echo "FAIL: expected dev active-copy line" >&2; echo "$single_out" >&2; exit 1; }

# Test 7: main reports the active INSTALLED copy.
inst_out=$(
  CLAUDE_PLUGIN_ROOT="$CACHE/oskr/0.3.5" \
  OSKR_DOCTOR_CACHE_ROOT="$CACHE" \
  PATH="$INSTALLED:/usr/bin:/bin" \
  bash "$DOCTOR" 2>&1
)
grep -qF "active copy:  installed" <<<"$inst_out" \
  || { echo "FAIL: expected installed active-copy line" >&2; echo "$inst_out" >&2; exit 1; }
```

**Step 2: Run test to verify it fails**
Run: `bash tests/scripts/test_doctor.sh`
Expected: FAIL **at Test 5** (Tests 6–7 never run). At Task-1 state `bin/doctor.sh` defines functions but has **no `main` and no standalone guard**, so `bash "$DOCTOR"` simply sources the function definitions and exits **0**. Test 5 asserts the doctor exits *non-zero* on a double-enable collision; because the command substitution succeeds (exit 0), the `&& { echo "FAIL: doctor should exit non-zero on collision"; exit 1; }` guard fires and the script exits 1 with `FAIL: doctor should exit non-zero on collision` — before reaching the `single_out`/`inst_out` grep checks. (The `set -euo pipefail` at the top of the test does **not** short-circuit the assignment, because `collision_out=$(…) && {…} || true` is an AND-OR list, so errexit is suppressed for its non-final members.)

**Step 3: Write minimal implementation** — append to `bin/doctor.sh` (after the `oskr_doctor_path_copies` function):

```bash
# Human-readable report. Reads $CLAUDE_PLUGIN_ROOT (active copy) + $PATH (collision).
# Returns 0 normally, 1 on a double-enable collision.
main() {
  local root="${CLAUDE_PLUGIN_ROOT:-}" marker="harness-lib.sh"
  local cache kind copies
  cache="$(oskr_doctor_cache_root)"

  echo "oskr doctor"
  if [[ -z "$root" ]]; then
    echo "  active copy:  unknown (CLAUDE_PLUGIN_ROOT unset — not running under an enabled plugin?)"
  else
    kind="$(oskr_doctor_classify "$root" "$cache")"
    echo "  active copy:  $kind ($root)"
  fi

  copies="$(oskr_doctor_path_copies "${PATH:-}" "$marker")"
  echo "  oskr bin dirs on PATH: $copies"
  oskr_doctor_oskr_bins "${PATH:-}" "$marker" | sed 's/^/    - /'

  if (( copies > 1 )); then
    {
      echo "  WARNING: double-enable collision — $copies oskr copies are enabled at once."
      echo "  Duplicate /oskr:* skills and an ambiguous bin/ PATH precedence will result."
      echo "  Keep the installed/pinned plugin as the default; use --plugin-dir only to work ON oskr."
    } >&2
    return 1
  fi
  return 0
}

if [[ "${BASH_SOURCE[0]:-}" = "$0" ]]; then
  main "$@"
fi
```

> Note on exit behavior: with `set -e`, `main` returning 1 inside the `then`-body propagates and the script exits 1 — that is the desired "warns on collision" non-zero exit. The collision lines go to **stderr**; Test 5 captures `2>&1` so the `grep` sees them.

**Step 4: Run test to verify it passes**
Run: `bash tests/scripts/test_doctor.sh`
Expected: PASS — prints `test_doctor: PASS`.

**Step 5: Commit** — `git add bin/doctor.sh tests/scripts/test_doctor.sh && git commit -m "feat(doctor): active-copy report + double-enable collision warn (#55)"`

---

## Task 3: Document the dev-vs-installed convention (CONTRIBUTING.md)

**Harness-infrastructure substitution:** prose doc — TDD is replaced by **write AC → grep check → implement** (declared in the DoD).

**Files:**
- Modify: `CONTRIBUTING.md`

**Acceptance Criteria (grep checks):**
- [ ] `grep -qFe '--plugin-dir' CONTRIBUTING.md` → exit 0  *(must be `-e`; see the AC-map note — a plain `grep -qF '--plugin-dir'` exits 2 because `--plugin-dir` is parsed as an option)*
- [ ] `grep -qF 'is the default' CONTRIBUTING.md` → exit 0
- [ ] `grep -qF 'bin/doctor.sh' CONTRIBUTING.md` → exit 0
- [ ] `grep -qF 'double-enable' CONTRIBUTING.md` → exit 0

**Step 1: Write the acceptance criterion (the grep)**
Run: `grep -qFe '--plugin-dir' CONTRIBUTING.md && grep -qF 'is the default' CONTRIBUTING.md && grep -qF 'bin/doctor.sh' CONTRIBUTING.md && grep -qF 'double-enable' CONTRIBUTING.md`
Expected (before implementing): FAIL (exit 1) — none of these anchors exist in `CONTRIBUTING.md` yet. (The leading `grep -qFe '--plugin-dir'` exits 1 = "no match", **not** 2 = "bad option", confirming the command itself is well-formed and only the content is missing.)

**Step 2: Implement** — append this section to the **end** of `CONTRIBUTING.md`:

```markdown
## Developing oskr: dev vs installed

oskr lives at `projects/oskr` inside the workspace **and** is the plugin Claude Code
loads — a deliberate self-hosting recursion. So "I edited a skill" must not silently
change every workspace operation.

**The installed/pinned plugin is the default.** Working *on* oskr is a deliberate
`--plugin-dir projects/oskr` launch, never ambient:

    claude --plugin-dir projects/oskr     # load the dev checkout in-place for this session

Do not leave both enabled. A `--plugin-dir` dev copy does **not** replace a
marketplace-cached copy — both can be enabled at once, a **double-enable** collision
that yields duplicate `/oskr:*` skills and two `bin/` dirs on `PATH` with ambiguous
precedence.

**Which copy is active?** Run the doctor:

    bin/doctor.sh

It reads `$CLAUDE_PLUGIN_ROOT` and `$PATH` and reports whether the active copy is a
**dev** checkout or the **installed** marketplace cache (`~/.claude/plugins/cache`),
and exits non-zero with a warning if it detects a double-enable collision.
```

**Step 3: Run the acceptance criterion to verify it passes**
Run: `grep -qFe '--plugin-dir' CONTRIBUTING.md && grep -qF 'is the default' CONTRIBUTING.md && grep -qF 'bin/doctor.sh' CONTRIBUTING.md && grep -qF 'double-enable' CONTRIBUTING.md`
Expected: PASS (exit 0).

**Step 4: Commit** — `git add CONTRIBUTING.md && git commit -m "docs(doctor): document dev-vs-installed toggle + the doctor (#55)"`

---

## Task 4: Version bump + full suite green

**Files:**
- Modify: `.claude-plugin/plugin.json`

**Acceptance Criteria:**
- [ ] `.claude-plugin/plugin.json` `version` is `0.4.0` (minor bump — `bin/doctor.sh` is a new command/capability per the versioning convention).
- [ ] `tests/scripts/run-tests.sh` exits 0 (whole suite green, including the new `test_doctor.sh` and the unchanged `test_harness_config.sh`).
- [ ] The seam guard `test_backend_no_inline_gh.sh` passes — it `bash -n`s every `bin/**/*.sh` (so `doctor.sh` parses) and finds no inline `gh`/`curl` in it.

**Step 1: Write the acceptance criterion**
Run: `[[ "$(jq -r .version .claude-plugin/plugin.json)" == 0.4.0 ]]`
Expected (before): FAIL — version is still `0.3.5`.

**Step 2: Implement** — edit `.claude-plugin/plugin.json`, change line 4:

```json
  "version": "0.4.0",
```

(from `"version": "0.3.5",`). Rationale: pre-1.0, a new user-visible command (`bin/doctor.sh`) is a **minor** bump per `CONTRIBUTING.md` § Versioning.

**Step 3: Run the full verification**
Run: `[[ "$(jq -r .version .claude-plugin/plugin.json)" == 0.4.0 ]] && bash tests/scripts/run-tests.sh`
Expected: PASS — version assertion passes; `run-tests.sh` prints `Results: N/N passed, 0 failed` and exits 0.

**Step 4: Commit** — `git add .claude-plugin/plugin.json && git commit -m "chore: bump 0.3.5 -> 0.4.0 for doctor (#55)"`

---

## Cross-task dependencies

- **This child (#55 / T9) is independent and parallelizable** at the Area level (PRD Task DAG: "T9 — dev-vs-installed toggle + active-copy doctor. *(independent; ∥)*"). It does **not** depend on T1's workspace-root resolver, two-tier config, the registry, `init` v2, or any forge code: the doctor is a pure `$CLAUDE_PLUGIN_ROOT`/`$PATH` env read.
- **Internal ordering:** T1 → T2 (T2 appends `main` to the file and the integration asserts to the test created in T1) → T3 (doc references `bin/doctor.sh` created in T1/T2) → T4 (runs the full suite, so all prior tasks must be green). Strictly sequential within this plan.
- **No shared-file contention with sibling #27 tasks:** `bin/doctor.sh` and `tests/scripts/test_doctor.sh` are new files unique to this slice. The only shared files touched are `CONTRIBUTING.md` (append-only section) and `.claude-plugin/plugin.json` (`version` line) — both standard per-PR touch points; resolve the version line to whatever is on the Area branch at merge (re-bump if a sibling already moved it).
- **Untouched on purpose:** `bin/harness-lib.sh`, `tests/scripts/test_harness_config.sh`, and every forge path are not modified — the project-tier precedence guarantee is preserved trivially because this slice does not touch the config resolver.
