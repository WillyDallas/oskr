# Extract Harness Core Scripts Implementation Plan

**Goal:** Port the dispatcher + board-helper bash scripts from Wonderloom into `oskr/scripts/`, eliminating hardcoded board option-UUIDs in favor of runtime resolution against `harness-config.json`.

**Architecture:** A new `harness-lib.sh` (sourced by all other scripts) loads `harness-config.json`, resolves Project v2 field/option UUIDs lazily via GraphQL, and caches them in `${XDG_CACHE_HOME:-$HOME/.cache}/oskr/<project_id>.json`. Four ported scripts (`dispatch-loop.sh`, `board-dispatcher.sh`, `move-issue.sh`, `check-budget.sh`) call the lib instead of `source board-constants.sh`. `move-issue.sh`'s CLI surface flips from `<ITEM_ID> <UUID>` to `<ITEM_ID> <COLUMN_NAME>`.

**Tech Stack:** bash 3.2+ (macOS default), `jq`, `gh` CLI. Tests use a hand-rolled `set -euo pipefail` runner — no bats-core dependency.

**Issue:** oskr#1

**Exemptions:**
- **No Playwright AC.** This is pure shell with no UI surface.
- **No E2E Foundation Gate.** oskr is not Wonderloom; no pipeline-relevant globs apply.
- **TDD substitution for GraphQL-dependent functions.** The `harness_project_id` / `harness_status_field_id` discovery is tested via a `gh` shim on `PATH` that returns canned JSON. One end-to-end smoke test exercises the live GitHub path at the very end (Task 13).

**AC form:** All ACs follow the tuple skeleton from Wonderloom's `docs/Architecture/ac-and-test-infra-conventions.md` section 1 (`Run: <cmd>` / `Expected: <exit code or exact stdout substring>`).

---

## Task 1: Sample harness-config fixture for unit tests

**Files:**
- Create: `tests/scripts/fixtures/harness-config.sample.json`
- Create: `tests/scripts/fixtures/harness-config.malformed.json`
- Create: `tests/scripts/fixtures/harness-config.with-aliases.json`

**Dependencies:** none.

**Acceptance Criteria:**
- [ ] `Run: test -f tests/scripts/fixtures/harness-config.sample.json && echo OK` → `Expected: stdout = "OK"`
- [ ] `Run: jq -e '.github.owner == "WillyDallas" and .github.repo == "oskr" and (.github.project_number | type == "number")' tests/scripts/fixtures/harness-config.sample.json` → `Expected: exit 0`
- [ ] `Run: jq -e '.workflow.actionable_columns | length == 4' tests/scripts/fixtures/harness-config.sample.json` → `Expected: exit 0`
- [ ] `Run: jq '.' tests/scripts/fixtures/harness-config.malformed.json` → `Expected: exit non-zero` (malformed by design; jq returns exit 5 for parse errors)
- [ ] `Run: jq -e '.workflow.column_names["needs_input"] == "Needs Developer Input"' tests/scripts/fixtures/harness-config.with-aliases.json` → `Expected: exit 0`

**Step 1: Write the failing test (verify fixtures missing)**

```bash
test ! -f tests/scripts/fixtures/harness-config.sample.json && echo "as expected, fixture missing"
```

**Step 2: Create the three fixtures**

`harness-config.sample.json`:
```json
{
  "name": "oskr-test",
  "github": {
    "owner": "WillyDallas",
    "repo": "oskr",
    "project_number": 1
  },
  "workflow": {
    "kind": "gen-eval-9col",
    "column_names": {},
    "actionable_columns": ["needs_input", "approval", "ready", "in_review"]
  },
  "paths": {
    "plans": "docs/plans",
    "research": "docs/research",
    "plan_archive": "docs/_local_archive"
  },
  "agent_context": {
    "project_name": "Oskr Test",
    "tech_stack": "bash + gh CLI"
  }
}
```

`harness-config.malformed.json`:
```
{ "name": "broken", "github":
```

`harness-config.with-aliases.json`: same as `sample.json` but with
```json
  "column_names": {
    "needs_input": "Needs Developer Input",
    "in_review": "PR Open"
  }
```

**Step 3: Run AC verifications**
Run each AC command; all must pass.

**Step 4: Commit**
`add harness-config fixtures for unit tests`

---

## Task 2: Bash test runner skeleton

**Files:**
- Create: `tests/scripts/run-tests.sh`
- Create: `tests/scripts/lib/assert.sh`
- Create: `tests/scripts/lib/gh-shim.sh`

**Dependencies:** Task 1.

**Acceptance Criteria:**
- [ ] `Run: bash -n tests/scripts/run-tests.sh` → `Expected: exit 0`
- [ ] `Run: shellcheck tests/scripts/run-tests.sh tests/scripts/lib/assert.sh tests/scripts/lib/gh-shim.sh` → `Expected: exit 0`
- [ ] `Run: tests/scripts/run-tests.sh` → `Expected: exit 0` (no tests yet — runner exits 0 on empty test set with stdout containing "0 tests")
- [ ] `Run: tests/scripts/run-tests.sh 2>&1 | grep -qF "0 tests"` → `Expected: exit 0`

**Step 1: Write the runner stub (will pass with zero tests)**

`run-tests.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PASS=0; FAIL=0; TOTAL=0
shopt -s nullglob
for test_file in "$SCRIPT_DIR"/test_*.sh; do
  TOTAL=$((TOTAL + 1))
  echo "==> $(basename "$test_file")"
  if bash "$test_file"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
  fi
done
echo "Results: $PASS/$TOTAL passed, $FAIL failed ($TOTAL tests)"
[[ "$FAIL" -eq 0 ]]
```

`lib/assert.sh`:
```bash
#!/usr/bin/env bash
assert_eq() {
  local expected="$1" actual="$2" msg="${3:-}"
  if [[ "$expected" != "$actual" ]]; then
    echo "FAIL${msg:+ ($msg)}: expected '$expected', got '$actual'" >&2
    return 1
  fi
}
assert_exit() {
  local expected="$1"; shift
  local actual=0
  "$@" >/dev/null 2>&1 || actual=$?
  if [[ "$expected" != "$actual" ]]; then
    echo "FAIL: expected exit $expected from '$*', got $actual" >&2
    return 1
  fi
}
assert_stdout_contains() {
  local needle="$1"; shift
  local out
  out=$("$@" 2>&1) || true
  if ! grep -qF "$needle" <<<"$out"; then
    echo "FAIL: '$*' stdout did not contain '$needle'" >&2
    echo "--- actual ---" >&2
    echo "$out" >&2
    return 1
  fi
}
```

`lib/gh-shim.sh`:
```bash
#!/usr/bin/env bash
# Drop-in `gh` replacement for tests. Reads canned responses from
# $GH_SHIM_FIXTURE (a JSON file) and echoes them. Each call increments
# a counter for cache-hit assertions.
: "${GH_SHIM_FIXTURE:?GH_SHIM_FIXTURE not set}"
: "${GH_SHIM_CALL_LOG:?GH_SHIM_CALL_LOG not set}"
echo "$*" >> "$GH_SHIM_CALL_LOG"
cat "$GH_SHIM_FIXTURE"
```

**Step 2: Run AC verifications**

**Step 3: Commit**
`add bash test runner skeleton`

---

## Task 3: harness-lib.sh — config-path discovery and getters

**Files:**
- Create: `scripts/harness-lib.sh`
- Create: `tests/scripts/test_harness_config.sh`

**Dependencies:** Task 2.

**Public functions added this task:**
- `harness_config_path` — echoes the resolved absolute path to `harness-config.json` (searches `$PWD`, then `$PWD/.claude/`, dies if neither).
- `harness_config_get <jq.path>` — echoes a scalar from the config.
- `harness_config_get_array <jq.path>` — echoes array elements one per line.

**Acceptance Criteria:**
- [ ] `Run: bash -n scripts/harness-lib.sh` → `Expected: exit 0`
- [ ] `Run: shellcheck scripts/harness-lib.sh` → `Expected: exit 0`
- [ ] `Run: tests/scripts/run-tests.sh` → `Expected: exit 0` (test_harness_config.sh passes)
- [ ] `Run: (cd tests/scripts/fixtures && source ../../../scripts/harness-lib.sh && harness_config_get '.github.owner')` → `Expected: stdout = "WillyDallas"`
- [ ] Missing config dies with explicit message: `Run: (cd /tmp && source $OLDPWD/scripts/harness-lib.sh && harness_config_path 2>&1)` → `Expected: stdout contains "not in an oskr project"` and `Expected: exit non-zero`
- [ ] Malformed JSON dies: when `HARNESS_CONFIG=tests/scripts/fixtures/harness-config.malformed.json`, `harness_config_get '.github.owner'` exits non-zero with jq error on stderr.

**Step 1: Write the failing test**

`tests/scripts/test_harness_config.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/lib/assert.sh"

# Test 1: resolve config from $PWD
HARNESS_CONFIG="$REPO_ROOT/tests/scripts/fixtures/harness-config.sample.json" \
  bash -c "source '$REPO_ROOT/scripts/harness-lib.sh' && [[ \$(harness_config_get '.github.owner') == 'WillyDallas' ]]"

# Test 2: missing config exits non-zero
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
( cd "$TMPDIR" && \
    HARNESS_CONFIG="" bash -c "source '$REPO_ROOT/scripts/harness-lib.sh' && harness_config_path" \
  ) 2>&1 | grep -qF "not in an oskr project"

# Test 3: malformed JSON propagates jq error
HARNESS_CONFIG="$REPO_ROOT/tests/scripts/fixtures/harness-config.malformed.json" \
  bash -c "source '$REPO_ROOT/scripts/harness-lib.sh' && harness_config_get '.github.owner'" 2>/dev/null \
  && { echo "FAIL: expected non-zero on malformed JSON"; exit 1; } || true

echo "test_harness_config: PASS"
```

**Step 2: Run test to verify it fails**
Run: `tests/scripts/run-tests.sh`
Expected: FAIL with "harness-lib.sh: No such file" or similar.

**Step 3: Write minimal implementation**

`scripts/harness-lib.sh` (this task adds only the config section; later tasks append):
```bash
#!/usr/bin/env bash
# harness-lib.sh — shared helpers for the oskr dispatcher scripts.
# Sourceable; not directly executable.
#
# Public functions (this section):
#   harness_config_path                  — absolute path to harness-config.json
#   harness_config_get <jq_path>         — scalar getter
#   harness_config_get_array <jq_path>   — array getter (one element per line)

# Each function uses `command jq` to avoid recursion into the test gh-shim.
# All functions either echo on stdout and return 0, or die with a message
# on stderr and return non-zero.

_harness_die() {
  echo "[harness] $1" >&2
  return 1
}

harness_config_path() {
  if [[ -n "${HARNESS_CONFIG:-}" ]]; then
    [[ -f "$HARNESS_CONFIG" ]] || { _harness_die "HARNESS_CONFIG set but file missing: $HARNESS_CONFIG"; return 1; }
    echo "$HARNESS_CONFIG"
    return 0
  fi
  if [[ -f "$PWD/harness-config.json" ]]; then
    echo "$PWD/harness-config.json"; return 0
  fi
  if [[ -f "$PWD/.claude/harness-config.json" ]]; then
    echo "$PWD/.claude/harness-config.json"; return 0
  fi
  _harness_die "not in an oskr project; expected harness-config.json at \$PWD or \$PWD/.claude/"
  return 1
}

harness_config_get() {
  local path="$1" cfg
  cfg=$(harness_config_path) || return 1
  jq -er "$path" "$cfg"
}

harness_config_get_array() {
  local path="$1" cfg
  cfg=$(harness_config_path) || return 1
  jq -er "${path}[]" "$cfg"
}
```

**Step 4: Run test to verify it passes**
Run: `tests/scripts/run-tests.sh`
Expected: PASS

**Step 5: Commit**
`add harness-lib config helpers`

---

## Task 4: harness-lib.sh — project / field discovery via gh GraphQL

**Files:**
- Modify: `scripts/harness-lib.sh`
- Create: `tests/scripts/fixtures/gh-project-discovery.json`
- Create: `tests/scripts/test_harness_project_discovery.sh`

**Dependencies:** Task 3.

**Public functions added this task:**
- `harness_project_id` — echoes the Project v2 node ID (e.g. `PVT_kw...`).
- `harness_status_field_id` — echoes the Status single-select field ID.
- `harness_field_id <field_name>` — generic field-ID resolver.

These call `gh api graphql` with the org/repo/project_number from config, parse the response, and cache the result via Task 5's cache layer (added next; this task tests the GraphQL parse path with a `gh` shim).

**Acceptance Criteria:**
- [ ] `Run: bash -n scripts/harness-lib.sh` → `Expected: exit 0`
- [ ] `Run: shellcheck scripts/harness-lib.sh` → `Expected: exit 0`
- [ ] `Run: tests/scripts/run-tests.sh` → `Expected: exit 0` (test_harness_project_discovery.sh passes)
- [ ] With `PATH` prefixed by a `gh` shim returning canned project JSON, `harness_project_id` echoes the fixture's `PVT_*` node ID.
- [ ] With same shim, `harness_status_field_id` echoes the Status field ID.
- [ ] With same shim, `harness_field_id "Priority"` echoes the Priority field ID.

**Step 1: Write the failing test**

`tests/scripts/fixtures/gh-project-discovery.json`:
```json
{
  "data": {
    "repository": {
      "projectV2": {
        "id": "PVT_kwTEST123",
        "fields": {
          "nodes": [
            { "id": "PVTSSF_statusTEST", "name": "Status",
              "options": [
                { "id": "opt-backlog",     "name": "Backlog" },
                { "id": "opt-research",    "name": "Research" },
                { "id": "opt-needs-input", "name": "Needs Input" },
                { "id": "opt-planning",    "name": "Planning" },
                { "id": "opt-approval",    "name": "Approval" },
                { "id": "opt-ready",       "name": "Ready" },
                { "id": "opt-in-progress", "name": "In Progress" },
                { "id": "opt-in-review",   "name": "In Review" },
                { "id": "opt-done",        "name": "Done" }
              ]
            },
            { "id": "PVTSSF_priorityTEST", "name": "Priority", "options": [] }
          ]
        }
      }
    }
  }
}
```

`tests/scripts/test_harness_project_discovery.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/lib/assert.sh"

SHIM_DIR=$(mktemp -d); trap 'rm -rf "$SHIM_DIR"' EXIT
GH_SHIM_CALL_LOG="$SHIM_DIR/gh-calls.log"
GH_SHIM_FIXTURE="$REPO_ROOT/tests/scripts/fixtures/gh-project-discovery.json"
: > "$GH_SHIM_CALL_LOG"

# Install the shim as `gh` on PATH
cp "$SCRIPT_DIR/lib/gh-shim.sh" "$SHIM_DIR/gh"
chmod +x "$SHIM_DIR/gh"

# Use sample config and isolate the cache dir
XDG_CACHE_HOME=$(mktemp -d)

PATH="$SHIM_DIR:$PATH" \
  HARNESS_CONFIG="$REPO_ROOT/tests/scripts/fixtures/harness-config.sample.json" \
  GH_SHIM_CALL_LOG="$GH_SHIM_CALL_LOG" \
  GH_SHIM_FIXTURE="$GH_SHIM_FIXTURE" \
  XDG_CACHE_HOME="$XDG_CACHE_HOME" \
  bash -c "
    source '$REPO_ROOT/scripts/harness-lib.sh'
    [[ \$(harness_project_id) == 'PVT_kwTEST123' ]] || { echo FAIL project_id; exit 1; }
    [[ \$(harness_status_field_id) == 'PVTSSF_statusTEST' ]] || { echo FAIL status_field_id; exit 1; }
    [[ \$(harness_field_id 'Priority') == 'PVTSSF_priorityTEST' ]] || { echo FAIL priority_field_id; exit 1; }
  "

echo "test_harness_project_discovery: PASS"
```

**Step 2: Run test to verify it fails**
Run: `tests/scripts/run-tests.sh`
Expected: FAIL with "harness_project_id: command not found" or equivalent.

**Step 3: Write minimal implementation**

Append to `scripts/harness-lib.sh`:
```bash
# --- Project / field discovery ---------------------------------------------
#
# Note: this layer always hits gh; Task 5's cache layer wraps these via
# _harness_get_discovery() which reads from / writes to disk. Until Task 5
# lands, _harness_discover_raw() is the entry point.

_harness_discover_raw() {
  local owner number repo
  owner=$(harness_config_get '.github.owner') || return 1
  repo=$(harness_config_get '.github.repo')   || return 1
  number=$(harness_config_get '.github.project_number') || return 1

  gh api graphql -f query='
    query($owner: String!, $repo: String!, $number: Int!) {
      repository(owner: $owner, name: $repo) {
        projectV2(number: $number) {
          id
          fields(first: 50) {
            nodes {
              ... on ProjectV2SingleSelectField {
                id name
                options { id name }
              }
              ... on ProjectV2Field { id name }
            }
          }
        }
      }
    }
  ' -F owner="$owner" -F repo="$repo" -F number="$number" 2>/dev/null \
    || { _harness_die "GraphQL discovery failed; try: gh auth status"; return 1; }
}

harness_project_id() {
  _harness_discover_raw | jq -er '.data.repository.projectV2.id'
}

harness_status_field_id() {
  harness_field_id "Status"
}

harness_field_id() {
  local field_name="$1"
  _harness_discover_raw \
    | jq -er --arg n "$field_name" '
        .data.repository.projectV2.fields.nodes[]
        | select(.name == $n) | .id
      '
}
```

Note: the `gh` shim ignores its CLI args entirely and just echoes the fixture, so all three calls during one test invocation re-issue `gh api graphql`. Task 5 introduces the disk cache to make them O(1) after the first call.

**Step 4: Run test to verify it passes**
Run: `tests/scripts/run-tests.sh`
Expected: PASS

**Step 5: Commit**
`add harness-lib project/field discovery`

---

## Task 5: harness-lib.sh — disk-backed discovery cache

**Files:**
- Modify: `scripts/harness-lib.sh`
- Create: `tests/scripts/test_harness_cache.sh`

**Dependencies:** Task 4.

**Public functions added this task:**
- `harness_cache_clear` — removes the cache file for the current project.

**Behavior:** `_harness_get_discovery()` (internal) becomes the cached gateway. It returns cached JSON when present and writes to `${XDG_CACHE_HOME:-$HOME/.cache}/oskr/<project_number>-<owner>-<repo>.json` on first call. `harness_project_id`, `harness_status_field_id`, `harness_field_id` all rewire to call `_harness_get_discovery` instead of `_harness_discover_raw`.

**Acceptance Criteria:**
- [ ] `Run: bash -n scripts/harness-lib.sh` → `Expected: exit 0`
- [ ] `Run: shellcheck scripts/harness-lib.sh` → `Expected: exit 0`
- [ ] `Run: tests/scripts/run-tests.sh` → `Expected: exit 0`
- [ ] Cache hit: after one `harness_project_id` call, three subsequent `harness_field_id` calls in the same shell session produce exactly **one** entry in `GH_SHIM_CALL_LOG` (verifying gh was called only once).
- [ ] `harness_cache_clear` removes the cache file; next call re-fetches (second entry appears in the log).
- [ ] Cache file path is exactly `${XDG_CACHE_HOME}/oskr/<project_number>-<owner>-<repo>.json` when `XDG_CACHE_HOME` is set.

**Step 1: Write the failing test**

`tests/scripts/test_harness_cache.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

SHIM_DIR=$(mktemp -d); CACHE_DIR=$(mktemp -d)
trap 'rm -rf "$SHIM_DIR" "$CACHE_DIR"' EXIT
GH_SHIM_CALL_LOG="$SHIM_DIR/gh-calls.log"
: > "$GH_SHIM_CALL_LOG"
cp "$SCRIPT_DIR/lib/gh-shim.sh" "$SHIM_DIR/gh"
chmod +x "$SHIM_DIR/gh"

PATH="$SHIM_DIR:$PATH" \
  HARNESS_CONFIG="$REPO_ROOT/tests/scripts/fixtures/harness-config.sample.json" \
  GH_SHIM_CALL_LOG="$GH_SHIM_CALL_LOG" \
  GH_SHIM_FIXTURE="$REPO_ROOT/tests/scripts/fixtures/gh-project-discovery.json" \
  XDG_CACHE_HOME="$CACHE_DIR" \
  bash -c "
    source '$REPO_ROOT/scripts/harness-lib.sh'
    harness_project_id >/dev/null
    harness_status_field_id >/dev/null
    harness_field_id 'Priority' >/dev/null
    [[ \$(wc -l < '$GH_SHIM_CALL_LOG') -eq 1 ]] || { echo FAIL: expected 1 gh call, got \$(wc -l < '$GH_SHIM_CALL_LOG'); exit 1; }
    test -f '$CACHE_DIR/oskr/1-WillyDallas-oskr.json' || { echo FAIL: cache file missing; exit 1; }
    harness_cache_clear
    test ! -f '$CACHE_DIR/oskr/1-WillyDallas-oskr.json' || { echo FAIL: cache_clear did not remove file; exit 1; }
    harness_project_id >/dev/null
    [[ \$(wc -l < '$GH_SHIM_CALL_LOG') -eq 2 ]] || { echo FAIL: expected 2 gh calls after clear, got \$(wc -l < '$GH_SHIM_CALL_LOG'); exit 1; }
  "

echo "test_harness_cache: PASS"
```

**Step 2: Run test to verify it fails**

**Step 3: Write minimal implementation**

Append to `scripts/harness-lib.sh`:
```bash
# --- Discovery cache -------------------------------------------------------

_harness_cache_dir() {
  echo "${XDG_CACHE_HOME:-$HOME/.cache}/oskr"
}

_harness_cache_file() {
  local owner repo number dir
  owner=$(harness_config_get '.github.owner') || return 1
  repo=$(harness_config_get '.github.repo')   || return 1
  number=$(harness_config_get '.github.project_number') || return 1
  dir=$(_harness_cache_dir)
  echo "$dir/${number}-${owner}-${repo}.json"
}

_harness_get_discovery() {
  local f
  f=$(_harness_cache_file) || return 1
  if [[ -f "$f" ]]; then
    cat "$f"
    return 0
  fi
  mkdir -p "$(dirname "$f")"
  local raw
  raw=$(_harness_discover_raw) || return 1
  printf '%s' "$raw" > "$f"
  printf '%s' "$raw"
}

harness_cache_clear() {
  local f
  f=$(_harness_cache_file) || return 1
  rm -f "$f"
}
```

Now **rewire** `harness_project_id` and `harness_field_id` to call `_harness_get_discovery` instead of `_harness_discover_raw`:
```bash
harness_project_id() {
  _harness_get_discovery | jq -er '.data.repository.projectV2.id'
}

harness_field_id() {
  local field_name="$1"
  _harness_get_discovery \
    | jq -er --arg n "$field_name" '
        .data.repository.projectV2.fields.nodes[]
        | select(.name == $n) | .id
      '
}
```

**Step 4: Run test to verify it passes**

**Step 5: Commit**
`add harness-lib discovery cache`

---

## Task 6: harness-lib.sh — column resolution with name/slug normalization

**Files:**
- Modify: `scripts/harness-lib.sh`
- Create: `tests/scripts/test_harness_columns.sh`

**Dependencies:** Task 5.

**Public functions added this task:**
- `harness_column_option_id <name_or_slug>` — resolves either `"Planning"` or `"planning"` to its option UUID. Honors `workflow.column_names` aliases from config.
- `harness_column_name_for <option_uuid>` — reverse lookup; replaces the case statement at the old `move-issue.sh:33-38`.

**Normalization:** input is lowercased and spaces become underscores (e.g., `"Needs Input"` → `"needs_input"`, `"Needs Developer Input"` → `"needs_developer_input"`). The 9 canonical slugs are:

| Slug | Default display name |
|---|---|
| `backlog` | Backlog |
| `research` | Research |
| `needs_input` | Needs Input |
| `planning` | Planning |
| `approval` | Approval |
| `ready` | Ready |
| `in_progress` | In Progress |
| `in_review` | In Review |
| `done` | Done |

Resolution order:
1. Normalize input to slug.
2. If `workflow.column_names[<slug>]` is set in config, use that as the GraphQL `name` to match against.
3. Otherwise use the canonical default name for that slug.
4. Look up by `name` in cached options. If no match, lazy-refresh cache once (covers the "option renamed on the board" case) and retry.
5. If still no match, die with the list of available column names.

**Acceptance Criteria:**
- [ ] `Run: bash -n scripts/harness-lib.sh` → `Expected: exit 0`
- [ ] `Run: shellcheck scripts/harness-lib.sh` → `Expected: exit 0`
- [ ] `Run: tests/scripts/run-tests.sh` → `Expected: exit 0`
- [ ] `harness_column_option_id "Planning"` and `harness_column_option_id "planning"` both echo `"opt-planning"` against the sample fixture.
- [ ] `harness_column_option_id "Needs Input"` and `harness_column_option_id "needs_input"` both echo `"opt-needs-input"`.
- [ ] With `harness-config.with-aliases.json` (which renames `needs_input` → `"Needs Developer Input"`), the fixture lookup correctly resolves through the alias map (test uses a discovery fixture that includes a column literally named `"Needs Developer Input"`).
- [ ] Unknown column dies with a list: `harness_column_option_id "Nonsense"` exits non-zero and stderr contains both `"unknown column"` and at least one of the canonical names.
- [ ] `harness_column_name_for "opt-planning"` echoes `"Planning"` (the display name from cache).

**Step 1: Write the failing test**

Add a second discovery fixture for the aliased case:

`tests/scripts/fixtures/gh-project-discovery-aliased.json`: same as `gh-project-discovery.json` but with the Status option `"Needs Input"` renamed to `"Needs Developer Input"`.

`tests/scripts/test_harness_columns.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

SHIM_DIR=$(mktemp -d); CACHE_DIR=$(mktemp -d)
trap 'rm -rf "$SHIM_DIR" "$CACHE_DIR"' EXIT
GH_SHIM_CALL_LOG="$SHIM_DIR/gh-calls.log"
: > "$GH_SHIM_CALL_LOG"
cp "$SCRIPT_DIR/lib/gh-shim.sh" "$SHIM_DIR/gh"
chmod +x "$SHIM_DIR/gh"

# Default-names case
PATH="$SHIM_DIR:$PATH" \
  HARNESS_CONFIG="$REPO_ROOT/tests/scripts/fixtures/harness-config.sample.json" \
  GH_SHIM_CALL_LOG="$GH_SHIM_CALL_LOG" \
  GH_SHIM_FIXTURE="$REPO_ROOT/tests/scripts/fixtures/gh-project-discovery.json" \
  XDG_CACHE_HOME="$CACHE_DIR" \
  bash -c "
    source '$REPO_ROOT/scripts/harness-lib.sh'
    [[ \$(harness_column_option_id 'Planning') == 'opt-planning' ]] || exit 1
    [[ \$(harness_column_option_id 'planning') == 'opt-planning' ]] || exit 1
    [[ \$(harness_column_option_id 'Needs Input') == 'opt-needs-input' ]] || exit 1
    [[ \$(harness_column_option_id 'needs_input') == 'opt-needs-input' ]] || exit 1
    [[ \$(harness_column_name_for 'opt-planning') == 'Planning' ]] || exit 1
  "

# Unknown column → non-zero + helpful stderr
PATH="$SHIM_DIR:$PATH" \
  HARNESS_CONFIG="$REPO_ROOT/tests/scripts/fixtures/harness-config.sample.json" \
  GH_SHIM_CALL_LOG="$GH_SHIM_CALL_LOG" \
  GH_SHIM_FIXTURE="$REPO_ROOT/tests/scripts/fixtures/gh-project-discovery.json" \
  XDG_CACHE_HOME="$CACHE_DIR" \
  bash -c "source '$REPO_ROOT/scripts/harness-lib.sh' && harness_column_option_id 'Nonsense'" 2>&1 \
  | grep -qF "unknown column" || { echo FAIL: unknown column did not surface; exit 1; }

# Aliased case
CACHE_DIR2=$(mktemp -d); trap 'rm -rf "$SHIM_DIR" "$CACHE_DIR" "$CACHE_DIR2"' EXIT
PATH="$SHIM_DIR:$PATH" \
  HARNESS_CONFIG="$REPO_ROOT/tests/scripts/fixtures/harness-config.with-aliases.json" \
  GH_SHIM_CALL_LOG="$GH_SHIM_CALL_LOG" \
  GH_SHIM_FIXTURE="$REPO_ROOT/tests/scripts/fixtures/gh-project-discovery-aliased.json" \
  XDG_CACHE_HOME="$CACHE_DIR2" \
  bash -c "
    source '$REPO_ROOT/scripts/harness-lib.sh'
    [[ \$(harness_column_option_id 'needs_input') == 'opt-needs-input' ]] || { echo FAIL: alias lookup; exit 1; }
    [[ \$(harness_column_option_id 'Needs Developer Input') == 'opt-needs-input' ]] || { echo FAIL: alias literal lookup; exit 1; }
  "

echo "test_harness_columns: PASS"
```

**Step 2: Run test to verify it fails**

**Step 3: Write minimal implementation**

Append to `scripts/harness-lib.sh`:
```bash
# --- Column resolution -----------------------------------------------------

_harness_normalize_slug() {
  local s="$1"
  s=$(printf '%s' "$s" | tr '[:upper:]' '[:lower:]' | tr ' ' '_')
  printf '%s' "$s"
}

# Canonical slug → default display name
_harness_default_name_for_slug() {
  case "$1" in
    backlog)     echo "Backlog" ;;
    research)    echo "Research" ;;
    needs_input) echo "Needs Input" ;;
    planning)    echo "Planning" ;;
    approval)    echo "Approval" ;;
    ready)       echo "Ready" ;;
    in_progress) echo "In Progress" ;;
    in_review)   echo "In Review" ;;
    done)        echo "Done" ;;
    *)           return 1 ;;
  esac
}

# Echoes the display name to look up in the GraphQL Status options.
# Honors workflow.column_names[<slug>] aliasing.
_harness_display_name_for() {
  local input="$1" slug cfg alias
  slug=$(_harness_normalize_slug "$input")
  cfg=$(harness_config_path) || return 1
  alias=$(jq -r --arg s "$slug" '.workflow.column_names[$s] // ""' "$cfg")
  if [[ -n "$alias" ]]; then
    printf '%s' "$alias"
    return 0
  fi
  if _harness_default_name_for_slug "$slug" >/dev/null 2>&1; then
    _harness_default_name_for_slug "$slug"
    return 0
  fi
  # input was neither a recognized slug nor a defined alias key — pass through
  # in case it's a literal display name typed by the caller (e.g. "Needs Developer Input").
  printf '%s' "$input"
}

_harness_status_options_json() {
  _harness_get_discovery \
    | jq -c '
        .data.repository.projectV2.fields.nodes[]
        | select(.name == "Status") | .options
      '
}

harness_column_option_id() {
  local input="$1" display options uuid
  display=$(_harness_display_name_for "$input") || return 1
  options=$(_harness_status_options_json) || return 1
  uuid=$(printf '%s' "$options" | jq -r --arg n "$display" '.[] | select(.name == $n) | .id')

  if [[ -z "$uuid" ]]; then
    # lazy re-discover once
    harness_cache_clear
    options=$(_harness_status_options_json) || return 1
    uuid=$(printf '%s' "$options" | jq -r --arg n "$display" '.[] | select(.name == $n) | .id')
  fi

  if [[ -z "$uuid" ]]; then
    local valid
    valid=$(printf '%s' "$options" | jq -r '[.[] | .name] | join(", ")')
    _harness_die "unknown column '$input' (looked up as '$display'); valid: $valid"
    return 1
  fi
  printf '%s' "$uuid"
}

harness_column_name_for() {
  local uuid="$1" options
  options=$(_harness_status_options_json) || return 1
  printf '%s' "$options" | jq -er --arg id "$uuid" '.[] | select(.id == $id) | .name'
}
```

**Step 4: Run test to verify it passes**

**Step 5: Commit**
`add harness-lib column resolution`

---

## Task 7: harness-lib.sh — `harness_move_issue` compound op

**Files:**
- Modify: `scripts/harness-lib.sh`
- Create: `tests/scripts/test_harness_move_issue.sh`

**Dependencies:** Task 6.

**Public functions added this task:**
- `harness_move_issue <item_id> <column_name_or_slug>` — resolves project/field/option IDs and runs the `updateProjectV2ItemFieldValue` mutation.

**Acceptance Criteria:**
- [ ] `Run: bash -n scripts/harness-lib.sh` → `Expected: exit 0`
- [ ] `Run: shellcheck scripts/harness-lib.sh` → `Expected: exit 0`
- [ ] `Run: tests/scripts/run-tests.sh` → `Expected: exit 0`
- [ ] When the `gh` shim is configured to record-and-echo, `harness_move_issue "PVTI_test" "Planning"` writes one log line containing `updateProjectV2ItemFieldValue` (the mutation query) to `GH_SHIM_CALL_LOG`.
- [ ] The shim log shows the mutation was called with the resolved Status option UUID for Planning (`opt-planning`).

**Step 1: Write the failing test**

The shim needs an upgrade for this task — it now returns the discovery fixture for the first call (the discovery query) and an empty success blob for the mutation. Easiest path: switch the shim to a script that inspects `$@` for the query name and picks an appropriate fixture file. Update `tests/scripts/lib/gh-shim.sh` to:

```bash
#!/usr/bin/env bash
: "${GH_SHIM_FIXTURE:?GH_SHIM_FIXTURE not set}"
: "${GH_SHIM_CALL_LOG:?GH_SHIM_CALL_LOG not set}"
echo "$*" >> "$GH_SHIM_CALL_LOG"
# All-args fan-in: if any arg mentions 'updateProjectV2ItemFieldValue', return success blob.
for a in "$@"; do
  if [[ "$a" == *"updateProjectV2ItemFieldValue"* ]]; then
    echo '{"data":{"updateProjectV2ItemFieldValue":{"projectV2Item":{"id":"PVTI_test"}}}}'
    exit 0
  fi
done
cat "$GH_SHIM_FIXTURE"
```

`tests/scripts/test_harness_move_issue.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

SHIM_DIR=$(mktemp -d); CACHE_DIR=$(mktemp -d)
trap 'rm -rf "$SHIM_DIR" "$CACHE_DIR"' EXIT
GH_SHIM_CALL_LOG="$SHIM_DIR/gh-calls.log"
: > "$GH_SHIM_CALL_LOG"
cp "$SCRIPT_DIR/lib/gh-shim.sh" "$SHIM_DIR/gh"
chmod +x "$SHIM_DIR/gh"

PATH="$SHIM_DIR:$PATH" \
  HARNESS_CONFIG="$REPO_ROOT/tests/scripts/fixtures/harness-config.sample.json" \
  GH_SHIM_CALL_LOG="$GH_SHIM_CALL_LOG" \
  GH_SHIM_FIXTURE="$REPO_ROOT/tests/scripts/fixtures/gh-project-discovery.json" \
  XDG_CACHE_HOME="$CACHE_DIR" \
  bash -c "
    source '$REPO_ROOT/scripts/harness-lib.sh'
    harness_move_issue 'PVTI_test' 'Planning' >/dev/null
  "

grep -qF 'updateProjectV2ItemFieldValue' "$GH_SHIM_CALL_LOG" || { echo FAIL: mutation not invoked; exit 1; }
grep -qF 'opt-planning' "$GH_SHIM_CALL_LOG" || { echo FAIL: planning option UUID not in mutation call; exit 1; }

echo "test_harness_move_issue: PASS"
```

**Step 2: Run test to verify it fails**

**Step 3: Write minimal implementation**

Append to `scripts/harness-lib.sh`:
```bash
# --- Compound operations ---------------------------------------------------

harness_move_issue() {
  local item_id="$1" column="$2"
  local project_id field_id option_id
  project_id=$(harness_project_id) || return 1
  field_id=$(harness_status_field_id) || return 1
  option_id=$(harness_column_option_id "$column") || return 1

  gh api graphql -f query='
    mutation($project: ID!, $item: ID!, $field: ID!, $value: String!) {
      updateProjectV2ItemFieldValue(input: {
        projectId: $project
        itemId: $item
        fieldId: $field
        value: { singleSelectOptionId: $value }
      }) {
        projectV2Item { id }
      }
    }
  ' -f project="$project_id" -f item="$item_id" -f field="$field_id" -f value="$option_id"
}
```

**Step 4: Run test to verify it passes**

**Step 5: Commit**
`add harness-lib harness_move_issue`

---

## Task 8: Port `move-issue.sh` (column-name CLI surface)

**Files:**
- Create: `scripts/move-issue.sh`
- Create: `tests/scripts/test_move_issue.sh`

**Dependencies:** Task 7.

**Behavior changes from Wonderloom version:**
- CLI: `move-issue.sh <ITEM_ID> <COLUMN_NAME>` (was `<ITEM_ID> <STATUS_OPTION_ID>`)
- Drops `source board-constants.sh` entirely; uses `harness-lib.sh`.
- Reverse-lookup case statement at old line 33-38 disappears: trigger slug is derived directly from the input column name via `_harness_normalize_slug`.
- Token-report integration **remains in place** with the same env-var contract (`HARNESS_ISSUE_NUMBER`, `HARNESS_TRIGGER_SLUG`, `HARNESS_TOKEN_REPORT`). The script gates the call on `[[ -x "$(dirname "$0")/token-report.sh" ]]` so it's a no-op until token-report ships in oskr#3.

**Acceptance Criteria:**
- [ ] `Run: bash -n scripts/move-issue.sh` → `Expected: exit 0`
- [ ] `Run: shellcheck scripts/move-issue.sh` → `Expected: exit 0`
- [ ] `Run: ! grep -qF 'board-constants.sh' scripts/move-issue.sh` → `Expected: exit 0` (board-constants reference eliminated)
- [ ] `Run: grep -qF 'harness-lib.sh' scripts/move-issue.sh` → `Expected: exit 0`
- [ ] `Run: tests/scripts/run-tests.sh` → `Expected: exit 0`
- [ ] Test exercises end-to-end via shim: `./scripts/move-issue.sh "PVTI_test" "Planning"` invokes the mutation with `opt-planning`.

**Step 1: Write the failing test**

`tests/scripts/test_move_issue.sh` mirrors `test_harness_move_issue.sh` but invokes `scripts/move-issue.sh` as a subprocess and checks the same shim log assertions.

**Step 2: Run test to verify it fails**

**Step 3: Write minimal implementation**

```bash
#!/usr/bin/env bash
# Moves a GitHub Project item to a new status column.
# Usage: ./scripts/move-issue.sh <ITEM_ID> <COLUMN_NAME>
# Example: ./scripts/move-issue.sh "PVTI_abc123" "Planning"
#
# Optional env (token-report integration):
#   HARNESS_ISSUE_NUMBER  — issue number being moved
#   HARNESS_TRIGGER_SLUG  — overrides slug derivation
#   HARNESS_TOKEN_REPORT  — "off" to skip the reporter entirely

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/harness-lib.sh"

ITEM_ID="${1:?usage: move-issue.sh <ITEM_ID> <COLUMN_NAME>}"
COLUMN="${2:?usage: move-issue.sh <ITEM_ID> <COLUMN_NAME>}"

# Token report — fire before the move so it lands in the source column.
TOKEN_REPORT_SCRIPT="$SCRIPT_DIR/token-report.sh"
if [[ "${HARNESS_TOKEN_REPORT:-on}" != "off" && -x "$TOKEN_REPORT_SCRIPT" ]]; then
  ISSUE_NUM="${HARNESS_ISSUE_NUMBER:-}"
  TRIGGER_SLUG="${HARNESS_TRIGGER_SLUG:-}"

  if [[ -z "$ISSUE_NUM" ]]; then
    ISSUE_NUM=$(gh api graphql -f query='query($id: ID!) { node(id: $id) { ... on ProjectV2Item { content { ... on Issue { number } } } } }' \
      -F id="$ITEM_ID" --jq '.data.node.content.number' 2>/dev/null || true)
  fi

  if [[ -z "$TRIGGER_SLUG" ]]; then
    slug=$(printf '%s' "$COLUMN" | tr '[:upper:]' '[:lower:]' | tr ' ' '_')
    case "$slug" in
      needs_input|approval|in_review) TRIGGER_SLUG="$slug" ;;
      *) TRIGGER_SLUG="" ;;
    esac
  fi

  if [[ -n "$ISSUE_NUM" && -n "$TRIGGER_SLUG" ]]; then
    "$TOKEN_REPORT_SCRIPT" --issue "$ISSUE_NUM" --trigger "$TRIGGER_SLUG" || true
  fi
fi

harness_move_issue "$ITEM_ID" "$COLUMN"
```

**Step 4: Run test to verify it passes**

**Step 5: Commit**
`port move-issue.sh to harness-lib`

---

## Task 9: Port `check-budget.sh` (Wonderloom-clean copy)

**Files:**
- Create: `scripts/check-budget.sh`

**Dependencies:** none (does not call into harness-lib; it's a self-contained ccburn helper).

**Notes:** This is a near-verbatim port. The Wonderloom version has zero board-constants coupling — it only depends on `ccburn` and `claude`. Copy it as-is. The only deliberate change: remove the `# scripts/check-budget.sh` header path comment if it's stale.

**Acceptance Criteria:**
- [ ] `Run: bash -n scripts/check-budget.sh` → `Expected: exit 0`
- [ ] `Run: shellcheck scripts/check-budget.sh` → `Expected: exit 0`
- [ ] `Run: ! grep -qF 'board-constants.sh' scripts/check-budget.sh` → `Expected: exit 0`
- [ ] `Run: grep -qF 'check_budget()' scripts/check-budget.sh` → `Expected: exit 0`
- [ ] `Run: scripts/check-budget.sh --help` → `Expected: exit 0` and stdout contains `"Sourceable + standalone budget check"`
- [ ] When sourced, exposes `check_budget`: `Run: bash -c "source scripts/check-budget.sh && declare -F check_budget"` → `Expected: exit 0` and stdout contains `"check_budget"`

**Step 1: Verify file absent**
`test ! -f scripts/check-budget.sh && echo OK`

**Step 2: Copy implementation verbatim from Wonderloom**
Source: `/Users/willydallas/WillyDev/story-spark-child/scripts/check-budget.sh` (287 lines, no modifications needed). Copy contents into `scripts/check-budget.sh`.

**Step 3: Run AC verifications**

**Step 4: Commit**
`port check-budget.sh`

---

## Task 10: Port `board-dispatcher.sh` (harness-lib + actionable_columns)

**Files:**
- Create: `scripts/board-dispatcher.sh`
- Create: `tests/scripts/test_board_dispatcher_syntax.sh`

**Dependencies:** Task 7.

**Behavior changes from Wonderloom version:**
1. Drops `source board-constants.sh`; sources `harness-lib.sh` instead.
2. The GraphQL `-F org="Wonderloom-books"` hardcoded value becomes `-F org="$(harness_config_get '.github.owner')"`.
3. The GraphQL query switches from `organization(login: ...)` to `repository(owner: ..., name: ...)` to match the discovery query and avoid the org-vs-user account-type pitfall.
4. The status filter `select(.status.name == "Ready" or "Planning" or "Research")` becomes a dynamic build from `workflow.actionable_columns`:
   ```bash
   ACTIONABLE_NAMES_JSON=$(
     while IFS= read -r slug; do
       _harness_display_name_for "$slug"  # private helper; dispatcher is the only consumer
     done < <(harness_config_get_array '.workflow.actionable_columns') \
       | jq -R . | jq -s .
   )
   ```
   Then in the jq filter: `select(.status.name as $n | $actionable | index($n))`.
5. The "Board constants for move-issue.sh:" footer block in the Claude prompt is removed entirely. The new move-issue.sh takes a column name, so no UUIDs need leaking into the prompt.
6. `has_actionable_work()` is **not in this script** — it stays in `dispatch-loop.sh`. But the equivalent in `board-dispatcher.sh` (the jq filter) must also honor the configured actionable columns.

**No new public function added.** The dispatcher calls the underscore-private `_harness_display_name_for` directly. The public API stays at the 10 functions locked in Q&A; rationale documented in this plan and in `harness-lib.sh`'s header comment.

**Acceptance Criteria:**
- [ ] `Run: bash -n scripts/board-dispatcher.sh` → `Expected: exit 0`
- [ ] `Run: shellcheck scripts/board-dispatcher.sh` → `Expected: exit 0`
- [ ] `Run: ! grep -qF 'board-constants.sh' scripts/board-dispatcher.sh` → `Expected: exit 0`
- [ ] `Run: ! grep -qF 'Wonderloom' scripts/board-dispatcher.sh` → `Expected: exit 0` (no hardcoded org)
- [ ] `Run: grep -qF 'harness-lib.sh' scripts/board-dispatcher.sh` → `Expected: exit 0`
- [ ] `Run: grep -qF 'actionable_columns' scripts/board-dispatcher.sh` → `Expected: exit 0`
- [ ] `Run: ! grep -qF 'Board constants for move-issue.sh' scripts/board-dispatcher.sh` → `Expected: exit 0` (UUID-leak footer eliminated)
- [ ] `Run: ! grep -qF 'harness_column_name_for_slug' scripts/harness-lib.sh` → `Expected: exit 0` (private-only, no public 11th function)
- [ ] `Run: tests/scripts/run-tests.sh` → `Expected: exit 0`

**Step 1: Write the syntax/structure test**
`test_board_dispatcher_syntax.sh` greps for the AC requirements above using `assert_*` helpers. This is a structural test only — exercising the full dispatcher requires Claude + a real board, which is out of scope for unit tests.

**Step 2: Run test to verify it fails**

**Step 3: Port the script**
Use the Wonderloom version as the template; apply changes 1-6 above. Include the `harness_column_name_for_slug` alias addition to `harness-lib.sh`.

**Step 4: Run test to verify it passes**

**Step 5: Commit**
`port board-dispatcher.sh to harness-lib`

---

## Task 11: Port `dispatch-loop.sh` (actionable_columns-aware polling)

**Files:**
- Create: `scripts/dispatch-loop.sh`

**Dependencies:** Tasks 9, 10.

**Testing deferred:** The structural unit test originally scoped here is dropped per developer call — the jq filter behavior in `has_actionable_work` (correctly excluding `loop-skip` labels, correctly counting 0) can only be meaningfully tested against a populated board with actionable items. That coverage rolls into a true e2e test once oskr has its own board populated with seed issues. For this task, the ACs below (bash -n, shellcheck, grep-based structural checks) are sufficient.

**Behavior changes from Wonderloom version:**
1. Drops `source board-constants.sh` (it never had one, but defensive).
2. `has_actionable_work()` switches from hardcoded `--status=Research --status=Planning --status=Ready` to building the list from `workflow.actionable_columns`. Since `board-status.sh` isn't being ported in oskr#1 (out-of-scope), replace the call with a direct GraphQL query that pages the board and counts items whose Status name is in the actionable set and that lack the `loop-skip` label.
3. The `ensure_on_development()` function is **kept as-is** (the base-branch invariant is a harness contract). Plan-reviewer should expect this to read `development` unconditionally — making the base branch configurable is a separate concern (oskr#5 territory).
4. Replace `PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"` semantics with the actual oskr project root. Log path remains `logs/dispatcher.log` relative to PROJECT_DIR.

**Inline `has_actionable_work()` implementation:**
```bash
has_actionable_work() {
  local owner repo number actionable_json count
  owner=$(harness_config_get '.github.owner') || return 1
  repo=$(harness_config_get '.github.repo') || return 1
  number=$(harness_config_get '.github.project_number') || return 1
  actionable_json=$(
    while IFS= read -r slug; do
      _harness_display_name_for "$slug"
    done < <(harness_config_get_array '.workflow.actionable_columns') \
      | jq -R . | jq -sc .
  )
  count=$(gh api graphql -f query='
    query($owner: String!, $repo: String!, $number: Int!) {
      repository(owner: $owner, name: $repo) {
        projectV2(number: $number) {
          items(first: 100) {
            nodes {
              status: fieldValueByName(name: "Status") {
                ... on ProjectV2ItemFieldSingleSelectValue { name }
              }
              content {
                ... on Issue {
                  labels(first: 10) { nodes { name } }
                }
              }
            }
          }
        }
      }
    }
  ' -F owner="$owner" -F repo="$repo" -F number="$number" 2>/dev/null \
    | jq --argjson actionable "$actionable_json" '
        [.data.repository.projectV2.items.nodes[]
          | select(.status.name as $n | $actionable | index($n))
          | select(((.content.labels.nodes // []) | map(.name) | index("loop-skip")) | not)
        ] | length
      ' 2>/dev/null || echo "0")
  [[ "$count" -gt 0 ]]
}
```

(Pagination is intentionally not implemented for the count check — first 100 is enough; a board with >100 actionable items would already be in trouble. If we hit that, follow-on issue.)

**Acceptance Criteria:**
- [ ] `Run: bash -n scripts/dispatch-loop.sh` → `Expected: exit 0`
- [ ] `Run: shellcheck scripts/dispatch-loop.sh` → `Expected: exit 0`
- [ ] `Run: ! grep -qF 'board-constants.sh' scripts/dispatch-loop.sh` → `Expected: exit 0`
- [ ] `Run: ! grep -qE -- '--status=(Research|Planning|Ready)' scripts/dispatch-loop.sh` → `Expected: exit 0` (no hardcoded column set)
- [ ] `Run: grep -qF 'actionable_columns' scripts/dispatch-loop.sh` → `Expected: exit 0`
- [ ] `Run: grep -qF 'ensure_on_development' scripts/dispatch-loop.sh` → `Expected: exit 0` (invariant preserved)
- [ ] `Run: grep -qF 'check_budget' scripts/dispatch-loop.sh` → `Expected: exit 0`
- [ ] `Run: tests/scripts/run-tests.sh` → `Expected: exit 0`

**Step 1: Port the script**
Use the Wonderloom version as template; apply changes 1-4 above.

**Step 2: Run ACs**
`bash -n`, `shellcheck`, and each grep AC must pass.

**Step 3: Commit**
`port dispatch-loop.sh to harness-lib`

---

## Task 12: Verify board-constants.sh is absent (deliberate negative AC)

**Files:** none.

**Dependencies:** Tasks 8, 10, 11.

**Acceptance Criteria:**
- [ ] `Run: test ! -f scripts/board-constants.sh && echo OK` → `Expected: stdout = "OK"`
- [ ] `Run: ! grep -rF 'board-constants.sh' scripts/` → `Expected: exit 0` (no script references the eliminated file)
- [ ] `Run: ! grep -rE 'PVTSSF_lA|PVT_kwDOD' scripts/` → `Expected: exit 0` (no Wonderloom-specific node IDs leaked into oskr scripts)

**Step 1-3: Run the negative ACs. Any failure means a prior task left dangling references.**

**Step 4: Commit (if changes needed to make ACs pass)**
`scrub board-constants references`

---

## Task 13: Live smoke test — `harness_move_issue` round trip against the real oskr board

**Files:**
- Create: `harness-config.json` (at oskr repo root — for the first time; oskr becomes its own consumer)
- Create: `scripts/smoke/round-trip-move.sh`

**Dependencies:** Task 12.

**Note on the project's harness-config.json:** this is also the deliverable that turns oskr into an oskr consumer. The file values come from the real `WillyDallas/oskr` Project v2 board.

**Behavior:** the smoke script picks a sandbox issue (oskr#1 itself is a fine candidate — it's already on the board), records its current Status, moves it to `"Backlog"`, asserts the move took effect via a follow-up query, and moves it back to the original column. Idempotent and reversible.

**Manual gate:** the developer runs this once locally. CI integration is out of scope.

**Acceptance Criteria:**
- [ ] `Run: test -f harness-config.json && jq -e '.github.owner == "WillyDallas" and .github.repo == "oskr"' harness-config.json` → `Expected: exit 0`
- [ ] `Run: bash -n scripts/smoke/round-trip-move.sh` → `Expected: exit 0`
- [ ] `Run: shellcheck scripts/smoke/round-trip-move.sh` → `Expected: exit 0`
- [ ] **Manual:** `Run: scripts/smoke/round-trip-move.sh <issue_item_id>` → `Expected: exit 0` with stdout containing `"round-trip: PASS"`. (Documented as manual because it requires gh auth.)

**Step 1: Create harness-config.json**

Values populated from the real board. Use a placeholder for `project_number` and instruct the developer to fill in via `gh api graphql` discovery during the smoke run if unknown:

```json
{
  "name": "oskr",
  "github": {
    "owner": "WillyDallas",
    "repo": "oskr",
    "project_number": 1
  },
  "workflow": {
    "kind": "gen-eval-9col",
    "column_names": {},
    "actionable_columns": ["needs_input", "approval", "ready", "in_review"]
  },
  "paths": {
    "plans": "docs/plans",
    "research": "docs/research",
    "plan_archive": "docs/_local_archive"
  },
  "agent_context": {
    "project_name": "Oskr",
    "tech_stack": "bash + gh CLI"
  }
}
```

**Step 2: Write the smoke script**

```bash
#!/usr/bin/env bash
# Smoke test: round-trip move on the real oskr Project v2 board.
# Usage: scripts/smoke/round-trip-move.sh <ITEM_ID>
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/harness-lib.sh"

ITEM_ID="${1:?usage: round-trip-move.sh <ITEM_ID>}"

current=$(gh api graphql -f query='
  query($id: ID!) {
    node(id: $id) {
      ... on ProjectV2Item {
        status: fieldValueByName(name: "Status") {
          ... on ProjectV2ItemFieldSingleSelectValue { name }
        }
      }
    }
  }
' -F id="$ITEM_ID" --jq '.data.node.status.name')

echo "round-trip: current column = $current"

echo "round-trip: moving to Backlog"
harness_move_issue "$ITEM_ID" "Backlog" >/dev/null

after=$(gh api graphql -f query='
  query($id: ID!) {
    node(id: $id) {
      ... on ProjectV2Item {
        status: fieldValueByName(name: "Status") {
          ... on ProjectV2ItemFieldSingleSelectValue { name }
        }
      }
    }
  }
' -F id="$ITEM_ID" --jq '.data.node.status.name')

if [[ "$after" != "Backlog" ]]; then
  echo "round-trip: FAIL — expected Backlog, got $after"
  exit 1
fi

echo "round-trip: moving back to $current"
harness_move_issue "$ITEM_ID" "$current" >/dev/null

echo "round-trip: PASS"
```

**Step 3: Document the manual run**

Add a one-paragraph note in the plan body (already here) — no separate doc file.

**Step 4: Commit**
`add harness-config.json and round-trip smoke test`

---

## Cross-task dependency graph

```
Task 1 (fixtures)
  └── Task 2 (test runner)
        └── Task 3 (config helpers)
              └── Task 4 (discovery)
                    └── Task 5 (cache)
                          └── Task 6 (columns)
                                └── Task 7 (move_issue lib fn)
                                      ├── Task 8 (move-issue.sh)
                                      └── Task 10 (board-dispatcher.sh)
                                            └── Task 11 (dispatch-loop.sh; also blocks on Task 9)
                                                  └── Task 12 (negative ACs)
                                                        └── Task 13 (live smoke)
Task 9 (check-budget.sh) — independent; blocks Task 11
```

## Risk register (read this before starting)

1. **macOS bash 3.2 vs bash 4+ syntax.** The plan uses only bash 3.2-compatible constructs (no `${var,,}`, no associative arrays). The test runner runs under whatever `bash` is on PATH; if a developer's PATH points to bash 5 via brew, fine — but the scripts themselves must run under `/bin/bash` 3.2.
2. **`gh api graphql` org-vs-user account types.** Wonderloom uses `organization(login:)`; oskr is a user repo (`WillyDallas/oskr`). The discovery query in Task 4 uses `repository(owner:, name:)` which works for both. The board-dispatcher port in Task 10 makes the same switch.
3. **`shellcheck` may not be installed.** ACs assume it's present. If a developer's machine lacks it, install via `brew install shellcheck` before starting Task 2. Add a one-line prereq note at the top of `tests/scripts/run-tests.sh` that checks `command -v shellcheck` and skips with a warning if absent (don't fail).
4. **Cache invalidation gap.** If GitHub renames a column AND the cache is warm, the first `harness_column_option_id` call after the rename does one wasted GraphQL request before refreshing. Acceptable — column renames are rare and the latency is ~200ms.
5. **Token-report.sh is referenced but doesn't exist.** Task 8 gates the call on `[[ -x ]]` so this is safe. When oskr#3 ships token-report, no change to move-issue.sh is needed.
6. **Smoke test (Task 13) is gh-auth dependent.** It cannot run in CI without secrets. Documented as manual — the planner accepts this as the right trade-off for a first-code-in-repo issue.
7. **`workflow.column_names` JSON shape.** The schema doc shows it as an object; the plan honors that (jq `--arg s "$slug"` lookups against `.workflow.column_names[$s]`). If the schema later changes to an array of pairs, Task 6 needs revisiting.
