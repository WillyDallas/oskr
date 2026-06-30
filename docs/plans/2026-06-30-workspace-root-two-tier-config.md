# Workspace-Root Resolver + Two-Tier Config (Additive) Implementation Plan

**Goal:** Give any oskr `bin/` operation a way to find the workspace root (`.oskr/`) from any subdirectory, and make config two-tier — project `harness-config.json` keeps its exact behavior, a new lower-precedence global `.oskr/config.json` supplies defaults consulted only when a key is absent from the project tier.

**Architecture:** Two net-new sourceable functions in `bin/harness-lib.sh` — `blacksmith_workspace_dir` (OSKR_WORKSPACE override → upward `.oskr/` filesystem walk → loud error) and `blacksmith_global_config_path` (workspace `.oskr/config.json` or quiet fail). `blacksmith_config_get` gains a strictly-additive fallback: it tries the project config first (byte-for-byte unchanged), and only on a non-resolving key consults the global tier before reproducing today's failure. `blacksmith_config_path` and `blacksmith_config_get_array` are untouched.

**Tech Stack:** bash 3.2+ (macOS default), `jq`. Tests use the existing hand-rolled `set -euo pipefail` subshell-fixture runner (`tests/scripts/run-tests.sh` + `lib/assert.sh`) — no bats, no new deps.

**Issue:** #54 (child of Area #27 — Workspace & setup)

---

## Exemptions & substitutions (declared for plan-reviewer)

- **No Playwright AC.** Pure shell library; zero UI / navigation / auth surface. The Playwright tier does not apply.
- **No design/quality-rule ACs.** The project declares no `.claude/rules/` (verified: `Glob .claude/rules/**` → no files). This AC class is a no-op here.
- **Standard 5-step TDD (no substitution).** This is testable shell at the `bin/` verb boundary, not an agent prompt / skill-prose / config-only change. RED-first applies and is used.
- **Seam tier = subshell + fixture only.** Per the umbrella's Named Seams, this child is "pure resolution" (config/workspace-root). It touches **no** forge-probing verb, so neither `lib/gh-shim.sh` nor `lib/curl-shim.sh` is needed. Fixtures are an mktemp workspace tree + one static global-config fixture.

## Scope boundary (what this child is NOT)

The Area PRD's "T1" sketch bundled a legacy-registry **migration shim** with the resolver. Issue #54's `## What` / `## AC` do **not** — they cover only (a) the workspace-root resolver and (b) the two-tier config merge. The migration shim, `bin/registry.sh`, and any registry relocation are **out of scope** here (they live in the T2 child). This plan also leaves `_blacksmith_forge` and `blacksmith_config_get_array` project-tier-only by deliberate choice (the "deliberately minimal reader" decision) — only `blacksmith_config_get` gains the global fallback, because that is the single getter `/oskr-setup` and `init` v2 read shared defaults through.

---

## Definition of Done

1. **Deliverables:**
   - Modify `bin/harness-lib.sh`: add `blacksmith_workspace_dir`, add `blacksmith_global_config_path`, make `blacksmith_config_get` two-tier (additive).
   - Create `tests/scripts/test_workspace_dir.sh` (resolver over a fixture tree).
   - Create `tests/scripts/test_two_tier_config.sh` (merge order + project-tier regression).
   - Create `tests/scripts/fixtures/oskr-config.global.json` (global-tier fixture).
2. **Testing tier:** Unit / hermetic subshell-fixture — the umbrella's "pure resolution" seam. No integration/e2e: there is no forge call, no network, no live board. Justification: every behavior is a pure function of `{PWD, OSKR_WORKSPACE, project config, global config}`.
3. **Task granularity:** 3 tasks, each ≤ 5 min of implementer work (one function + its test; one getter change + its test/fixture; one suite-green verification gate).
4. **Verification:** every acceptance criterion below maps to a runnable `Run:`/`Expected:` tuple (see AC→Test map). No prose-only ACs.
5. **Dependencies:** Task 2 depends on Task 1 (`blacksmith_config_get` fallback calls `blacksmith_global_config_path` → `blacksmith_workspace_dir`). Task 3 depends on Tasks 1+2. Cross-child: #54 **blocks all** other #27 children; #54 itself is **not blocked-by** any (the blacksmith adapter it builds on already landed on `main`).
6. **Additive guarantee (issue-specific axis):** `blacksmith_config_path` precedence and every **present-key** `blacksmith_config_get` read are byte-for-byte unchanged; `tests/scripts/test_harness_config.sh` passes **untouched** (no edits to that file); `tests/scripts/run-tests.sh` is green.

---

## AC → Test map

| # | Acceptance criterion (from issue #54) | Verifying command |
|---|---|---|
| AC1 | From any nested subdir, resolver returns nearest ancestor with `.oskr/` | `bash tests/scripts/test_workspace_dir.sh` (Test 1) |
| AC2 | `OSKR_WORKSPACE` overrides the walk; clear error when neither resolves | `bash tests/scripts/test_workspace_dir.sh` (Tests 2–4) |
| AC3 | Project-tier precedence + present-key reads byte-for-byte unchanged; existing config test passes untouched | `bash tests/scripts/test_harness_config.sh` + `git diff --quiet -- tests/scripts/test_harness_config.sh` + `bash tests/scripts/test_two_tier_config.sh` (Test 4) |
| AC4 | Absent project key falls back to global; project wins when both define a key | `bash tests/scripts/test_two_tier_config.sh` (Tests 1–3) |
| AC5 | New hermetic tests cover resolution over a fixture tree (nested, no-workspace) + two-tier merge | `bash tests/scripts/run-tests.sh` (both new files discovered & green) |

---

## Task 1: `blacksmith_workspace_dir` resolver

**Files:**
- Modify: `bin/harness-lib.sh` (add `blacksmith_workspace_dir` after the config-getters block, ~line 55)
- Test: `tests/scripts/test_workspace_dir.sh` (create)

**Acceptance Criteria:**
- [ ] `Run: bash tests/scripts/test_workspace_dir.sh` → `Expected: exit 0` (prints `test_workspace_dir: PASS`)
- [ ] From a nested subdir of a fixture workspace, the function echoes the workspace root (Test 1).
- [ ] `OSKR_WORKSPACE` set to a valid workspace overrides the walk even when CWD is outside it (Test 2).
- [ ] With no ancestor `.oskr/` and `OSKR_WORKSPACE` empty, stderr contains `not inside an oskr workspace` and exit is non-zero (Test 3).
- [ ] `OSKR_WORKSPACE` set to a dir lacking `.oskr/` errors with `OSKR_WORKSPACE set but` (Test 4).
- [ ] `Run: grep -qF 'blacksmith_workspace_dir()' bin/harness-lib.sh` → `Expected: exit 0`

**Step 1: Write the failing test**

Create `tests/scripts/test_workspace_dir.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"
LIB="$REPO_ROOT/bin/harness-lib.sh"

# Fixture workspace tree: <WS>/.oskr/ + a nested project subdir.
# `cd ... && pwd` canonicalizes so string-equality holds despite /tmp symlinks.
WS=$(cd "$(mktemp -d)" && pwd)
OTHER=$(cd "$(mktemp -d)" && pwd)
trap 'rm -rf "$WS" "$OTHER"' EXIT
mkdir -p "$WS/.oskr" "$WS/projects/proj/src/deep"

# Test 1: from a nested subdir, resolver returns the workspace root.
OUT=$(cd "$WS/projects/proj/src/deep" && OSKR_WORKSPACE="" \
  bash -c "source '$LIB' && blacksmith_workspace_dir")
assert_eq "$WS" "$OUT" "nested subdir resolves to workspace root"

# Test 2: OSKR_WORKSPACE overrides the walk (CWD is outside the tree).
OUT=$(cd "$OTHER" && OSKR_WORKSPACE="$WS" \
  bash -c "source '$LIB' && blacksmith_workspace_dir")
assert_eq "$WS" "$OUT" "OSKR_WORKSPACE overrides the walk"

# Test 3: no .oskr/ ancestor and OSKR_WORKSPACE empty -> clear, actionable error.
ERR=$(cd "$OTHER" && OSKR_WORKSPACE="" \
  bash -c "source '$LIB' && blacksmith_workspace_dir" 2>&1 || true)
grep -qF "not inside an oskr workspace" <<<"$ERR" \
  || { echo "FAIL: missing clear no-workspace error; got: $ERR" >&2; exit 1; }

# Test 4: OSKR_WORKSPACE set but no .oskr/ inside -> clear misconfig error.
ERR=$(OSKR_WORKSPACE="$OTHER" \
  bash -c "source '$LIB' && blacksmith_workspace_dir" 2>&1 || true)
grep -qF "OSKR_WORKSPACE set but" <<<"$ERR" \
  || { echo "FAIL: misconfigured OSKR_WORKSPACE not flagged; got: $ERR" >&2; exit 1; }

echo "test_workspace_dir: PASS"
```

**Step 2: Run test to verify it fails**

Run: `bash tests/scripts/test_workspace_dir.sh`
Expected: FAIL — Test 1 reports `FAIL (nested subdir resolves to workspace root): expected '<WS>', got ''` (the function is undefined, so the subshell prints nothing to stdout).

**Step 3: Write minimal implementation**

In `bin/harness-lib.sh`, immediately after `blacksmith_config_get_array()` (the config-getters block ends ~line 55) and before the `# --- forge dispatch ---` header, insert:

```bash
# --- workspace-root resolution ---------------------------------------------

# Echo the workspace root: the nearest ancestor of $PWD containing a .oskr/
# directory. $OSKR_WORKSPACE, if non-empty, overrides the walk (and must itself
# contain .oskr/). Walks the filesystem, not git, so it crosses the gitignored
# project-repo boundary (e.g. projects/oskr inside the workspace). Loud error
# when neither resolves.
blacksmith_workspace_dir() {
  if [[ -n "${OSKR_WORKSPACE:-}" ]]; then
    if [[ -d "$OSKR_WORKSPACE/.oskr" ]]; then
      echo "$OSKR_WORKSPACE"; return 0
    fi
    _blacksmith_die "OSKR_WORKSPACE set but no .oskr/ found at: $OSKR_WORKSPACE"
    return 1
  fi
  local dir="$PWD"
  while :; do
    if [[ -d "$dir/.oskr" ]]; then
      echo "$dir"; return 0
    fi
    [[ "$dir" == "/" ]] && break
    dir=$(dirname "$dir")
  done
  _blacksmith_die "not inside an oskr workspace; no ancestor .oskr/ found and OSKR_WORKSPACE unset"
  return 1
}
```

**Step 4: Run test to verify it passes**

Run: `bash tests/scripts/test_workspace_dir.sh`
Expected: PASS — prints `test_workspace_dir: PASS`, exit 0.

**Step 5: Commit**
`git add bin/harness-lib.sh tests/scripts/test_workspace_dir.sh && git commit -m "feat(#54): workspace-root resolver (.oskr/ walk + OSKR_WORKSPACE override)"`

---

## Task 2: Two-tier `blacksmith_config_get` (additive global fallback)

**Files:**
- Modify: `bin/harness-lib.sh` (add `blacksmith_global_config_path`; rewrite `blacksmith_config_get` lines 45–49, additive)
- Test: `tests/scripts/test_two_tier_config.sh` (create)
- Create: `tests/scripts/fixtures/oskr-config.global.json`

**Dependencies:** Task 1 (`blacksmith_global_config_path` calls `blacksmith_workspace_dir`).

**Acceptance Criteria:**
- [ ] `Run: bash tests/scripts/test_two_tier_config.sh` → `Expected: exit 0` (prints `test_two_tier_config: PASS`)
- [ ] Project value wins when both tiers define a key (Test 1).
- [ ] A key absent from the project config falls back to the global tier (Test 2).
- [ ] A key absent from both tiers still fails non-zero (Test 3).
- [ ] With no workspace/global resolvable, a present project-tier key returns its value unchanged (Test 4 — regression).
- [ ] `Run: bash tests/scripts/test_harness_config.sh` → `Expected: exit 0` (existing resolver test passes untouched).
- [ ] `Run: git diff --quiet -- tests/scripts/test_harness_config.sh` → `Expected: exit 0` (that file was not edited).
- [ ] `Run: grep -qF 'blacksmith_global_config_path()' bin/harness-lib.sh` → `Expected: exit 0`

**Step 1: Write the failing test**

Create `tests/scripts/fixtures/oskr-config.global.json`:

```json
{
  "base_branch": "trunk",
  "github": { "owner": "GlobalOwner" },
  "forgejo": { "base_url": "https://git.squirrlylabs.dev" }
}
```

Create `tests/scripts/test_two_tier_config.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"
LIB="$REPO_ROOT/bin/harness-lib.sh"

# Workspace whose global tier defines base_branch + a github.owner.
WS=$(cd "$(mktemp -d)" && pwd)
trap 'rm -rf "$WS"' EXIT
mkdir -p "$WS/.oskr" "$WS/projects/proj"
cp "$REPO_ROOT/tests/scripts/fixtures/oskr-config.global.json" "$WS/.oskr/config.json"
cat > "$WS/projects/proj/harness-config.json" <<'JSON'
{ "github": { "owner": "WillyDallas", "repo": "oskr", "project_number": 1 } }
JSON
PROJ="$WS/projects/proj/harness-config.json"

get() { # get <jq-path> -> stdout
  OSKR_WORKSPACE="$WS" HARNESS_CONFIG="$PROJ" \
    bash -c "source '$LIB' && blacksmith_config_get '$1'"
}

# Test 1: project value wins when both tiers define the key.
assert_eq "WillyDallas" "$(get '.github.owner')" "project wins over global"

# Test 2: key absent from project falls back to the global tier.
assert_eq "trunk" "$(get '.base_branch')" "absent key falls back to global"

# Test 3: key absent from BOTH tiers still fails (non-zero).
if OSKR_WORKSPACE="$WS" HARNESS_CONFIG="$PROJ" \
   bash -c "source '$LIB' && blacksmith_config_get '.nope.missing'" >/dev/null 2>&1; then
  echo "FAIL: key missing in both tiers should fail" >&2; exit 1
fi

# Test 4: regression — with no workspace/global, project-tier read is unchanged.
OUT=$(OSKR_WORKSPACE="" \
  HARNESS_CONFIG="$REPO_ROOT/tests/scripts/fixtures/harness-config.sample.json" \
  bash -c "cd / && source '$LIB' && blacksmith_config_get '.github.owner'")
assert_eq "WillyDallas" "$OUT" "project-tier read unchanged with no workspace"

echo "test_two_tier_config: PASS"
```

**Step 2: Run test to verify it fails**

Run: `bash tests/scripts/test_two_tier_config.sh`
Expected: FAIL — Test 2 reports `FAIL (absent key falls back to global): expected 'trunk', got ''` (today `blacksmith_config_get '.base_branch'` on the project config returns non-zero with no fallback).

**Step 3: Write minimal implementation**

In `bin/harness-lib.sh`, add `blacksmith_global_config_path` directly after `blacksmith_workspace_dir` (from Task 1):

```bash
# Echo the global config file (<workspace>/.oskr/config.json), or fail quietly
# (return 1, no stderr) when no workspace or no global config exists. Quiet by
# design: it is a fallback probe, not a primary resolver.
blacksmith_global_config_path() {
  local ws gcfg
  ws=$(blacksmith_workspace_dir 2>/dev/null) || return 1
  gcfg="$ws/.oskr/config.json"
  [[ -f "$gcfg" ]] || return 1
  echo "$gcfg"
}
```

Then replace the existing `blacksmith_config_get` (lines 45–49) with the additive two-tier version:

```bash
blacksmith_config_get() {
  local path="$1" cfg out gcfg
  cfg=$(blacksmith_config_path) || return 1
  # Project tier first. A resolving key returns exactly what jq emits today;
  # the global fallback is strictly additive (present-key reads unchanged).
  if out=$(jq -er "$path" "$cfg" 2>/dev/null); then
    printf '%s\n' "$out"
    return 0
  fi
  # Absent from the project config: consult the global tier if one resolves.
  if gcfg=$(blacksmith_global_config_path 2>/dev/null); then
    if out=$(jq -er "$path" "$gcfg" 2>/dev/null); then
      printf '%s\n' "$out"
      return 0
    fi
  fi
  # Neither tier resolved the key: reproduce today's failure (jq error -> stderr).
  jq -er "$path" "$cfg"
}
```

Notes for the implementer (do **not** change these):
- `blacksmith_config_path` and `blacksmith_config_get_array` are untouched — project-tier precedence stays byte-for-byte.
- "Absent" is defined operationally as "`jq -e` yields no truthy value" (this conflates a missing key with an explicit `null`, matching jq's own model). That is acceptable and intended.
- For scalar values (owner/repo/project_number/base_branch/base_url — the only `config_get` callers), `out=$(...)` + `printf '%s\n'` reproduces jq's single-line-plus-newline output exactly.

**Step 4: Run test to verify it passes**

Run: `bash tests/scripts/test_two_tier_config.sh`
Expected: PASS — prints `test_two_tier_config: PASS`, exit 0.

Also confirm the additive guarantee holds:
Run: `bash tests/scripts/test_harness_config.sh`
Expected: PASS — prints `test_blacksmith_config: PASS`, exit 0.

**Step 5: Commit**
`git add bin/harness-lib.sh tests/scripts/test_two_tier_config.sh tests/scripts/fixtures/oskr-config.global.json && git commit -m "feat(#54): additive two-tier config_get (global .oskr/config.json fallback)"`

---

## Task 3: Suite-green + additive-regression gate

**Type:** Verification gate (no new production code). The "failing test" is the full suite run before the new tests/impl are in place; by this point Tasks 1–2 have made it green. This task asserts the whole contract holds together and nothing regressed.

**Files:**
- Modify: none (verification only)
- Test: runs the full `tests/scripts/` suite

**Acceptance Criteria:**
- [ ] `Run: bash tests/scripts/run-tests.sh` → `Expected: exit 0` (all `test_*.sh` pass, including the two new files and the untouched `test_harness_config.sh`).
- [ ] `Run: bash tests/scripts/run-tests.sh 2>&1 | grep -qF 'test_workspace_dir.sh'` → `Expected: exit 0` (new resolver test is discovered by the runner).
- [ ] `Run: bash tests/scripts/run-tests.sh 2>&1 | grep -qF 'test_two_tier_config.sh'` → `Expected: exit 0` (new merge test is discovered).
- [ ] `Run: git diff --quiet -- tests/scripts/test_harness_config.sh bin/harness-lib.sh` → `Expected: exit 0` after the Task-1/2 commits (no uncommitted drift in the touched files).
- [ ] `Run: bash tests/scripts/test_backend_no_inline_gh.sh` → `Expected: exit 0` (the seam guard still passes — this change added no inline `gh`/`curl`).

**Step 1 (gate, pre-implementation reference):** Before Tasks 1–2, `bash tests/scripts/run-tests.sh` would not yet include the two new tests. This task's role is the post-implementation green check.

**Step 2: Run the full suite**
Run: `bash tests/scripts/run-tests.sh`
Expected: PASS — final line `Results: N/N passed, 0 failed (N tests)`, exit 0.

**Step 3: Confirm no regression in the additive surface**
Run: `bash tests/scripts/test_harness_config.sh && bash tests/scripts/test_backend_no_inline_gh.sh`
Expected: PASS — `test_blacksmith_config: PASS` and the seam-guard pass line, exit 0.

**Step 4: (no code)** — gate only.

**Step 5: Commit** (only if any incidental fixup was needed; otherwise nothing to commit)
`git commit --allow-empty -m "test(#54): full suite green — workspace resolver + two-tier config"`

---

## Implementer guardrails (load-bearing)

- **Do not touch** `blacksmith_config_path`, `blacksmith_config_get_array`, `_blacksmith_forge`, or `tests/scripts/test_harness_config.sh`. The additive guarantee (AC3) is enforced by leaving them exactly as-is.
- **No inline `gh`/`curl`** — this change is forge-blind; keep it that way so `test_backend_no_inline_gh.sh` stays green.
- **bash 3.2 compatibility** (macOS default): no `${var,,}`, no associative arrays, no `mapfile`. The provided snippets already comply.
- **Quote `$PWD` / `$dir`** in the walk (paths may contain spaces in test mktemp dirs).
