# Harness `.env` Auto-Load + Registry Migrate-Ordering Guard Implementation Plan

**Goal:** Auto-load a workspace `.env` at `harness-lib.sh` source time (pre-existing env wins), and make the first registry touch — `list` OR `add` — migrate a legacy registry before an empty first-create can permanently no-op migration.
**Architecture:** Task 1 adds `blacksmith_load_workspace_env` to `bin/harness-lib.sh` and auto-invokes it (failure-tolerant) at the file tail. Task 2 inserts an unconditional `registry_migrate` call at the top of `bin/registry.sh`'s shared `_registry_file` create point, before the empty `{"projects":[]}` fallback. Both are pure bash + jq, hermetically tested with fixture workspaces and `OSKR_WORKSPACE` / `OSKR_LEGACY_REGISTRY` overrides.
**Tech Stack:** bash (3.2-safe, `set -euo pipefail`), jq, existing `tests/scripts/` harness (`run-tests.sh` nullglob auto-discovery + `lib/assert.sh`).
**Issue:** #102 (T6, Area #29)

**Testing form:** Standard TDD (write failing test → red → implement → green → commit). Not the grep-substitution form — both deliverables are executable bash with observable runtime behavior. No forge (gh/curl) calls, so no forge shim and the `bin/` seam guard stays green.

**Dependencies:** Task 1 and Task 2 are independent — disjoint files (`bin/harness-lib.sh` vs `bin/registry.sh`), disjoint test files, no ordering constraint. Both inherit the frozen `blacksmith_workspace_dir` contract (echoes workspace root on stdout, honors `OSKR_WORKSPACE`, loud+dies on failure — callers wrap `2>/dev/null` for quiet no-op). No `plugin.json` version bump (deferred to land-area).

**Prior art mirrored (read before implementing):** `tests/scripts/test_workspace_dir.sh` (subshell + `OSKR_WORKSPACE` fixture), `tests/scripts/test_registry_migrate.sh` (`OSKR_LEGACY_REGISTRY` legacy fixture), `tests/scripts/test_registry_add.sh` (`run()` wrapper + jq assertions). Assertion helper: `tests/scripts/lib/assert.sh` (`assert_eq`).

---

## Task 1: Workspace `.env` auto-load in `bin/harness-lib.sh`

**Files:**
- Modify: `bin/harness-lib.sh` (append at tail, after the hjarne source block at :1553-1555)
- Test: `tests/scripts/test_workspace_env.sh` (create)

**Acceptance Criteria:**
- [ ] `blacksmith_load_workspace_env` is defined and auto-invoked at source time; a `.env` `KEY=VAL` sets AND exports KEY.
  - Run: `bash tests/scripts/test_workspace_env.sh` → Expected: exit 0, stdout ends `test_workspace_env: PASS`
- [ ] Export reaches a NON-sourcing grandchild process (proves `export`, not just a shell var). Covered by `test_workspace_env.sh` Case 1.
- [ ] Verb-observed pinned probe: `source '$LIB'; printf '%s' "${OSKR_TEST_TOKEN:-UNSET}"` → `s3cr3t`, exit 0. Covered by Case 2.
- [ ] Pre-existing process env wins over `.env`. Covered by Case 3.
- [ ] `.env` value never printed to stdout/stderr at source time. Covered by Case 4 (`! grep -qF 's3cr3t'`).
- [ ] No-workspace silence: outside any `.oskr`, `OSKR_WORKSPACE=""`, `source '$LIB'` → exit 0, empty stderr. Covered by Case 5.
- [ ] `set -u`/`set -e`-safe and idempotent on double-source. Covered by Case 6.
- [ ] Regression: existing resolver test still passes.
  - Run: `bash tests/scripts/test_workspace_dir.sh` → Expected: exit 0

**Step 1: Write the failing test**

Create `tests/scripts/test_workspace_env.sh`:

```bash
#!/usr/bin/env bash
# harness-lib.sh workspace .env auto-load (#102). Sourcing the lib inside a
# workspace loads <ws>/.env into the environment (set + export), but only for
# keys currently UNSET — a pre-existing process value always wins. Values are
# assigned literally and never echoed. Quiet no-op outside a workspace; safe
# under set -euo pipefail; idempotent on double-source. OSKR_WORKSPACE pins the
# workspace so the fixtures never touch the real $HOME.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"
export LIB="$REPO_ROOT/bin/harness-lib.sh"

# Fixtures: WS (.env with a secret), WS2 (.env whose value must LOSE to process
# env), OUTSIDE (no .oskr ancestor). cd+pwd canonicalizes past /tmp symlinks.
WS=$(cd "$(mktemp -d)" && pwd)
WS2=$(cd "$(mktemp -d)" && pwd)
OUTSIDE=$(cd "$(mktemp -d)" && pwd)
trap 'rm -rf "$WS" "$WS2" "$OUTSIDE"' EXIT
mkdir -p "$WS/.oskr" "$WS2/.oskr"
printf 'OSKR_TEST_TOKEN=s3cr3t\n' > "$WS/.env"
printf 'OSKR_TEST_TOKEN=fromfile\n' > "$WS2/.env"

# Case 1: export reaches a NON-sourcing grandchild (proves export, not a shell var).
out=$(OSKR_WORKSPACE="$WS" bash -c 'source "$LIB"; exec bash -c '\''printf %s "${OSKR_TEST_TOKEN:-UNSET}"'\''')
assert_eq 's3cr3t' "$out" "export reaches a non-sourcing grandchild" || exit 1

# Case 2: verb-observed pinned probe in the sourcing shell.
out=$(OSKR_WORKSPACE="$WS" bash -c 'source "$LIB"; printf %s "${OSKR_TEST_TOKEN:-UNSET}"')
assert_eq 's3cr3t' "$out" "source-time load sets the var in the sourcing shell" || exit 1

# Case 3: pre-existing process env wins over .env.
out=$(OSKR_TEST_TOKEN=fromenv OSKR_WORKSPACE="$WS2" \
      bash -c 'source "$LIB"; printf %s "${OSKR_TEST_TOKEN:-UNSET}"')
assert_eq 'fromenv' "$out" "pre-existing process env wins over .env" || exit 1

# Case 4: the secret is never echoed to stdout or stderr at source time.
combined=$(OSKR_WORKSPACE="$WS" bash -c 'source "$LIB"' 2>&1 || true)
if grep -qF 's3cr3t' <<<"$combined"; then
  echo "FAIL: .env value leaked to source-time output" >&2; exit 1
fi

# Case 5: no workspace -> exit 0 and EMPTY stderr (quiet fallback probe).
set +e
err=$(cd "$OUTSIDE" && OSKR_WORKSPACE="" bash -c 'source "$LIB"' 2>&1 1>/dev/null)
rc=$?
set -e
assert_eq '0' "$rc" "no-workspace source exits 0" || exit 1
assert_eq ''  "$err" "no-workspace source emits no stderr" || exit 1

# Case 6: set -euo pipefail + idempotent double-source -> exit 0, value intact.
set +e
out=$(OSKR_WORKSPACE="$WS" bash -c \
  'set -euo pipefail; source "$LIB"; source "$LIB"; printf %s "${OSKR_TEST_TOKEN:-UNSET}"')
rc=$?
set -e
assert_eq '0' "$rc" "double-source under set -euo pipefail exits 0" || exit 1
assert_eq 's3cr3t' "$out" "value correct after idempotent double-source" || exit 1

echo "test_workspace_env: PASS"
```

**Step 2: Run test to verify it fails**

Run: `bash tests/scripts/test_workspace_env.sh`
Expected: FAIL — Case 1 fails with `FAIL (export reaches a non-sourcing grandchild): expected 's3cr3t', got 'UNSET'` (the loader does not yet exist, so `.env` is never read).

**Step 3: Write minimal implementation**

Append to the END of `bin/harness-lib.sh` (after the hjarne source block, current tail :1553-1555):

```bash

# --- workspace .env auto-load (#102) ---------------------------------------
# Load <workspace>/.env into the process environment at source time. Each
# `KEY=VAL` line SETs and EXPORTs KEY, but ONLY when KEY is currently unset —
# a pre-existing process-env value always wins. Values are assigned literally
# (never eval'd, never echoed). Quiet no-op outside a workspace (mirrors
# blacksmith_global_config_path). Idempotent via a once-guard. Safe under set -u.
blacksmith_load_workspace_env() {
  [[ -n "${_BLACKSMITH_ENV_LOADED:-}" ]] && return 0
  _BLACKSMITH_ENV_LOADED=1
  local ws envfile line key val
  ws=$(blacksmith_workspace_dir 2>/dev/null) || return 0
  envfile="$ws/.env"
  [[ -f "$envfile" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    # trim leading whitespace
    line="${line#"${line%%[![:space:]]*}"}"
    # skip blanks and comments
    [[ -z "$line" || "$line" == '#'* ]] && continue
    # tolerate a leading `export `
    line="${line#export }"
    # require a KEY=VALUE shape
    [[ "$line" == *=* ]] || continue
    key="${line%%=*}"
    val="${line#*=}"
    # trim trailing whitespace off the key
    key="${key%"${key##*[![:space:]]}"}"
    # KEY must be a valid shell identifier
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    # pre-existing process env wins: only set when currently UNSET
    [[ -n "${!key+x}" ]] && continue
    # strip one layer of matching surrounding quotes
    if [[ ${#val} -ge 2 && "$val" == '"'*'"' ]]; then
      val="${val:1:${#val}-2}"
    elif [[ ${#val} -ge 2 && "$val" == "'"*"'" ]]; then
      val="${val:1:${#val}-2}"
    fi
    export "$key=$val"
  done < "$envfile"
  return 0
}

# Auto-load at source time. Failure-tolerant: the ~22 bin/ scripts source this
# under `set -euo pipefail`, so a load hiccup must never abort them.
blacksmith_load_workspace_env || true
```

Notes on the safety-critical choices (do NOT drift):
- `${!key+x}` is set-`u`-safe indirect *presence* test (yields `x` iff the named var is set) — this is the "process env wins" gate. Do not swap for `${!key:-}` (that would let `.env` override a set-but-empty var).
- `export "$key=$val"` assigns the value literally — no `eval`, no command substitution — so `.env` contents are never executed.
- The once-guard `_BLACKSMITH_ENV_LOADED` makes a double-source a no-op (Case 6). Each command-substitution subshell in the test is a fresh process, so the guard never leaks across cases.

**Step 4: Run test to verify it passes**

Run: `bash tests/scripts/test_workspace_env.sh`
Expected: PASS — stdout ends `test_workspace_env: PASS`, exit 0.

Also run the regression:
Run: `bash tests/scripts/test_workspace_dir.sh`
Expected: exit 0, `test_workspace_dir: PASS`.

**Step 5: Commit**

`git add bin/harness-lib.sh tests/scripts/test_workspace_env.sh && git commit -m "feat(harness-lib): auto-load workspace .env at source time (#102)"`

---

## Task 2: Registry migrate-ordering guard in `bin/registry.sh`

**Files:**
- Modify: `bin/registry.sh` (`_registry_file`, :36-42)
- Test: `tests/scripts/test_registry_migrate_ordering.sh` (create)

**Acceptance Criteria:**
- [ ] A read-only `list` as the FIRST touch migrates the legacy registry instead of orphaning it.
  - Run: `bash tests/scripts/test_registry_migrate_ordering.sh` → Expected: exit 0, stdout ends `test_registry_migrate_ordering: PASS`
- [ ] After a list-first touch: `jq '.projects|length' <WS>/.oskr/registry.json` ≥ 1. Covered by Case A.
- [ ] `add` as the first touch migrates THEN adds — registry holds BOTH the migrated legacy entry and the new one. Covered by Case B.
- [ ] Migrate idempotency preserved (byte-for-byte no-op on re-run; absent/present/already-migrated cases).
  - Run: `bash tests/scripts/test_registry_migrate.sh` → Expected: exit 0
- [ ] `registry_add` contract preserved (first-create, idempotent add, mixed backend, list).
  - Run: `bash tests/scripts/test_registry_add.sh` → Expected: exit 0
- [ ] Full suite green.
  - Run: `bash tests/scripts/run-tests.sh` → Expected: exit 0 (`Results: N/N passed, 0 failed`)

**Step 1: Write the failing test**

Create `tests/scripts/test_registry_migrate_ordering.sh`:

```bash
#!/usr/bin/env bash
# registry.sh migrate-ordering guard (#102). The FIRST touch of the registry in
# a workspace — whether a read-only `list` or a `add` — must migrate a legacy
# registry BEFORE the empty {"projects":[]} first-create can permanently
# short-circuit migrate (target exists => migrate no-ops forever, orphaning the
# legacy entries). OSKR_LEGACY_REGISTRY keeps the source fixture off the real
# $HOME/WillyDev/oskr/repos/projects.json.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"

seed_legacy() {
  cat > "$1" <<'JSON'
{ "projects": [
  { "name": "legacyproj", "path": "/ws/projects/legacyproj",
    "github": "WillyDallas/legacyproj", "project_number": 7,
    "registered_at": "2026-01-01T00:00:00Z" }
] }
JSON
}

WS_A=$(mktemp -d);  LEG_A=$(mktemp -d)
WS_B=$(mktemp -d);  LEG_B=$(mktemp -d)
trap 'rm -rf "$WS_A" "$LEG_A" "$WS_B" "$LEG_B"' EXIT
mkdir -p "$WS_A/.oskr" "$WS_B/.oskr"
REG_A="$WS_A/.oskr/registry.json"; LEGACY_A="$LEG_A/projects.json"
REG_B="$WS_B/.oskr/registry.json"; LEGACY_B="$LEG_B/projects.json"

# --- Case A: list-before-add regression pin --------------------------------
# A read-only `list` as the FIRST touch must migrate, not orphan the legacy.
seed_legacy "$LEGACY_A"
[[ ! -f "$REG_A" ]] || { echo "FAIL: registry.json should not exist yet (A)" >&2; exit 1; }

OSKR_WORKSPACE="$WS_A" OSKR_LEGACY_REGISTRY="$LEGACY_A" \
  bash "$REPO_ROOT/bin/registry.sh" list >/dev/null

[[ -f "$REG_A" ]] || { echo "FAIL: list did not create a registry (A)" >&2; exit 1; }
n=$(jq '.projects | length' "$REG_A")
[[ "$n" -ge 1 ]] || { echo "FAIL: list-before-add orphaned the legacy registry (0 entries)" >&2; exit 1; }
assert_eq 'legacyproj' "$(jq -r '.projects[0].name' "$REG_A")"  "list-first migrated the legacy entry" || exit 1
assert_eq 'github'     "$(jq -r '.projects[0].forge' "$REG_A")" "migrated entry forge-tagged" || exit 1
assert_eq '7' "$(jq -r '.projects[0].github.project_number' "$REG_A")" "project_number preserved through list-first migrate" || exit 1

# --- Case B: add as the FIRST touch migrates THEN adds ---------------------
seed_legacy "$LEGACY_B"
OSKR_WORKSPACE="$WS_B" OSKR_LEGACY_REGISTRY="$LEGACY_B" \
  bash "$REPO_ROOT/bin/registry.sh" add --name newproj --path /ws/projects/newproj \
    --forge github --owner WillyDallas --repo newproj --project-number 9

assert_eq '2' "$(jq '.projects | length' "$REG_B")" "add-first => migrated legacy + new = 2 entries" || exit 1
grep -qF '"legacyproj"' "$REG_B" || { echo "FAIL: add-first dropped the migrated legacy entry" >&2; exit 1; }
grep -qF '"newproj"'    "$REG_B" || { echo "FAIL: add-first did not add the new entry" >&2; exit 1; }

echo "test_registry_migrate_ordering: PASS"
```

**Step 2: Run test to verify it fails**

Run: `bash tests/scripts/test_registry_migrate_ordering.sh`
Expected: FAIL — Case A fails with `FAIL: list-before-add orphaned the legacy registry (0 entries)`. Today `_registry_file` first-creates an empty `{"projects":[]}`, and no `list` path calls `registry_migrate`, so the migrated entries never land.

**Step 3: Write minimal implementation**

Edit `bin/registry.sh` `_registry_file` (:36-42). Insert the `registry_migrate` call after `f=` is computed and BEFORE the empty first-create fallback:

Before:
```bash
# Echo the registry.json path, first-creating an empty registry when absent.
_registry_file() {
  local d f
  d=$(_registry_oskr_dir) || return 1
  f="$d/registry.json"
  [[ -f "$f" ]] || echo '{"projects": []}' > "$f"
  printf '%s' "$f"
}
```

After:
```bash
# Echo the registry.json path, first-creating an empty registry when absent.
# ORDERING (#102): migrate any legacy registry BEFORE the empty first-create
# below. Without this, the FIRST touch — `list` (read) OR `add` (write) —
# would first-create an empty {"projects":[]}, after which registry_migrate
# sees the target exist and no-ops forever, permanently orphaning the legacy
# entries. registry_migrate resolves its own target via _registry_oskr_dir
# (not _registry_file), so this is NOT recursive. Auto-migrate, not refuse;
# a read-only `list` may therefore perform a one-time migration.
_registry_file() {
  local d f
  d=$(_registry_oskr_dir) || return 1
  f="$d/registry.json"
  registry_migrate
  [[ -f "$f" ]] || echo '{"projects": []}' > "$f"
  printf '%s' "$f"
}
```

Notes (do NOT drift):
- `registry_migrate` writes only to stderr (status lines) and to the target file; it emits NO stdout, so `_registry_file`'s `printf '%s' "$f"` stays clean.
- It returns 0 on all no-op paths (target exists / source absent) and only exits non-zero on a genuine migration failure — correct fatal behavior under the caller's `set -e`. Do not add `|| true` (the frozen DoD says unconditional auto-migrate).

**Step 4: Run test to verify it passes**

Run: `bash tests/scripts/test_registry_migrate_ordering.sh`
Expected: PASS — stdout ends `test_registry_migrate_ordering: PASS`, exit 0.

Run the preserved-contract regressions and the full suite:
Run: `bash tests/scripts/test_registry_migrate.sh` → Expected: exit 0
Run: `bash tests/scripts/test_registry_add.sh` → Expected: exit 0
Run: `bash tests/scripts/run-tests.sh` → Expected: exit 0 (`Results: N/N passed, 0 failed`)

**Step 5: Commit**

`git add bin/registry.sh tests/scripts/test_registry_migrate_ordering.sh && git commit -m "fix(registry): migrate legacy registry on first touch before empty create (#102)"`

---

## Final verification (whole issue)

Run: `bash tests/scripts/run-tests.sh`
Expected: exit 0, `Results: N/N passed, 0 failed` — includes the two new auto-discovered `test_*.sh` files plus all prior-art regressions.
