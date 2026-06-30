# Workspace Registry CLI + Relocation Implementation Plan

**Goal:** Move oskr's project registry out of the plugin source into the workspace's `.oskr/registry.json`, behind a small `bin/registry.sh` CLI (idempotent `add` / `list` / `migrate`), so the plugin writes no state into its own source tree.
**Architecture:** A new pure-`jq` `bin/registry.sh` sources `harness-lib.sh` and resolves the workspace root via T1's `blacksmith_workspace_dir` (honoring the `OSKR_WORKSPACE` override), then reads/writes `<workspace>/.oskr/registry.json`. Entries carry a `forge` discriminator + a nested per-backend coords block (`github` / `forgejo`) for a mixed-backend workspace. A `migrate` subcommand performs a one-time, idempotent relocation of the legacy `$HOME/WillyDev/oskr/repos/projects.json`, transforming its GitHub-only entries into the new shape. `init`'s Phase 6 is rewired to call the CLI instead of writing into the plugin.
**Tech Stack:** Bash (3.2-compatible), `jq`, the hermetic `tests/scripts/` subshell-fixture harness.
**Issue:** #56 (child of Area #27)

---

## Definition of Done (frozen contract)

1. **Deliverables**
   - Create: `bin/registry.sh` (executable; subcommands `add`, `list`, `migrate`).
   - Modify: `skills/init/SKILL.md` (Phase 6 routes through the CLI; Phase 11 summary references `.oskr/registry.json`; `allowed-tools` gains `Bash(registry.sh*)`).
   - Modify: `repos/projects.example.json` (new forge-tagged, per-backend-coords schema).
   - Modify: `.claude-plugin/plugin.json` (version bump, per the every-PR-bumps convention).
   - Test: `tests/scripts/test_registry_add.sh`, `tests/scripts/test_registry_migrate.sh`, `tests/scripts/test_registry_no_plugin_state.sh`.
2. **Testing tier:** unit / hermetic at the `bin/` verb boundary (subshell + temp-dir fixtures). This is the umbrella's single Named Seam's *pure-resolution* half — registry.sh makes **no** forge calls (pure `jq` over local files), so no `gh-shim`/`curl-shim` replay is needed (the shimmed half is for forge-touching verbs only). Tests follow the `test_harness_cache.sh` / `test_harness_config.sh` subshell-fixture prior art.
3. **Task granularity:** 4 tasks, each ~2-5 min of implementer work.
4. **Verification:** every acceptance criterion below maps to a runnable command (see AC→Test Map). Final gate: `bash tests/scripts/run-tests.sh` exits 0.
5. **Dependencies:** declared explicitly below. The registry tier is **blocked-by T1's `blacksmith_workspace_dir`**, whose name/return-value/env contract is **frozen** in the "Cross-task dependencies" section and **mechanically guarded** at the top of `test_registry_add.sh` so a divergent T1 landing fails at one obvious spot, not across every registry AC.
6. **Issue-specific axes:**
   - Project-tier config resolution is **untouched** — this slice adds a sibling CLI and a `migrate` verb; it does not edit `blacksmith_config_path` or any config getter. `test_harness_config.sh` must remain byte-for-byte passing (verified by the green-suite gate).
   - Statelessness is a *grep-enforced* invariant (`test_registry_no_plugin_state.sh`), not a prose claim. The guard distinguishes **naming** the legacy path (allowed only in `registry.sh`, the migration *source*) from **writing** plugin state (forbidden everywhere) — see Task 3.
   - Migration is hermetic: the legacy source path is overridable via `OSKR_LEGACY_REGISTRY` so tests never read/write the developer's real `$HOME/WillyDev/oskr/repos/projects.json`.

**AC class exemptions (deliberate):**
- **Playwright tier:** N/A — this slice has no UI / navigation / auth surface (a shell CLI + JSON files). No Playwright AC required.
- **Design/quality-rule ACs:** no-op — this repo declares no `.claude/rules/` (verify: `ls .claude/rules 2>/dev/null` → absent).
- **TDD substitution (infra):** Task 3 edits a SKILL.md (prose) and adds a structural grep-guard test, and Task 4 is a config/version bump + suite gate. Those follow the harness-infra *"write acceptance criterion → grep/structural check → implement"* form rather than RED-app-test-first. Tasks 1 and 2 are real RED-first TDD.

---

## Cross-task / cross-issue dependencies

### Blocked-by T1 (`#27` sibling): workspace-root resolver — FROZEN CONTRACT

`bin/registry.sh` consumes one T1 deliverable from `bin/harness-lib.sh`. **This function does not exist in the tree today** (`grep -rn 'blacksmith_workspace_dir\|OSKR_WORKSPACE' .` is empty as of this plan), and PRD line 57 only names it *"e.g. `blacksmith_workspace_dir`"*. Because 4 of 5 issue-level ACs route through it, its contract is **frozen here** and T1 must land conforming to it (or this plan re-plans against the actual name):

| Property | Frozen value |
|---|---|
| **Name** | `blacksmith_workspace_dir` |
| **Return** | echoes the **workspace root** — the directory that *contains* `.oskr/` (NOT the `.oskr/` dir itself) — on stdout, exit 0 |
| **Override** | when `OSKR_WORKSPACE` is set, echoes it verbatim (no filesystem walk) |
| **Failure** | when neither `OSKR_WORKSPACE` nor an upward `.oskr/` walk resolves, dies non-zero with a message on stderr |

**Mechanical guard:** `test_registry_add.sh` (which `run-tests.sh` runs first, alphabetically) asserts this contract before any registry behavior — if T1 landed with a different name, returned the `.oskr/` dir, or ignored `OSKR_WORKSPACE`, the guard fails with `T1 contract not met` instead of every registry AC failing opaquely. **T1 must be merged into the Area branch before T2 executes.** The tests pin `OSKR_WORKSPACE` to a temp dir, so they exercise the override path deterministically regardless of the walk-up internals.

> If the guard fails because T1 chose a different function name, this is a **re-plan** trigger, not an implementer workaround: change the single `blacksmith_workspace_dir` call site in `bin/registry.sh` and the guard, nowhere else (the resolver lives only behind `_registry_oskr_dir`).

### Sequencing constraint (T3 must honor): `migrate` precedes the first `add`

In any workspace that has a legacy registry, **`registry.sh migrate` MUST run before the first `registry.sh add`.** `add` first-creates `registry.json`, and `migrate` no-ops when the target already exists (idempotency) — so an add-before-migrate ordering silently drops the legacy entries `migrate` exists to preserve. T2 *builds and fixture-proves* both verbs but does not wire their invocation order; **T3 (`/oskr-setup`) owns running `migrate` once during workspace bootstrap, ahead of any project `init`.**

### Other handoffs

- **Hands off to T3 (`/oskr-setup`):** T2 *builds and fixture-proves* the `migrate` verb; T3 owns the one-time *invocation* of `registry.sh migrate` during the setup walkthrough (see sequencing constraint above). T2 does not wire the call (avoids scope overlap).
- **Hands off to T4 (`init` v2 backend choice):** T2 wires `init` Phase 6 to call `registry.sh add --forge github …` (GitHub is init's only mode today). T4 parameterizes `--forge` for the backend-choice path.
- **Within-plan ordering:** Task 1 → Task 2 (share `bin/registry.sh`) → Task 3 (consumes the CLI) → Task 4 (suite gate + version bump).

---

## AC → Test Map

| Issue AC | Verification command | Task |
|---|---|---|
| (dep) T1 resolver contract holds: `blacksmith_workspace_dir` defined, honors `OSKR_WORKSPACE`, echoes the workspace root | `bash tests/scripts/test_registry_add.sh` → exit 0 (top-of-file contract guard) | 1 |
| Idempotent `add` + `list`, reading/writing `.oskr/registry.json` under the resolved workspace root | `bash tests/scripts/test_registry_add.sh` → exit 0 | 1 |
| Entries record `forge` + per-backend coordinates (mixed-backend) | `bash tests/scripts/test_registry_add.sh` → exit 0 (asserts `.forge`, `.github.*`, `.forgejo.*`) | 1 |
| Legacy registry migrated idempotently; missing source is a no-op (not an error) | `bash tests/scripts/test_registry_migrate.sh` → exit 0 (present / absent / already-migrated) | 2 |
| No oskr code path writes state into the plugin's own source tree | `bash tests/scripts/test_registry_no_plugin_state.sh` → exit 0 | 3 |
| Hermetic tests cover first-create, idempotent add, list, migration (present/absent/already-migrated) | `bash tests/scripts/run-tests.sh` → exit 0 | 4 |

---

## Task 1: `bin/registry.sh` — workspace resolution + `add` + `list`

**Files:**
- Create: `bin/registry.sh`
- Test: `tests/scripts/test_registry_add.sh`

**Acceptance Criteria:**
- [ ] The T1 resolver contract holds: `blacksmith_workspace_dir` is defined, honors `OSKR_WORKSPACE`, and echoes the workspace root (asserted by the top-of-file contract guard in `test_registry_add.sh`).
- [ ] `registry.sh add` first-creates `<workspace>/.oskr/registry.json` (`{"projects":[]}`) when absent, then appends the entry.
- [ ] `add` is idempotent on `--name`: re-adding the same name is a no-op (no duplicate entry).
- [ ] An entry records `forge` plus a nested per-backend coords block (`github`:{owner,repo,project_number} or `forgejo`:{base_url,owner,repo}).
- [ ] `list` echoes the `.projects` array as JSON.
- [ ] Workspace root is resolved via `blacksmith_workspace_dir` (honoring `OSKR_WORKSPACE`).
- [ ] `bash tests/scripts/test_registry_add.sh` passes.

**Step 1: Write the failing test**

Create `tests/scripts/test_registry_add.sh`:

```bash
#!/usr/bin/env bash
# registry.sh add/list: workspace-rooted .oskr/registry.json. Covers first-create,
# idempotent add (no dup by name), list, and forge + per-backend coords (mixed
# backend). Pure subshell-fixture style — no forge shim (registry.sh makes no
# forge calls). OSKR_WORKSPACE pins resolution to a temp workspace.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"

WS=$(mktemp -d)
trap 'rm -rf "$WS"' EXIT
mkdir -p "$WS/.oskr"
REG="$WS/.oskr/registry.json"
run() { OSKR_WORKSPACE="$WS" bash "$REPO_ROOT/bin/registry.sh" "$@"; }

# --- T1 contract guard (frozen dependency) ---------------------------------
# This registry tier is BLOCKED-BY T1's workspace resolver. Assert T1's frozen
# contract up front so a divergent landing fails HERE (one obvious spot) instead
# of mechanically across every registry AC:
#   blacksmith_workspace_dir -> echoes the WORKSPACE ROOT (the dir CONTAINING
#   .oskr/, not .oskr/ itself) on stdout, exit 0; honors $OSKR_WORKSPACE as an
#   override; dies non-zero when neither resolves.
ws_resolved=$(OSKR_WORKSPACE="$WS" bash -c "source '$REPO_ROOT/bin/harness-lib.sh' && blacksmith_workspace_dir") \
  || { echo "FAIL: blacksmith_workspace_dir undefined or errored — T1 contract not met; STOP and reconcile with T1" >&2; exit 1; }
assert_eq "$WS" "$ws_resolved" "blacksmith_workspace_dir echoes the workspace root and honors OSKR_WORKSPACE" || exit 1

# First-create: registry.json absent -> add creates it with exactly one entry.
[[ ! -f "$REG" ]] || { echo "FAIL: registry.json should not exist yet" >&2; exit 1; }
run add --name oskr --path /ws/projects/oskr --forge github \
    --owner WillyDallas --repo oskr --project-number 5
[[ -f "$REG" ]] || { echo "FAIL: add did not create registry.json" >&2; exit 1; }
assert_eq '1' "$(jq '.projects | length' "$REG")" "first add => 1 entry" || exit 1

# Entry carries forge + per-backend coords.
assert_eq 'github'      "$(jq -r '.projects[0].forge' "$REG")"                "forge recorded" || exit 1
assert_eq 'WillyDallas' "$(jq -r '.projects[0].github.owner' "$REG")"         "github.owner" || exit 1
assert_eq 'oskr'        "$(jq -r '.projects[0].github.repo' "$REG")"          "github.repo" || exit 1
assert_eq '5'           "$(jq -r '.projects[0].github.project_number' "$REG")" "github.project_number" || exit 1

# Idempotent add: re-adding the same name is a no-op (still one entry).
run add --name oskr --path /ws/projects/oskr --forge github \
    --owner WillyDallas --repo oskr --project-number 5
assert_eq '1' "$(jq '.projects | length' "$REG")" "re-add same name => still 1 entry" || exit 1

# Mixed backend: a forgejo project records forgejo coords alongside the github one.
run add --name sluice --path /ws/projects/sluice --forge forgejo \
    --base-url https://sluice.example --owner ops --repo sluice
assert_eq '2'       "$(jq '.projects | length' "$REG")"      "second project => 2 entries" || exit 1
assert_eq 'forgejo' "$(jq -r '.projects[1].forge' "$REG")"   "forgejo forge" || exit 1
assert_eq 'https://sluice.example' "$(jq -r '.projects[1].forgejo.base_url' "$REG")" "forgejo.base_url" || exit 1
assert_eq 'ops'     "$(jq -r '.projects[1].forgejo.owner' "$REG")" "forgejo.owner" || exit 1

# list echoes the projects array (2 entries, both names present).
out=$(run list)
assert_eq '2' "$(jq 'length' <<<"$out")" "list => 2 entries" || exit 1
grep -qF '"oskr"'   <<<"$out" || { echo "FAIL: list missing oskr" >&2; exit 1; }
grep -qF '"sluice"' <<<"$out" || { echo "FAIL: list missing sluice" >&2; exit 1; }

echo "test_registry_add: PASS"
```

**Step 2: Run test to verify it fails**

Run: `bash tests/scripts/test_registry_add.sh`
Expected: FAIL — the T1 contract guard passes (T1 is merged), then `run add …` fails with `bin/registry.sh: No such file or directory` (the CLI does not exist yet). *(If the guard itself fails with `T1 contract not met`, T1 has not merged / diverged — stop and reconcile, do not stub the resolver.)*

**Step 3: Write minimal implementation**

Create `bin/registry.sh` (then `chmod +x bin/registry.sh`):

```bash
#!/usr/bin/env bash
# registry.sh — oskr's workspace project registry CLI.
# Reads/writes <workspace>/.oskr/registry.json. The workspace root is resolved by
# the blacksmith resolver (blacksmith_workspace_dir; honors $OSKR_WORKSPACE). State
# lives in the WORKSPACE, never in the plugin source tree.
#
# Subcommands:
#   add     upsert-by-name a managed-project entry (idempotent; no dup by name)
#   list    echo the registry's .projects array (JSON)
#   migrate one-time, idempotent relocation of the legacy in-plugin registry
#
# Pure jq over local files; NO forge (gh/curl) calls — keeps the bin/ seam guard green.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/harness-lib.sh"

# Legacy in-plugin registry SOURCE (overridable so tests stay hermetic). registry.sh
# is the ONLY file allowed to name this path — it READS it to relocate it (migrate),
# and never writes plugin state. The stateless-plugin guard whitelists this file.
LEGACY_REGISTRY="${OSKR_LEGACY_REGISTRY:-$HOME/WillyDev/oskr/repos/projects.json}"

_registry_die() { echo "[registry] $1" >&2; exit 1; }

# Echo the workspace .oskr/ dir (created if missing). Does NOT create registry.json.
# Relies on the frozen T1 contract: blacksmith_workspace_dir echoes the workspace ROOT.
_registry_oskr_dir() {
  local ws
  ws=$(blacksmith_workspace_dir) || return 1
  mkdir -p "$ws/.oskr"
  printf '%s' "$ws/.oskr"
}

# Echo the registry.json path, first-creating an empty registry when absent.
_registry_file() {
  local d f
  d=$(_registry_oskr_dir) || return 1
  f="$d/registry.json"
  [[ -f "$f" ]] || echo '{"projects": []}' > "$f"
  printf '%s' "$f"
}

registry_add() {
  local name="" path="" forge="github"
  local owner="" repo="" project_number="" base_url=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)           name="$2"; shift 2 ;;
      --path)           path="$2"; shift 2 ;;
      --forge)          forge="$2"; shift 2 ;;
      --owner)          owner="$2"; shift 2 ;;
      --repo)           repo="$2"; shift 2 ;;
      --project-number) project_number="$2"; shift 2 ;;
      --base-url)       base_url="$2"; shift 2 ;;
      *) _registry_die "add: unknown flag '$1'" ;;
    esac
  done
  [[ -n "$name" ]] || _registry_die "add: --name required"
  [[ -n "$path" ]] || _registry_die "add: --path required"

  local f; f=$(_registry_file) || exit 1

  # Idempotent: a project with this name already present => no-op (no duplicate).
  if jq -e --arg n "$name" 'any(.projects[]; .name == $n)' "$f" >/dev/null 2>&1; then
    echo "[registry] '$name' already registered; no-op" >&2
    return 0
  fi

  local coords
  case "$forge" in
    github)
      coords=$(jq -nc --arg o "$owner" --arg r "$repo" --argjson pn "${project_number:-0}" \
        '{owner: $o, repo: $r, project_number: $pn}') ;;
    forgejo)
      coords=$(jq -nc --arg b "$base_url" --arg o "$owner" --arg r "$repo" \
        '{base_url: $b, owner: $o, repo: $r}') ;;
    *) _registry_die "add: unknown forge '$forge' (expected github|forgejo)" ;;
  esac

  local entry
  entry=$(jq -nc \
    --arg name "$name" --arg path "$path" --arg forge "$forge" \
    --argjson coords "$coords" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{name: $name, path: $path, forge: $forge} + {($forge): $coords} + {registered_at: $ts}')

  jq --argjson e "$entry" '.projects += [$e]' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}

registry_list() {
  local f; f=$(_registry_file) || exit 1
  jq -c '.projects' "$f"
}

case "${1:-}" in
  add)     shift; registry_add "$@" ;;
  list)    shift; registry_list "$@" ;;
  migrate) shift; registry_migrate "$@" ;;  # defined in Task 2
  *)       _registry_die "usage: registry.sh {add|list|migrate} ..." ;;
esac
```

> Note: the `migrate)` case references `registry_migrate`, added in Task 2. `bash -n` checks syntax only (not undefined functions), so it stays clean; Task 1's tests call only `add`/`list`, so the unreachable `migrate)` arm never trips. Task 2 adds the function body before the seam guard runs in Task 4.

**Step 4: Run test to verify it passes**

Run: `bash tests/scripts/test_registry_add.sh`
Expected: PASS — prints `test_registry_add: PASS`.

**Step 5: Commit**
`feat(registry): add bin/registry.sh add/list over workspace .oskr/registry.json (#56)`

---

## Task 2: `bin/registry.sh migrate` — idempotent legacy relocation

**Files:**
- Modify: `bin/registry.sh` (add `registry_migrate`)
- Test: `tests/scripts/test_registry_migrate.sh`

**Acceptance Criteria:**
- [ ] Source present + target absent → migrates, transforming legacy GitHub-only entries to the new `forge`/`github`-block shape (`owner`/`repo` split from the `"owner/repo"` string; `project_number` preserved).
- [ ] Source absent → no-op, no error, no target created.
- [ ] Target already present → no-op (byte-for-byte unchanged); re-running is safe.
- [ ] Legacy source path is overridable via `OSKR_LEGACY_REGISTRY` (hermetic tests).
- [ ] `bash tests/scripts/test_registry_migrate.sh` passes.

**Step 1: Write the failing test**

Create `tests/scripts/test_registry_migrate.sh`:

```bash
#!/usr/bin/env bash
# registry.sh migrate: one-time, idempotent relocation of the legacy in-plugin
# registry into <workspace>/.oskr/registry.json. Covers present / absent /
# already-migrated. OSKR_LEGACY_REGISTRY overrides the source so the test never
# touches the real $HOME/WillyDev/oskr/repos/projects.json.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"

WS=$(mktemp -d); LEGACY_DIR=$(mktemp -d)
trap 'rm -rf "$WS" "$LEGACY_DIR"' EXIT
mkdir -p "$WS/.oskr"
REG="$WS/.oskr/registry.json"
LEGACY="$LEGACY_DIR/projects.json"
run() { OSKR_WORKSPACE="$WS" OSKR_LEGACY_REGISTRY="$LEGACY" bash "$REPO_ROOT/bin/registry.sh" migrate; }

# Case A: source ABSENT -> no-op, no error, no target created.
run
[[ ! -f "$REG" ]] || { echo "FAIL: migrate created a registry from an absent source" >&2; exit 1; }

# Case B: source PRESENT -> migrate transforms legacy GitHub-only entries.
cat > "$LEGACY" <<'JSON'
{ "projects": [
  { "name": "oskr", "path": "/ws/projects/oskr", "github": "WillyDallas/oskr",
    "project_number": 5, "registered_at": "2026-01-01T00:00:00Z" }
] }
JSON
run
[[ -f "$REG" ]] || { echo "FAIL: migrate did not create the target" >&2; exit 1; }
assert_eq '1'           "$(jq '.projects | length' "$REG")"                    "migrated 1 entry" || exit 1
assert_eq 'github'      "$(jq -r '.projects[0].forge' "$REG")"                 "legacy entry tagged forge=github" || exit 1
assert_eq 'WillyDallas' "$(jq -r '.projects[0].github.owner' "$REG")"          "owner split from github string" || exit 1
assert_eq 'oskr'        "$(jq -r '.projects[0].github.repo' "$REG")"           "repo split from github string" || exit 1
assert_eq '5'           "$(jq -r '.projects[0].github.project_number' "$REG")" "project_number preserved" || exit 1
assert_eq '2026-01-01T00:00:00Z' "$(jq -r '.projects[0].registered_at' "$REG")" "registered_at preserved" || exit 1

# Case C: already migrated -> re-running is a byte-for-byte no-op.
before=$(cat "$REG")
run
assert_eq "$before" "$(cat "$REG")" "re-run is a byte-for-byte no-op" || exit 1

echo "test_registry_migrate: PASS"
```

**Step 2: Run test to verify it fails**

Run: `bash tests/scripts/test_registry_migrate.sh`
Expected: FAIL — `registry_migrate: command not found` (the function is not yet defined; the `migrate)` case calls it).

**Step 3: Write minimal implementation**

Insert `registry_migrate` into `bin/registry.sh`, immediately after `registry_list` (before the `case` dispatcher):

```bash
# One-time, idempotent relocation of the legacy in-plugin registry into the
# workspace. Transforms GitHub-only legacy entries ({github:"owner/repo",
# project_number}) into the forge-tagged shape. No-op when the target already
# exists (already migrated) or the source is absent (nothing to migrate).
# SEQUENCING (T3): this MUST run before the first `add` in a workspace — `add`
# first-creates registry.json, after which this guard short-circuits and the
# legacy entries would be lost.
registry_migrate() {
  local d target
  d=$(_registry_oskr_dir) || exit 1
  target="$d/registry.json"

  if [[ -f "$target" ]]; then
    echo "[registry] already migrated ($target exists); no-op" >&2
    return 0
  fi
  if [[ ! -f "$LEGACY_REGISTRY" ]]; then
    echo "[registry] no legacy registry at $LEGACY_REGISTRY; no-op" >&2
    return 0
  fi

  jq '{projects: [ .projects[] | {
        name,
        path,
        forge: "github",
        github: {
          owner: ((.github // "") | split("/")[0]),
          repo:  ((.github // "") | split("/")[1]),
          project_number: (.project_number // 0)
        },
        registered_at: (.registered_at // "")
      } ]}' "$LEGACY_REGISTRY" > "$target.tmp" && mv "$target.tmp" "$target"
  echo "[registry] migrated $LEGACY_REGISTRY -> $target" >&2
}
```

**Step 4: Run test to verify it passes**

Run: `bash tests/scripts/test_registry_migrate.sh`
Expected: PASS — prints `test_registry_migrate: PASS`.

**Step 5: Commit**
`feat(registry): add idempotent migrate verb relocating the legacy in-plugin registry (#56)`

---

## Task 3: Rewire `init` Phase 6 + stateless-plugin guard + schema doc

**TDD substitution (infra):** this task edits a SKILL.md (prose) and a JSON template, and asserts the statelessness invariant with a structural **grep** test — the harness *"write acceptance criterion → grep/structural check → implement"* form, not an app-level RED test.

**Files:**
- Modify: `skills/init/SKILL.md` (Phase 6 + Phase 11 summary + `allowed-tools`)
- Modify: `repos/projects.example.json`
- Test: `tests/scripts/test_registry_no_plugin_state.sh`

**Acceptance Criteria:**
- [ ] The legacy `$HOME/WillyDev/oskr/repos/projects.json` path appears nowhere in `skills/`, and in `bin/` only inside `registry.sh` (the migration *source*) — guard checks (1a)/(1b). The AC is "no code path **writes** plugin state"; `registry.sh` only **reads** the legacy path to relocate it, so it is whitelisted.
- [ ] `skills/init/SKILL.md` Phase 6 registers via `registry.sh add` (not an inline `jq` write into the plugin) — guard check (2): `grep -qF 'registry.sh add' skills/init/SKILL.md`.
- [ ] `skills/init/SKILL.md` `allowed-tools` permits `Bash(registry.sh*)` — guard check (3): `grep -qF 'Bash(registry.sh' skills/init/SKILL.md`.
- [ ] No dangling `$REGISTRY` reference survives init's user-facing output (Phase 11 summary now points at `.oskr/registry.json`) — guard check (5): `! grep -qF '$REGISTRY' skills/init/SKILL.md`.
- [ ] `repos/projects.example.json` documents the new forge-tagged, per-backend-coords schema and is valid JSON — guard check (4).
- [ ] `bash tests/scripts/test_registry_no_plugin_state.sh` passes.

**Step 1: Write the acceptance-criterion check (the failing guard)**

Create `tests/scripts/test_registry_no_plugin_state.sh`:

```bash
#!/usr/bin/env bash
# Stateless-plugin guard: no executable oskr code path WRITES state into the plugin
# source tree. The legacy in-plugin registry path must not appear in skills/ at all,
# and in bin/ only inside registry.sh (the one-time migration SOURCE — it READS the
# legacy file to relocate it, never writes plugin state). init must register through
# bin/registry.sh and declare it in allowed-tools; no stale $REGISTRY may survive.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# (1a) skills/ must NEVER name the legacy in-plugin registry path. init used to WRITE
#      to it inline — that is the plugin-state leak this slice removes.
if grep -rn 'WillyDev/oskr/repos/projects.json' "$REPO_ROOT/skills" 2>/dev/null; then
  echo "FAIL: legacy in-plugin registry path referenced in skills/ (plugin-state write)" >&2
  exit 1
fi

# (1b) bin/ may name the legacy path ONLY in registry.sh (the migration source). Any
#      OTHER bin script naming it is an init-style write back into the plugin tree.
if grep -rn --exclude=registry.sh 'WillyDev/oskr/repos/projects.json' "$REPO_ROOT/bin" 2>/dev/null; then
  echo "FAIL: legacy in-plugin registry path referenced outside bin/registry.sh" >&2
  exit 1
fi

# (2) init registers through the CLI, not an inline jq write into the plugin.
grep -qF 'registry.sh add' "$REPO_ROOT/skills/init/SKILL.md" \
  || { echo "FAIL: init/SKILL.md does not register via bin/registry.sh" >&2; exit 1; }

# (3) init declares the CLI in allowed-tools.
grep -qF 'Bash(registry.sh' "$REPO_ROOT/skills/init/SKILL.md" \
  || { echo "FAIL: init/SKILL.md allowed-tools does not permit Bash(registry.sh*)" >&2; exit 1; }

# (4) the example schema documents the new shape (forge discriminator) and is valid JSON.
jq -e '.projects[0].forge' "$REPO_ROOT/repos/projects.example.json" >/dev/null \
  || { echo "FAIL: projects.example.json missing forge discriminator" >&2; exit 1; }

# (5) no stale $REGISTRY survives (Phase 6 defined it; Phase 11 echoed it).
if grep -qF '$REGISTRY' "$REPO_ROOT/skills/init/SKILL.md"; then
  echo "FAIL: stale \$REGISTRY reference survives in init/SKILL.md (Phase 11 summary?)" >&2
  exit 1
fi

echo "test_registry_no_plugin_state: PASS"
```

**Step 2: Run the guard to verify it fails**

Run: `bash tests/scripts/test_registry_no_plugin_state.sh`
Expected: FAIL — `skills/init/SKILL.md:327` still defines `REGISTRY="$HOME/WillyDev/oskr/repos/projects.json"`, so check **(1a)** matches and the guard exits 1. *(Note: `bin/registry.sh` from Tasks 1-2 also names the legacy path as its migration source, but check (1b)'s `--exclude=registry.sh` whitelists it — the RED is driven by `skills/`, not `bin/`.)*

**Step 3: Implement the edits**

(a) In `skills/init/SKILL.md`, replace the entire Phase 6 block (the heading through the closing ` ``` ` and the `Registered …` echo — current lines ~322-343) with:

````markdown
## Phase 6: Register in the oskr workspace registry

The registry tracks every project this oskr **workspace** manages. It lives in the
workspace at `<workspace>/.oskr/registry.json`, resolved by `registry.sh` — never in
the plugin source. (The one-time relocation of any legacy in-plugin registry is run by
`/oskr-setup` via `registry.sh migrate`, **before** any project's first `registry.sh add`.)

```bash
registry.sh add \
  --name "$NAME" \
  --path "$CWD" \
  --forge github \
  --owner "$OWNER" \
  --repo "$REPO" \
  --project-number "$PROJECT_NUMBER"

echo "Registered $NAME in the workspace registry (.oskr/registry.json)"
```
````

(b) In `skills/init/SKILL.md` front-matter `allowed-tools` (line 5), add `Bash(registry.sh*)` (drop nothing else):

```
allowed-tools: Bash(gh *) Bash(git *) Bash(mkdir *) Bash(touch *) Bash(jq *) Bash(cat *) Bash(echo *) Bash(test *) Bash(registry.sh*) Bash(find-item.sh*) Bash(move-issue.sh*) Read Write Edit
```

(c) Replace `repos/projects.example.json` with the forge-tagged schema (a GitHub entry and a Forgejo entry, to document the mixed-backend shape):

```json
{
  "projects": [
    {
      "name": "<project-name>",
      "path": "<absolute-path-to-the-project-checkout>",
      "forge": "github",
      "github": {
        "owner": "<owner>",
        "repo": "<repo>",
        "project_number": 0
      },
      "registered_at": "<ISO-8601 timestamp>"
    },
    {
      "name": "<forgejo-project-name>",
      "path": "<absolute-path-to-the-project-checkout>",
      "forge": "forgejo",
      "forgejo": {
        "base_url": "https://forge.example",
        "owner": "<owner>",
        "repo": "<repo>"
      },
      "registered_at": "<ISO-8601 timestamp>"
    }
  ]
}
```

(d) In `skills/init/SKILL.md` Phase 11 (the "Final summary" block, current line 427), the summary line still echoes the now-removed `$REGISTRY` var:

```
> - Registered in: `$REGISTRY`
```

Replace it with a workspace-relative reference (no `$REGISTRY`):

```
> - Registered in: `<workspace>/.oskr/registry.json`
```

This is the edit guard check (5) enforces — leaving line 427 dangling fails the test even though check (1a) would pass.

**Step 4: Run the guard to verify it passes**

Run: `bash tests/scripts/test_registry_no_plugin_state.sh`
Expected: PASS — prints `test_registry_no_plugin_state: PASS`.

Also confirm valid JSON: `jq . repos/projects.example.json >/dev/null` → exit 0.

**Step 5: Commit**
`refactor(init): register through bin/registry.sh; relocate registry state to workspace (#56)`

---

## Task 4: Version bump + green-suite gate

**TDD substitution (infra):** version bump + full-suite verification; no app test.

**Files:**
- Modify: `.claude-plugin/plugin.json`

**Acceptance Criteria:**
- [ ] `.claude-plugin/plugin.json` `version` is bumped `0.3.5` → `0.3.6` (patch — a new internal `bin/` CLI + refactor, not a new skill/agent/command).
- [ ] The seam guard accepts the new script: `bash tests/scripts/test_backend_no_inline_gh.sh` passes (registry.sh is pure `jq`; no inline `gh`/`curl`; `bash -n` clean; `registry_migrate` now defined).
- [ ] Project-tier config resolution is unchanged: `bash tests/scripts/test_harness_config.sh` passes untouched.
- [ ] Full hermetic suite is green: `bash tests/scripts/run-tests.sh` exits 0.

**Step 1: Write the acceptance criterion**
The gate is the existing suite plus the three new tests; no new test file is authored here.

**Step 2: Verify the pre-bump state**
Run: `grep -q '"version": "0.3.5"' .claude-plugin/plugin.json && echo present`
Expected: prints `present`.

**Step 3: Bump the version**
Edit `.claude-plugin/plugin.json` line 4: `"version": "0.3.5",` → `"version": "0.3.6",`.

**Step 4: Run the full gate**
Run: `bash tests/scripts/run-tests.sh`
Expected: PASS — `Results: N/N passed, 0 failed` (includes `test_registry_add`, `test_registry_migrate`, `test_registry_no_plugin_state`, and the untouched `test_harness_config`, `test_backend_no_inline_gh`). The stateless guard passes because check (1b) whitelists `registry.sh`'s migration-source default, so Task 1's literal and Task 3's guard no longer contradict.

Confirm the bump landed: `grep -q '"version": "0.3.6"' .claude-plugin/plugin.json` → exit 0.

**Step 5: Commit**
`chore: bump version 0.3.5 -> 0.3.6 for workspace registry CLI (#56)`

---

## Notes for the implementer

- **T1 is a hard blocker, not a stub target.** `blacksmith_workspace_dir` does not exist in the tree yet. If `test_registry_add.sh`'s contract guard fails with `T1 contract not met`, T1 has not merged (or landed with a different name/return) — **stop and reconcile**, do not re-implement workspace resolution in `registry.sh` (duplicating it is the divergence risk the PRD's "T1 owns the resolver" decision exists to prevent). The only legal fix for a renamed T1 function is the single call site in `_registry_oskr_dir` + the guard.
- **Do not edit `bin/harness-lib.sh`** in this slice. `registry.sh` only *sources* it to call `blacksmith_workspace_dir`.
- **`migrate` before `add`.** In a workspace with a legacy registry, T3 must run `registry.sh migrate` before any `registry.sh add` (init Phase 6). `add` first-creates `registry.json`, after which `migrate` short-circuits and legacy entries are lost. T2 only builds/proves the verbs; it does not own the call order.
- **bash 3.2 safety (macOS):** the implementation avoids empty-array expansion under `set -u`; flag parsing uses positional `shift 2`. Keep `jq -n` for entry construction (no here-string surprises).
- **`registry.sh` must be executable** (`chmod +x bin/registry.sh`) and invoked on `PATH` (bin/ is auto-added while the plugin is enabled), matching how `find-item.sh` is invoked from skills.
- **Hermeticity:** every test pins `OSKR_WORKSPACE` (and `OSKR_LEGACY_REGISTRY` for migrate) to `mktemp -d` dirs with an `EXIT` trap — no test reads or writes the developer's real workspace or `$HOME/WillyDev/...`.
