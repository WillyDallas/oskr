# init v2 — GitHub provisioning + 8-column reshape Implementation Plan

**Goal:** A freshly-`init`'d GitHub project gets the live 8-column board (Backlog · Scoping · Planning · Plan Approval · Ready · In Progress · In Review · Done) provisioned through the board-ops seam, with `actionable_columns` migrated off the retired slugs and the manual "Auto-add to project" workflow instructed-and-verified.
**Architecture:** The 8-column vocabulary becomes a single source of truth in `bin/harness-lib.sh` (`_blacksmith_default_name_for_slug` + `_blacksmith_board_column_slugs`). A new shim-testable provisioning verb `blacksmith_provision_status_columns` augments the project's Status field in place from that list. `skills/init/SKILL.md` stops inlining the 9-column `gh api graphql` mutation and instead sources the blacksmith and calls the verb; it emits live-slug `actionable_columns` and replaces its false auto-add assumption with an instruct-then-verify probe.
**Tech Stack:** bash 3.2+, `gh` CLI (GitHub GraphQL Projects v2), `jq`, the hermetic `tests/scripts/` harness (subshell fixtures + `lib/gh-shim.sh` PATH-boundary replay).
**Issue:** #60 (child of Area #27; realizes #52 for new projects)

---

## Context the implementer must hold

- **The Named Seam** (Area #27): the hermetic `tests/scripts/` harness over the `bin/` shell layer, run by `tests/scripts/run-tests.sh`. Pure functions are subshell+fixture; forge-touching verbs are `lib/gh-shim.sh` PATH-boundary replay. Prior art for this plan: `tests/scripts/test_harness_columns.sh` (vocab) and `tests/scripts/test_blacksmith_create_issue.sh` (gh-shim call-log assertions).
- **Settled decisions honored here:** the 8 columns are `Backlog · Scoping · Planning · Plan Approval · Ready · In Progress · In Review · Done` (add `scoping`, rename `approval`→`plan_approval`, drop `research`+`needs_input`); the `forge` discriminator stays `forge`; provisioning routes through blacksmith verbs "where avoidable"; the auto-add toggle is instruct-and-verify (UI-only); live Forgejo acceptance is Area 5.
- **Deliberate non-changes (surface, do not do):**
  - `workflow.kind` stays `"gen-eval-9col"`. No code reads its value (grep confirms only `bin/smoke/forgejo-roundtrip.sh:30` uses it as a literal string). Renaming it would churn the schema + every fixture + every existing config for zero behavior change, and is outside this task's AC. A repeatable `workflow.kind` is roadmap-line-370 follow-up, not #60.
  - oskr's own `harness-config.json` and the `harness-config.sample.json` / `harness-config.with-aliases.json` fixtures keep their retired-slug `actionable_columns`. T5's AC scopes the `actionable_columns` migration to **the emitted config (init) and the config schema** only; the dogfood-config drift is the broader #52 / board-flow.md "Known drift" note. (After Task 1 the retired slugs in those files resolve to pass-through display names — harmless: no test exercises them, and the autonomous dispatcher is parked.)
  - The Forgejo `list_board` slug loop (`bin/harness-lib.sh:872`) keeps its stale slug list; Forgejo column vocabulary belongs to T8 / Area 5. Verified: no test breaks (the Forgejo fixtures use only live slugs `ready`/`backlog`).
  - The `gh-project-discovery-aliased.json` fixture + the aliased block of `test_harness_columns.sh` stay as-is — they are alias-driven (independent of the vocab) and continue to pass.

- **Harness-infra TDD substitution:** Tasks 1 and 2 are real TDD (RED shell test first). Tasks 3, 4, 5 edit prose/config surfaces (a doc, a skill markdown) — for these the agent rule applies: *write the acceptance criterion → grep/structural check → implement*. This substitution is deliberate and flagged per task. Task 6 is a version bump.

---

## Definition of Done

1. **Deliverables**
   - Modify `bin/harness-lib.sh`: 8-column `_blacksmith_default_name_for_slug`; new `_blacksmith_board_column_slugs`, `_blacksmith_github_color_for_slug`, `_blacksmith_github_status_options_literal`, `_blacksmith_github_provision_status_columns`; new public verb `blacksmith_provision_status_columns`.
   - Create test `tests/scripts/test_blacksmith_provision_columns.sh` + fixture `tests/scripts/fixtures/gh-provision-fields.json`.
   - Modify test `tests/scripts/test_harness_columns.sh` + fixture `tests/scripts/fixtures/gh-project-discovery.json` to the 8-column scheme.
   - Modify `docs/harness-config.schema.md`: `actionable_columns` → live slugs; "canonical 9" → "8".
   - Modify `skills/init/SKILL.md`: provision via the verb (no inline 9-col mutation); 8-column prose; emitted `actionable_columns` → `["scoping", "planning", "ready"]`; smoke moves to a live column; auto-add instruct-and-verify; frontmatter `8-column`; `allowed-tools` source.
   - Modify `.claude-plugin/plugin.json`: patch version bump.
2. **Testing tier:** unit (subshell pure-function) + integration-at-the-verb-boundary (gh-shim PATH replay). Justification: every automatable behavior in this task is a `bin/` verb or a config/doc string; the seam is exactly the `tests/scripts/` harness. The interactive init walkthrough and the live auto-add toggle are out of automated scope (guided checklist) per the Area's Named Seams.
3. **Task granularity:** each task ≤ ~5 min implementer work.
4. **Verification:** every acceptance criterion below is a runnable `Run:`/`Expected:` tuple. Suite-green is the closing gate.
5. **Dependencies:** declared explicitly (see the Dependencies section and per-task notes).

---

## Task 1: 8-column vocabulary + canonical slug-order helper

**Files:**
- Modify: `bin/harness-lib.sh` (`_blacksmith_default_name_for_slug`, lines ~114-128; add `_blacksmith_board_column_slugs`)
- Modify (test): `tests/scripts/test_harness_columns.sh` (default-names block, lines ~8-26)
- Modify (fixture): `tests/scripts/fixtures/gh-project-discovery.json`

**Acceptance Criteria:**
- [ ] `Run: bash tests/scripts/test_harness_columns.sh` → `Expected: exit 0`
- [ ] `Run: bash -c 'source bin/harness-lib.sh && [[ "$(_blacksmith_default_name_for_slug scoping)" == "Scoping" ]]'` → `Expected: exit 0`
- [ ] `Run: bash -c 'source bin/harness-lib.sh && [[ "$(_blacksmith_default_name_for_slug plan_approval)" == "Plan Approval" ]]'` → `Expected: exit 0`
- [ ] `Run: bash -c 'source bin/harness-lib.sh && ! _blacksmith_default_name_for_slug research'` → `Expected: exit 0` (retired slug returns non-zero)
- [ ] `Run: bash -c 'source bin/harness-lib.sh && [[ "$(_blacksmith_board_column_slugs | tr "\n" " ")" == "backlog scoping planning plan_approval ready in_progress in_review done " ]]'` → `Expected: exit 0`
- [ ] `Run: grep -qF 'echo "Scoping"' bin/harness-lib.sh` → `Expected: exit 0`
- [ ] `Run: ! grep -qF 'echo "Research"' bin/harness-lib.sh` → `Expected: exit 0`
- [ ] `Run: ! grep -qF 'echo "Needs Input"' bin/harness-lib.sh` → `Expected: exit 0`
- [ ] `Run: ! grep -qF 'echo "Approval"' bin/harness-lib.sh` → `Expected: exit 0` (the new arm is `echo "Plan Approval"`, which does not contain `echo "Approval"`)

**Step 1: Write the failing test.** Replace the "Default-names case" block of `tests/scripts/test_harness_columns.sh` (the block between the `cp .../gh` install and the "Unknown column" block, ~lines 13-26) with the 8-column assertions, and prepend a pure-vocab block right after `source "$SCRIPT_DIR/lib/assert.sh"` is not used here — keep style consistent with the existing subshell form:

```bash
# Pure vocabulary (8-column scheme; #27 T5) — no shim needed.
bash -c "
  source '$REPO_ROOT/bin/harness-lib.sh'
  [[ \$(_blacksmith_default_name_for_slug backlog)       == 'Backlog' ]]       || exit 1
  [[ \$(_blacksmith_default_name_for_slug scoping)       == 'Scoping' ]]       || exit 1
  [[ \$(_blacksmith_default_name_for_slug plan_approval) == 'Plan Approval' ]] || exit 1
  [[ \$(_blacksmith_default_name_for_slug in_review)     == 'In Review' ]]     || exit 1
  _blacksmith_default_name_for_slug research    && exit 1
  _blacksmith_default_name_for_slug needs_input && exit 1
  _blacksmith_default_name_for_slug approval    && exit 1
  exit 0
"

# Default-names case (8-column board discovery)
PATH="$SHIM_DIR:$PATH" \
  HARNESS_CONFIG="$REPO_ROOT/tests/scripts/fixtures/harness-config.sample.json" \
  GH_SHIM_CALL_LOG="$GH_SHIM_CALL_LOG" \
  GH_SHIM_FIXTURE="$REPO_ROOT/tests/scripts/fixtures/gh-project-discovery.json" \
  XDG_CACHE_HOME="$CACHE_DIR" \
  bash -c "
    source '$REPO_ROOT/bin/harness-lib.sh'
    [[ \$(_blacksmith_github_column_option_id 'Planning')      == 'opt-planning' ]]      || exit 1
    [[ \$(_blacksmith_github_column_option_id 'planning')      == 'opt-planning' ]]      || exit 1
    [[ \$(_blacksmith_github_column_option_id 'Scoping')       == 'opt-scoping' ]]       || exit 1
    [[ \$(_blacksmith_github_column_option_id 'scoping')       == 'opt-scoping' ]]       || exit 1
    [[ \$(_blacksmith_github_column_option_id 'Plan Approval') == 'opt-plan-approval' ]] || exit 1
    [[ \$(_blacksmith_github_column_option_id 'plan_approval') == 'opt-plan-approval' ]] || exit 1
    [[ \$(_blacksmith_github_column_name_for 'opt-planning')   == 'Planning' ]]          || exit 1
  "
```

Leave the existing "Unknown column" and "Aliased case" blocks unchanged.

**Step 2: Run test to verify it fails.**
Run: `bash tests/scripts/test_harness_columns.sh`
Expected: FAIL — the vocab still returns `Needs Input`/`Approval` and does not know `scoping`/`plan_approval`; the discovery fixture has no `Scoping`/`Plan Approval` options.

**Step 3: Write minimal implementation.** In `bin/harness-lib.sh`, replace `_blacksmith_default_name_for_slug` (lines ~115-128) and add the slug-order helper directly below it:

```bash
# Canonical slug → default display name (8-column scheme; #27 T5).
_blacksmith_default_name_for_slug() {
  case "$1" in
    backlog)       echo "Backlog" ;;
    scoping)       echo "Scoping" ;;
    planning)      echo "Planning" ;;
    plan_approval) echo "Plan Approval" ;;
    ready)         echo "Ready" ;;
    in_progress)   echo "In Progress" ;;
    in_review)     echo "In Review" ;;
    done)          echo "Done" ;;
    *)             return 1 ;;
  esac
}

# The canonical board columns in board order — the SINGLE source of truth that kills
# the provisioning-vs-runtime column drift (#52). Provisioning maps each slug to its
# display name via _blacksmith_default_name_for_slug.
_blacksmith_board_column_slugs() {
  printf '%s\n' backlog scoping planning plan_approval ready in_progress in_review done
}
```

Then update the 8 `options` in `tests/scripts/fixtures/gh-project-discovery.json` (keep the project id `PVT_kwTEST123`, the Status field id `PVTSSF_statusTEST`, and the `Priority` field node untouched):

```json
"options": [
  { "id": "opt-backlog",       "name": "Backlog" },
  { "id": "opt-scoping",       "name": "Scoping" },
  { "id": "opt-planning",      "name": "Planning" },
  { "id": "opt-plan-approval", "name": "Plan Approval" },
  { "id": "opt-ready",         "name": "Ready" },
  { "id": "opt-in-progress",   "name": "In Progress" },
  { "id": "opt-in-review",     "name": "In Review" },
  { "id": "opt-done",          "name": "Done" }
]
```

**Step 4: Run test to verify it passes.**
Run: `bash tests/scripts/test_harness_columns.sh`
Expected: PASS (`test_blacksmith_columns: PASS`)
Then guard no regression in the fixture's other consumers:
Run: `bash tests/scripts/test_harness_move_issue.sh && bash tests/scripts/test_move_issue.sh && bash tests/scripts/test_harness_project_discovery.sh`
Expected: exit 0 (these assert `opt-planning` / `PVTSSF_statusTEST` / `PVTSSF_priorityTEST`, all preserved)

**Step 5: Commit.**

---

## Task 2: GitHub status-column provisioning verb (the seam)

**Files:**
- Modify: `bin/harness-lib.sh` (add public verb near the op list ~line 104; add `_blacksmith_github_color_for_slug`, `_blacksmith_github_status_options_literal`, `_blacksmith_github_provision_status_columns` in the GitHub backend section)
- Create (test): `tests/scripts/test_blacksmith_provision_columns.sh`
- Create (fixture): `tests/scripts/fixtures/gh-provision-fields.json`

**Acceptance Criteria:**
- [ ] `Run: bash tests/scripts/test_blacksmith_provision_columns.sh` → `Expected: exit 0`
- [ ] `Run: grep -qF 'blacksmith_provision_status_columns() { _blacksmith_dispatch provision_status_columns' bin/harness-lib.sh` → `Expected: exit 0`
- [ ] `Run: bash -n bin/harness-lib.sh` → `Expected: exit 0`
- [ ] `Run: bash tests/scripts/test_backend_no_inline_gh.sh` → `Expected: exit 0` (the new `gh` calls live inside `harness-lib.sh`, which the guard exempts)

**Depends on:** Task 1 (`_blacksmith_board_column_slugs`, `_blacksmith_default_name_for_slug`).

**Step 1: Write the failing test.** Create `tests/scripts/test_blacksmith_provision_columns.sh`:

```bash
#!/usr/bin/env bash
# blacksmith_provision_status_columns (GitHub, #27 T5): augment the project's Status
# field with the 8 canonical columns through the board-ops seam (shim replay).
# Verifies the mutation carries the live 8 columns, omits the retired 3, and that the
# verb echoes the resulting status field name.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/lib/assert.sh"

SHIM_DIR=$(mktemp -d); trap 'rm -rf "$SHIM_DIR"' EXIT
LOG="$SHIM_DIR/gh-calls.log"; : > "$LOG"
cp "$SCRIPT_DIR/lib/gh-shim.sh" "$SHIM_DIR/gh"; chmod +x "$SHIM_DIR/gh"

out=$(PATH="$SHIM_DIR:$PATH" \
  HARNESS_CONFIG="$REPO_ROOT/tests/scripts/fixtures/harness-config.sample.json" \
  GH_SHIM_CALL_LOG="$LOG" \
  GH_SHIM_FIXTURE="$REPO_ROOT/tests/scripts/fixtures/gh-provision-fields.json" \
  bash -c "source '$REPO_ROOT/bin/harness-lib.sh'; blacksmith_provision_status_columns 'PVT_kwTEST123'")

# Augment path: existing Status field is updated in place and its name echoed.
assert_eq 'Status' "$out" "verb echoes resulting status field name" || exit 1
grep -qF 'updateProjectV2Field' "$LOG" || { echo "FAIL: did not augment the Status field" >&2; exit 1; }

# All 8 live columns are provisioned.
for c in "Backlog" "Scoping" "Planning" "Plan Approval" "Ready" "In Progress" "In Review" "Done"; do
  grep -qF "name: \"$c\"" "$LOG" || { echo "FAIL: column '$c' not provisioned" >&2; exit 1; }
done

# The retired 9-column options are gone. (name: "Plan Approval" does not match name: "Approval".)
for c in "Research" "Needs Input" "Approval"; do
  ! grep -qF "name: \"$c\"" "$LOG" || { echo "FAIL: retired column '$c' still provisioned" >&2; exit 1; }
done

echo "test_blacksmith_provision_columns: PASS"
```

And create the fixture `tests/scripts/fixtures/gh-provision-fields.json` (shaped `.data.node.fields.nodes` so the verb's field-discovery `--jq` resolves the Status id under the shim's default route):

```json
{
  "data": {
    "node": {
      "fields": {
        "nodes": [
          { "id": "PVTSSF_statusTEST",   "name": "Status" },
          { "id": "PVTSSF_priorityTEST", "name": "Priority" }
        ]
      }
    }
  }
}
```

**Step 2: Run test to verify it fails.**
Run: `bash tests/scripts/test_blacksmith_provision_columns.sh`
Expected: FAIL — `blacksmith_provision_status_columns` is undefined → the `bash -c` exits non-zero / `out` is empty.

**Step 3: Write minimal implementation.** In `bin/harness-lib.sh`:

(a) Add the public dispatcher right after `blacksmith_base_branch` (~line 104), with a group comment:

```bash
# Board provisioning (init / setup; #27 T5). Routes through the seam like every op.
blacksmith_provision_status_columns() { _blacksmith_dispatch provision_status_columns "$@"; }
```

(b) Add the GitHub implementation in the GitHub backend section (e.g. just before `# --- Compound operations ---`):

```bash
# --- Board provisioning (init/setup; #27 T5) -------------------------------

# GitHub single-select option color (enum) for a column slug — presentation only.
_blacksmith_github_color_for_slug() {
  case "$1" in
    backlog)       echo GRAY ;;
    scoping)       echo BLUE ;;
    planning)      echo PURPLE ;;
    plan_approval) echo YELLOW ;;
    ready)         echo GREEN ;;
    in_progress)   echo BLUE ;;
    in_review)     echo PURPLE ;;
    done)          echo GREEN ;;
    *)             echo GRAY ;;
  esac
}

# Build the GraphQL singleSelectOptions array literal for the 8 canonical columns,
# from the single-source-of-truth slug list. name+color+description mirror the shape
# GitHub's ProjectV2SingleSelectFieldOptionInput requires.
_blacksmith_github_status_options_literal() {
  local slug name color out=""
  while IFS= read -r slug; do
    name=$(_blacksmith_default_name_for_slug "$slug") || return 1
    color=$(_blacksmith_github_color_for_slug "$slug")
    out+="{ name: \"$name\", color: $color, description: \"\" },"
  done < <(_blacksmith_board_column_slugs)
  printf '[%s]' "${out%,}"
}

# Provision the project's Status single-select field with the 8 canonical columns.
# Augments the existing Status field IN PLACE (id-preserving, no orphaned assignments);
# on failure, creates a separate "Phase" field with the same options. Echoes the
# resulting status field NAME ("Status" | "Phase") so the caller records
# workflow.status_field_name.  provision_status_columns <project_node_id>
_blacksmith_github_provision_status_columns() {
  local project_id="$1" options field_id resp
  [[ -n "$project_id" ]] || { _blacksmith_die "provision_status_columns: project node id required"; return 1; }
  options=$(_blacksmith_github_status_options_literal) || return 1
  # shellcheck disable=SC2016
  field_id=$(gh api graphql -f query='
    query($projectId: ID!) {
      node(id: $projectId) {
        ... on ProjectV2 {
          fields(first: 50) { nodes { ... on ProjectV2SingleSelectField { id name } } }
        }
      }
    }
  ' -f projectId="$project_id" --jq '.data.node.fields.nodes[] | select(.name == "Status") | .id' 2>/dev/null)
  if [[ -n "$field_id" ]]; then
    resp=$(gh api graphql -f query="
      mutation(\$fieldId: ID!) {
        updateProjectV2Field(input: { fieldId: \$fieldId, singleSelectOptions: $options }) {
          projectV2Field { ... on ProjectV2SingleSelectField { id name } }
        }
      }
    " -f fieldId="$field_id" 2>&1)
    grep -q '"errors"' <<<"$resp" || { printf 'Status'; return 0; }
  fi
  gh api graphql -f query="
    mutation(\$projectId: ID!) {
      createProjectV2Field(input: {
        projectId: \$projectId, dataType: SINGLE_SELECT, name: \"Phase\",
        singleSelectOptions: $options
      }) { projectV2Field { ... on ProjectV2SingleSelectField { id name } } }
    }
  " -f projectId="$project_id" >/dev/null 2>&1 \
    || { _blacksmith_die "provision_status_columns: could not augment Status nor create Phase"; return 1; }
  printf 'Phase'
}
```

Note for the implementer: the inner double quotes in `$options` are a literal variable value, so bash does not re-parse them; `\$fieldId`/`\$projectId` escape the shell so GraphQL receives the variables. The shim routes both calls to the default `emit < $GH_SHIM_FIXTURE` — call 1 (`--jq`) extracts the Status id; call 2 (`updateProjectV2Field`, no `--jq`, fixture has no `"errors"`) returns the augment-success path.

**Step 4: Run test to verify it passes.**
Run: `bash tests/scripts/test_blacksmith_provision_columns.sh`
Expected: PASS (`test_blacksmith_provision_columns: PASS`)
Run: `bash tests/scripts/test_backend_no_inline_gh.sh`
Expected: exit 0 (`test_backend_no_inline_gh: PASS`)

**Step 5: Commit.**

---

## Task 3: Migrate `actionable_columns` in the config schema

**Harness-infra (prose/doc) task — TDD substitution: write AC → grep check → implement.**

**Files:**
- Modify: `docs/harness-config.schema.md` (lines ~24-29 `actionable_columns`; line ~56 "canonical 9")

**Acceptance Criteria:**
- [ ] `Run: ! grep -qF '"needs_input"' docs/harness-config.schema.md` → `Expected: exit 0`
- [ ] `Run: ! grep -qF '"approval"' docs/harness-config.schema.md` → `Expected: exit 0`
- [ ] `Run: grep -qF '"scoping"' docs/harness-config.schema.md` → `Expected: exit 0`
- [ ] `Run: grep -qF 'canonical 8' docs/harness-config.schema.md` → `Expected: exit 0`
- [ ] `Run: jq -e '.workflow.actionable_columns' <(sed -n '/^```jsonc/,/^```/p' docs/harness-config.schema.md | sed '1d;$d' | sed 's://.*$::')` → `Expected: exit 0` (the jsonc example still parses with live slugs) — *if the strip proves fiddly, the load-bearing ACs are the four greps above; this parse-check is advisory.*

**Step 1: Write the acceptance criterion.** The four greps above are the contract: no retired slug, `scoping` present, prose says "canonical 8".

**Step 2: Run to confirm RED.**
Run: `! grep -qF '"needs_input"' docs/harness-config.schema.md`
Expected: FAIL (exit 1) — the doc currently lists `"needs_input"`.

**Step 3: Implement.** Replace the `actionable_columns` array in the jsonc block (lines ~24-29) with the live-slug set, matching what init emits (Task 4):

```jsonc
    "actionable_columns": [
      "scoping",
      "planning",
      "ready"
    ]
```

And update the column_names reference prose (line ~56) from `Optional aliases when display names diverge from the canonical 9` to `… diverge from the canonical 8`. (Leave `workflow.kind` as `gen-eval-9col` per the deliberate non-change.)

**Step 4: Verify GREEN.**
Run: `! grep -qF '"needs_input"' docs/harness-config.schema.md && ! grep -qF '"approval"' docs/harness-config.schema.md && grep -qF '"scoping"' docs/harness-config.schema.md && grep -qF 'canonical 8' docs/harness-config.schema.md`
Expected: exit 0

**Step 5: Commit.**

---

## Task 4: init provisions the 8-column board through the verb

**Harness-infra (skill markdown) task — TDD substitution: write AC → grep/structural check → implement.**

**Files:**
- Modify: `skills/init/SKILL.md` — frontmatter (`description` line 3, `allowed-tools` line 5); Phase 4 intro (line ~92); Phase 4c (lines ~132-217); Phase 5 (lines ~280-294); Phase 9 smoke (line ~394)

**Acceptance Criteria:**
- [ ] `Run: grep -qF 'blacksmith_provision_status_columns' skills/init/SKILL.md` → `Expected: exit 0` (provisioning routes through the verb)
- [ ] `Run: ! grep -qF 'updateProjectV2Field' skills/init/SKILL.md` → `Expected: exit 0` (the inline 9-column mutation is gone — it now lives behind the seam)
- [ ] `Run: grep -qF '"actionable_columns": ["scoping", "planning", "ready"]' skills/init/SKILL.md` → `Expected: exit 0`
- [ ] `Run: ! grep -qF '"research", "planning", "ready"' skills/init/SKILL.md` → `Expected: exit 0`
- [ ] `Run: grep -qF 'Backlog, Scoping, Planning, Plan Approval, Ready, In Progress, In Review, Done' skills/init/SKILL.md` → `Expected: exit 0`
- [ ] `Run: ! grep -qF 'Backlog, Research, Needs Input, Planning, Approval' skills/init/SKILL.md` → `Expected: exit 0`
- [ ] `Run: ! grep -qF 'move-issue.sh "$ITEM_ID" "Research"' skills/init/SKILL.md` → `Expected: exit 0` (the Research column no longer exists)
- [ ] `Run: grep -qF 'move-issue.sh "$ITEM_ID" "Scoping"' skills/init/SKILL.md` → `Expected: exit 0`
- [ ] `Run: grep -qF '8-column' skills/init/SKILL.md && ! grep -qF '9-column' skills/init/SKILL.md` → `Expected: exit 0`
- [ ] `Run: grep -qF 'Bash(source' skills/init/SKILL.md` → `Expected: exit 0`

**Depends on:** Task 2 (calls `blacksmith_provision_status_columns`). See cross-issue note re: T4 (#27) under Dependencies.

**Step 1: Write the acceptance criteria.** The greps above are the contract.

**Step 2: Run to confirm RED.**
Run: `grep -qF 'blacksmith_provision_status_columns' skills/init/SKILL.md`
Expected: FAIL (exit 1) — init currently inlines the provisioning mutation.

**Step 3: Implement.**

(a) **Frontmatter.** `description` (line 3): change `9-column` → `8-column`. `allowed-tools` (line 5): append ` Bash(source *)` so the agent may `source` the blacksmith.

(b) **Phase 4 intro** (line ~92): replace `augment the Status field with oskr's 9 columns` → `augment the Status field with oskr's 8 columns`.

(c) **Phase 4c** (lines ~132-217): delete the entire Path 1 / Path 2 inline block (the `STATUS_FIELD_ID` discovery, `updateProjectV2Field`, the `createProjectV2Field "Phase"` fallback, and the `STATUS_PATH_TAKEN` bookkeeping) and replace the whole sub-section with:

```markdown
### Step 4c: Provision the Status columns (through the board-ops seam)

The default Status field has 3 options (Todo, In Progress, Done). oskr needs the 8
columns: Backlog, Scoping, Planning, Plan Approval, Ready, In Progress, In Review, Done.
Provisioning routes through the blacksmith verb so the column set has one source of truth
(no inline 9-column drift — oskr#52).

```bash
source "$CLAUDE_PLUGIN_ROOT/bin/harness-lib.sh"

# Augments the existing Status field in place; falls back to a separate "Phase" field.
# Echoes the resulting status field name ("Status" or "Phase").
STATUS_FIELD_NAME=$(blacksmith_provision_status_columns "$PROJECT_ID")
echo "Status columns provisioned (field: $STATUS_FIELD_NAME)."
```

If it could neither augment Status nor create Phase, the verb exits non-zero — stop and
surface the failure; do not proceed to Phase 5.
```

(d) **Phase 5** (lines ~280-294): swap the `STATUS_PATH_TAKEN`/`"phase"` branch for `STATUS_FIELD_NAME` and migrate `actionable_columns` to live slugs:

```bash
# workflow.status_field_name is only needed when augment fell back to a "Phase" field.
if [[ "$STATUS_FIELD_NAME" != "Status" ]]; then
  WORKFLOW_BLOCK='"workflow": {
    "kind": "gen-eval-9col",
    "column_names": {},
    "status_field_name": "'"$STATUS_FIELD_NAME"'",
    "actionable_columns": ["scoping", "planning", "ready"]
  }'
else
  WORKFLOW_BLOCK='"workflow": {
    "kind": "gen-eval-9col",
    "column_names": {},
    "actionable_columns": ["scoping", "planning", "ready"]
  }'
fi
```

(Leave `kind` as `gen-eval-9col` per the deliberate non-change. The rest of the `cat > harness-config.json` heredoc is unchanged.)

(e) **Phase 9 smoke** (line ~394): change `move-issue.sh "$ITEM_ID" "Research"` → `move-issue.sh "$ITEM_ID" "Scoping"` and the adjacent echo `moved to Research` → `moved to Scoping`.

**Step 4: Verify GREEN.**
Run: `grep -qF 'blacksmith_provision_status_columns' skills/init/SKILL.md && ! grep -qF 'updateProjectV2Field' skills/init/SKILL.md && grep -qF '"actionable_columns": ["scoping", "planning", "ready"]' skills/init/SKILL.md && grep -qF 'move-issue.sh "$ITEM_ID" "Scoping"' skills/init/SKILL.md && grep -qF '8-column' skills/init/SKILL.md && ! grep -qF '9-column' skills/init/SKILL.md`
Expected: exit 0

**Step 5: Commit.**

---

## Task 5: Auto-add instruct-and-verify (kill the false assumption)

**Harness-infra (skill markdown) task — TDD substitution: write AC → grep check → implement.**

**Files:**
- Modify: `skills/init/SKILL.md` — insert a new Phase 9.5 between Phase 9 and Phase 10; fix Phase 10 step 4 (lines ~415-416)

**Acceptance Criteria:**
- [ ] `Run: ! grep -qF 'new issues auto-add to the linked project, so this is automatic' skills/init/SKILL.md` → `Expected: exit 0` (false claim removed)
- [ ] `Run: grep -qF 'Auto-add to project' skills/init/SKILL.md` → `Expected: exit 0` (explicit instruct present)
- [ ] `Run: grep -qF 'blacksmith_find_item' skills/init/SKILL.md` → `Expected: exit 0` (verify via the board seam, not an inline board read)
- [ ] `Run: grep -qiF 'probe' skills/init/SKILL.md` → `Expected: exit 0` (the verification probe step exists)

**Depends on:** none (independent of Tasks 2-4; safe to do in parallel, but it edits the same file as Task 4 — sequence the commits to avoid a conflicting hunk).

**Step 1: Write the acceptance criteria.** The four greps above are the contract.

**Step 2: Run to confirm RED.**
Run: `grep -qF 'Auto-add to project' skills/init/SKILL.md`
Expected: FAIL (exit 1) — the phrase is absent; init currently asserts auto-add "is automatic".

**Step 3: Implement.**

(a) Insert a new phase after Phase 9 ("Smoke verify"):

```markdown
## Phase 9.5: Enable & verify "Auto-add to project" (manual — UI-only)

A fresh Projects v2 board ships with the "Auto-add to project" workflow OFF, and the
GitHub API cannot enable it. Seed issues will NOT land on the board until you flip it.
Instruct the developer, then verify with a probe — never assume.

1. Instruct:
   > Open `<PROJECT_URL>`, then the project's `…` menu → **Workflows** →
   > **Auto-add to project**. Enable it, set the filter to `is:issue`, target this repo
   > (`$OWNER/$REPO`), and Save. Tell me when done.

2. Verify with a probe issue, checking placement through the board-ops seam:
   ```bash
   source "$CLAUDE_PLUGIN_ROOT/bin/harness-lib.sh"
   PROBE=$(gh issue create --repo "$OWNER/$REPO" \
     --title "oskr auto-add probe (safe to close)" \
     --body "Verifying the Auto-add workflow places new issues on the board." \
     | grep -oE '[0-9]+$')
   sleep 3
   if [[ -n "$(blacksmith_find_item "$PROBE")" ]]; then
     echo "Auto-add VERIFIED: issue #$PROBE landed on the board."
   else
     echo "Auto-add NOT working: issue #$PROBE is not on the board — re-check the toggle."
   fi
   gh issue close "$PROBE" --reason "not planned" --repo "$OWNER/$REPO"
   ```

3. If verification fails, repeat step 1 until the probe lands. Only after Auto-add is
   verified may Phase 10 rely on it for seed issues. (If the developer opts to skip the
   toggle, create seed issues with `blacksmith_create_issue` in Phase 10 — it both
   creates the issue and adds it to the board — instead of relying on auto-add.)
```

(b) Fix Phase 10 step 4 (line ~415): replace `Place each issue in Backlog (default; new issues auto-add to the linked project, so this is automatic unless you want a different starting column).` with:

```markdown
4. Place each issue in Backlog. With Auto-add verified in Phase 9.5, new issues land on
   the board automatically. If Auto-add was skipped, create each seed issue via
   `blacksmith_create_issue` (creates + adds to the board) rather than bare `gh issue create`.
```

**Step 4: Verify GREEN.**
Run: `! grep -qF 'new issues auto-add to the linked project, so this is automatic' skills/init/SKILL.md && grep -qF 'Auto-add to project' skills/init/SKILL.md && grep -qF 'blacksmith_find_item' skills/init/SKILL.md && grep -qiF 'probe' skills/init/SKILL.md`
Expected: exit 0

**Step 5: Commit.**

---

## Task 6: Version bump (repo convention — every PR bumps the manifest)

**Files:**
- Modify: `.claude-plugin/plugin.json` (`version`)

**Acceptance Criteria:**
- [ ] `Run: jq -e '.version | test("^[0-9]+\\.[0-9]+\\.[0-9]+$")' .claude-plugin/plugin.json` → `Expected: exit 0`
- [ ] `Run: test "$(jq -r .version .claude-plugin/plugin.json)" != "$OLD_VERSION"` → `Expected: exit 0` (where `OLD_VERSION` is captured before the edit)

**Step 1.** Capture and bump the patch component (patch, because this task adds an internal verb + reshape, not a new skill/command):
```bash
OLD_VERSION=$(jq -r '.version' .claude-plugin/plugin.json)
NEW_VERSION=$(awk -F. -v OFS=. '{$3=$3+1; print}' <<<"$OLD_VERSION")
tmp=$(mktemp) && jq --arg v "$NEW_VERSION" '.version=$v' .claude-plugin/plugin.json > "$tmp" && mv "$tmp" .claude-plugin/plugin.json
echo "bumped $OLD_VERSION -> $NEW_VERSION"
```
(Current baseline is `0.3.5`; if a sibling Area-#27 child already bumped on the Area branch, bump from whatever is current — the AC checks inequality, not a fixed value.)

**Step 2.** Verify:
Run: `jq -e '.version | test("^[0-9]+\\.[0-9]+\\.[0-9]+$")' .claude-plugin/plugin.json`
Expected: exit 0

**Step 3: Commit.**

---

## Closing gate (run after all tasks)

- [ ] `Run: bash tests/scripts/run-tests.sh` → `Expected: exit 0` (suite green — the Area DoD's hard requirement)
- [ ] `Run: bash -n bin/harness-lib.sh` → `Expected: exit 0`

---

## AC → test/verification map

| AC (from #60 / t5.md) | Verified by |
|---|---|
| Freshly-init'd board has exactly the 8 columns (Scoping added, Approval→Plan Approval, Research+Needs Input absent) | Task 1 (`_blacksmith_board_column_slugs` + vocab, `test_harness_columns.sh`) + Task 2 (`test_blacksmith_provision_columns.sh` asserts the provisioning mutation carries the 8 and omits the 3) + Task 4 (init calls the verb) |
| `actionable_columns` in emitted config + schema reference only live slugs | Task 4 grep (`["scoping","planning","ready"]`, no `"research"…`) + Task 3 grep (schema: no `"needs_input"`/`"approval"`, has `"scoping"`) |
| init instructs + verifies "Auto-add to project" before relying on it | Task 5 greps (`Auto-add to project`, `blacksmith_find_item`, `probe`; false claim removed) |
| Provisioning runs through the board-ops seam (shim replay), not inline forge calls where avoidable | Task 2 (`test_blacksmith_provision_columns.sh` shim replay; `test_backend_no_inline_gh.sh`) + Task 4 (`! grep updateProjectV2Field` in init; init sources the blacksmith) |
| Resolves the #52 provisioning-layer drift for new projects | Single-source-of-truth slug list (Task 1) consumed by both runtime resolution and the provisioning verb (Task 2), emitted by init (Task 4), documented in the schema (Task 3) |

---

## Dependencies

**Within this plan:** Task 2 → Task 1; Task 4 → Task 2. Tasks 3, 5, 6 are independent (Task 5 edits the same file as Task 4 — order their commits). Run the closing gate last.

**Cross-issue (Area #27):** #60 (this task, T5) is **blocked-by T4** (init v2 mode-detection + backend choice + config emission). Task 4 here edits init's Phase 4c/5/9. If T4 has already landed on the Area branch `WillyDallas/27`, the implementer must rebase and re-anchor Task 4's edits onto T4's restructured init (the `forge` discriminator and mode branches will already be present; the provisioning + `actionable_columns` + smoke-column edits still apply). If T4 has not landed, Task 4 applies cleanly to init as it exists today. Either way the grep ACs are the invariant. No other cross-task coupling.

**Deferred (not this task):** Forgejo column provisioning + the `bin/harness-lib.sh:872` slug loop → T8 / Area 5; `workflow.kind` rename + dogfood-config `actionable_columns` → broader #52 / roadmap line 370; live Forgejo acceptance → Area 5.
