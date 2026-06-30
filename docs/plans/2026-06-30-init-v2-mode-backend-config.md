# init v2 — Mode Detection + Backend Choice + Config Emission Implementation Plan

**Goal:** Turn `init` into a repeatable onboarding step that detects which of {already-init, create-new, clone, adopt} applies, lets the developer pick the backend, and writes a `harness-config.json` carrying the `forge` discriminator (`github` | `forgejo`, default `github`) plus the matching per-backend block — for every mode and backend. Board provisioning and the column reshape are separate slices.

**Architecture:** Three new sourceable shell verbs. Two live in a new pure library `bin/init-lib.sh`: `init_detect_mode` (a network-free mapping of `{is-git?, has-origin?, remote-exists?, config-present?}` → mode) and `init_emit_config` (a pure `jq` writer that emits the full config with the `forge` discriminator + the correct backend block). The one forge-coupled detection input — "does the repo exist on the forge?" — is a new blacksmith verb `blacksmith_remote_exists` in `bin/harness-lib.sh` (GitHub via `gh`, Forgejo via the existing curl transport), so it stays behind the seam and is PATH-shim-replayed in tests. `skills/init/SKILL.md` is rewired to call these verbs in Phase 0 (mode detection) and Phase 5 (config emission).

**Tech Stack:** bash 3.2+ (macOS default), `jq`, `gh` CLI, Forgejo REST over `curl`. Tests use the existing hand-rolled `set -euo pipefail` subshell + PATH-shim-replay runner (`tests/scripts/run-tests.sh` + `lib/assert.sh` + `lib/gh-shim.sh` + `lib/curl-shim.sh`) — no bats, no new deps.

**Issue:** #57 (child of Area #27 — Workspace & setup)

---

## Exemptions & substitutions (declared for plan-reviewer)

- **No Playwright AC.** oskr is a Claude Code plugin harness — pure shell verbs + one interactive skill (prose). Zero web UI / navigation / auth surface. The Playwright tier does not apply.
- **No design/quality-rule ACs.** The project declares no `.claude/rules/` (verified: `Glob .claude/rules/**` → no files). This AC class is a no-op here.
- **TDD substitution on Tasks 4–5 (declared, deliberate).** Tasks 1–3 are testable shell at the `bin/` verb boundary → standard RED-first TDD applies and is used. Tasks 4–5 edit `skills/init/SKILL.md` — interactive agent prose with no runnable unit boundary. Per the agent definition, those use the harness-infrastructure substitution: **write acceptance criterion → `grep` / `! grep` structural check → implement.** The load-bearing *behavior* (detection, emission) is already covered by Tasks 1–3's unit tests; the SKILL greps only assert the verbs are wired in and the stale GitHub-only / fresh-repo-only prose is gone.
- **Seam tier per verb.** Per the umbrella's single Named Seam family: `init_detect_mode` + `init_emit_config` are *pure resolution* → subshell + `harness-config.*.json` fixtures, no shims. `blacksmith_remote_exists` is the *forge-touching* verb → `lib/gh-shim.sh` + `lib/curl-shim.sh` PATH-boundary replay. This matches the PRD's "straddles both" note for init mode-detection.

## Scope boundary (what this child is NOT)

Issue #57's `## What` / `## AC` cover exactly: (a) mode detection, (b) writing `harness-config.json` with the `forge` discriminator + per-backend block, (c) round-tripping both shapes, (d) the forge probe via shim replay. Therefore the following are **out of scope** and belong to other children:

- **Board provisioning + the 8-column reshape + `actionable_columns` migration** → T5 (#58-class). This plan keeps the emitter's `workflow.kind: gen-eval-9col` and the current `actionable_columns` so it round-trips the existing fixtures; T5 reshapes the emitter's `workflow` defaults in one place (`init_emit_config`). That is a deliberate blocked-by edge (T5 → T4), not a gap.
- **The adopt flow** (consent gate, register-only, harvest→reconcile→re-emit) → T6/T7. This plan makes Phase 0 *detect* `adopt` and route to it; it does not build the adopt body.
- **Registry write / relocation / `bin/registry.sh`** → T2. Phase 6 is left untouched here.
- **Workspace-root resolver / two-tier global config** → T1 (#54). `init_emit_config` writes the project's own `harness-config.json` at `$PWD`; it does not read or depend on the workspace tier. So although #57 is *labelled* blocked-by T1, none of these three verbs actually consume T1's resolver — the plan stands alone.
- **Live Forgejo acceptance** → Area 5. The Forgejo probe is curl-shim-unit-proven only; no live server is hit.

---

## Definition of Done

1. **Deliverables:**
   - Create `bin/init-lib.sh` — sourceable; `init_detect_mode` + `init_emit_config` (+ `_init_die`).
   - Modify `bin/harness-lib.sh` — add `blacksmith_remote_exists` public verb + `_blacksmith_github_remote_exists` + `_blacksmith_forgejo_remote_exists`.
   - Modify `tests/scripts/lib/gh-shim.sh` + `tests/scripts/lib/curl-shim.sh` — add `remote_exists` probe routes (rc-controllable).
   - Create `tests/scripts/test_init_detect_mode.sh`, `tests/scripts/test_init_emit_config.sh`, `tests/scripts/test_init_remote_probe.sh`.
   - Modify `skills/init/SKILL.md` — Phase 0 mode detection (Task 4) + Phase 1/5 backend choice & emit-via-verb (Task 5).
   - Bump `version` (patch) in `.claude-plugin/plugin.json` per the repo's every-PR convention.
2. **Testing tier:** Unit / hermetic — subshell-fixture for the pure verbs, PATH-shim replay for the one forge-coupled verb. No integration/e2e: no live board, no network. Justification: detection is a pure function of four booleans; emission is pure `jq`; the probe's only forge dependency is replaced by a replayed shim. Live Forgejo is explicitly Area 5.
3. **Task granularity:** 5 tasks, each ≤ 5 min of implementer work (one verb + its test, or one SKILL phase + its greps).
4. **Verification:** every acceptance criterion below maps to a runnable `Run:`/`Expected:` tuple (see AC→Test map). No prose-only ACs.
5. **Dependencies:** Task 4 and Task 5 depend on Tasks 1–3 (they wire the verbs in). Task 5 depends on Task 2 + Task 4. Tasks 1, 2, 3 are mutually independent. Cross-child: #57 is blocked-by T1 (#54) on the board DAG, but — see Scope boundary — none of these verbs consume T1's output, so the plan is executable even if merged ahead of T1. #57 **blocks** T5 (provisioning + reshape), which extends `init_emit_config`'s `workflow` defaults.
6. **Regression guarantee (issue-specific axis):** Adding `blacksmith_remote_exists` must not trip the backend seam guard, and the project-tier config reader is untouched. `tests/scripts/test_backend_no_inline_gh.sh` and `tests/scripts/test_harness_config.sh` pass **unchanged**; `tests/scripts/run-tests.sh` is green.

---

## AC → Test map

| # | Acceptance criterion (from issue #57) | Verifying command |
|---|---|---|
| AC1 | Mode detection maps the four inputs to {already-init, create-new, clone, adopt}; `already-init` refuses re-init safely | `bash tests/scripts/test_init_detect_mode.sh` |
| AC2 | `init` writes `harness-config.json` with the `forge` discriminator + correct per-backend block; default `github` | `bash tests/scripts/test_init_emit_config.sh` (forge/default/backend assertions) + `grep -qF 'init_emit_config' skills/init/SKILL.md` |
| AC3 | Emitted config round-trips for both GitHub and Forgejo shapes (asserted against fixtures) | `bash tests/scripts/test_init_emit_config.sh` (fixture deep-equal + reader round-trip) |
| AC4 | The forge probe is exercised via shim replay; the rest of detection is pure subshell | `bash tests/scripts/test_init_remote_probe.sh` (gh-shim + curl-shim) + `bash tests/scripts/test_init_detect_mode.sh` (no shims) |
| AC5 | Seam + project-tier reader unbroken; suite green | `bash tests/scripts/test_backend_no_inline_gh.sh` + `bash tests/scripts/test_harness_config.sh` + `bash tests/scripts/run-tests.sh` |
| AC6 | Phase 0 detects mode; the stale fresh-repo-only / oskr#16 refusal is gone | `grep -qF 'init_detect_mode' skills/init/SKILL.md` + `! grep -qF 'oskr#16' skills/init/SKILL.md` |

---

## Task 1: `init_detect_mode` — pure mode-detection verb

**Files:**
- Create: `bin/init-lib.sh`
- Test: `tests/scripts/test_init_detect_mode.sh` (create)

**Acceptance Criteria:**
- [ ] `Run: bash tests/scripts/test_init_detect_mode.sh` → `Expected: exit 0` (prints `test_init_detect_mode: PASS`)
- [ ] `config-present=yes` returns `already-init` regardless of the other three inputs (the re-init guard).
- [ ] `is-git=yes, has-origin=yes, config=no` → `adopt`; `remote-exists=yes` (else) → `clone`; all-no → `create-new`.
- [ ] No-arg call defaults to `create-new` (all inputs default `no`).
- [ ] `Run: grep -qF 'init_detect_mode()' bin/init-lib.sh` → `Expected: exit 0`

**Step 1: Write the failing test**

Create `tests/scripts/test_init_detect_mode.sh`:

```bash
#!/usr/bin/env bash
# init_detect_mode (init v2, #27 / #57): pure mapping of
# {is-git?, has-origin?, remote-exists?, config-present?} -> the onboarding mode.
# Network-free, disk-free — straight subshell over the function. No shims.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"
LIB="$REPO_ROOT/bin/init-lib.sh"

detect() { bash -c "source '$LIB'; init_detect_mode \"\$@\"" _ "$@"; }

# config present always wins -> already-init (the re-init guard), whatever the rest.
assert_eq "already-init" "$(detect yes yes yes yes)" "config present -> already-init"        || exit 1
assert_eq "already-init" "$(detect no  no  no  yes)" "config present (bare) -> already-init"  || exit 1
# local git repo wired to an origin remote -> adopt.
assert_eq "adopt"        "$(detect yes yes no  no)"  "git + origin -> adopt"                  || exit 1
# repo exists on the forge but absent locally -> clone.
assert_eq "clone"        "$(detect no  no  yes no)"  "remote exists, absent locally -> clone" || exit 1
# nothing anywhere -> create-new.
assert_eq "create-new"   "$(detect no  no  no  no)"  "nothing -> create-new"                  || exit 1
# defaults: no args -> create-new (every input defaults to no).
assert_eq "create-new"   "$(bash -c "source '$LIB'; init_detect_mode")" "no args -> create-new" || exit 1

echo "test_init_detect_mode: PASS"
```

**Step 2: Run test to verify it fails**

Run: `bash tests/scripts/test_init_detect_mode.sh`
Expected: FAIL — `bin/init-lib.sh` does not exist (`source: No such file`), non-zero exit.

**Step 3: Write minimal implementation**

Create `bin/init-lib.sh`:

```bash
#!/usr/bin/env bash
# init-lib.sh — init v2 helpers: mode detection + config emission.
# Sourceable; NOT directly executable. Pure (network-free, disk-free) by design —
# the one forge-coupled detection input (does the repo exist on the forge?) is
# supplied by the caller via blacksmith_remote_exists (harness-lib.sh), keeping
# these functions subshell-testable. See docs/design/platform-reframe.md and the
# Area #27 PRD.

_init_die() {
  echo "[init] $1" >&2
  return 1
}

# init_detect_mode <is_git> <has_origin> <remote_exists> <config_present>
# Each arg is "yes" or "no" (anything not "yes" is treated as "no"). Echoes
# exactly one of:
#   already-init  — harness-config.json present; the caller refuses re-init
#   adopt         — local git repo already wired to an origin remote
#   clone         — repo exists on the forge but not here
#   create-new    — nothing exists locally or on the forge
# Precedence: config > origin > forge-remote > nothing. Pure; no network, no disk.
init_detect_mode() {
  local is_git="${1:-no}" has_origin="${2:-no}" remote_exists="${3:-no}" config_present="${4:-no}"
  if [[ "$config_present" == "yes" ]]; then echo "already-init"; return 0; fi
  if [[ "$is_git" == "yes" && "$has_origin" == "yes" ]]; then echo "adopt"; return 0; fi
  if [[ "$remote_exists" == "yes" ]]; then echo "clone"; return 0; fi
  echo "create-new"
}
```

**Step 4: Run test to verify it passes**

Run: `bash tests/scripts/test_init_detect_mode.sh`
Expected: PASS — prints `test_init_detect_mode: PASS`, exit 0.

**Step 5: Commit** — `feat(init): pure init_detect_mode verb (#57)`

---

## Task 2: `init_emit_config` — pure config writer with the `forge` discriminator

**Files:**
- Modify: `bin/init-lib.sh` (append `init_emit_config`)
- Test: `tests/scripts/test_init_emit_config.sh` (create)
- Reuse fixtures: `tests/scripts/fixtures/harness-config.sample.json` (github), `tests/scripts/fixtures/harness-config.forgejo.json` (forgejo)

**Acceptance Criteria:**
- [ ] `Run: bash tests/scripts/test_init_emit_config.sh` → `Expected: exit 0` (prints `test_init_emit_config: PASS`)
- [ ] github emit: `.forge == "github"`, `.github` deep-equals the sample fixture's `.github`, no `.forgejo` key.
- [ ] forgejo emit: `.forge == "forgejo"`, `.forgejo` deep-equals the forgejo fixture's `.forgejo`, no `.github` key.
- [ ] Empty/omitted forge arg defaults to `github`; an unknown forge fails non-zero.
- [ ] Emitted config is consumable by the existing reader: `HARNESS_CONFIG=<emitted> _blacksmith_forge` echoes the right forge and `blacksmith_config_get` reads the backend coords back.
- [ ] `Run: grep -qF 'init_emit_config()' bin/init-lib.sh` → `Expected: exit 0`

**Step 1: Write the failing test**

Create `tests/scripts/test_init_emit_config.sh`:

```bash
#!/usr/bin/env bash
# init_emit_config (init v2, #27 / #57): emits harness-config.json carrying the
# `forge` discriminator + the matching per-backend block. Round-trips both the
# GitHub and Forgejo shapes against the canonical fixtures, AND back through the
# real config reader. Pure jq; no network, no shims.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FIX="$REPO_ROOT/tests/scripts/fixtures"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"
LIB="$REPO_ROOT/bin/init-lib.sh"
HLIB="$REPO_ROOT/bin/harness-lib.sh"
emit() { bash -c "source '$LIB'; init_emit_config \"\$@\"" _ "$@"; }

TMP=$(mktemp); trap 'rm -f "$TMP"' EXIT

# --- GitHub shape: forge=github, .github block round-trips the sample fixture ---
gh_out=$(emit github oskr-test "bash + gh CLI" main WillyDallas oskr 1)
echo "$gh_out" | jq -e . >/dev/null || { echo "FAIL: github emit is not valid JSON" >&2; exit 1; }
assert_eq "github" "$(jq -r '.forge' <<<"$gh_out")" "github: forge discriminator" || exit 1
assert_eq "$(jq -cS '.github' "$FIX/harness-config.sample.json")" \
          "$(jq -cS '.github' <<<"$gh_out")" "github: backend block matches fixture" || exit 1
assert_eq "false" "$(jq 'has("forgejo")' <<<"$gh_out")" "github: no forgejo block" || exit 1

# --- Forgejo shape: forge=forgejo, .forgejo block round-trips the forgejo fixture ---
fj_out=$(emit forgejo sluice "" main https://git.squirrlylabs.dev squirrlylabs sluice)
echo "$fj_out" | jq -e . >/dev/null || { echo "FAIL: forgejo emit is not valid JSON" >&2; exit 1; }
assert_eq "forgejo" "$(jq -r '.forge' <<<"$fj_out")" "forgejo: forge discriminator" || exit 1
assert_eq "$(jq -cS '.forgejo' "$FIX/harness-config.forgejo.json")" \
          "$(jq -cS '.forgejo' <<<"$fj_out")" "forgejo: backend block matches fixture" || exit 1
assert_eq "false" "$(jq 'has("github")' <<<"$fj_out")" "forgejo: no github block" || exit 1

# --- default forge is github when omitted/empty ---
def_out=$(emit "" def-proj "" main owner repo 3)
assert_eq "github" "$(jq -r '.forge' <<<"$def_out")" "empty forge defaults to github" || exit 1

# --- unknown forge fails loudly (non-zero) ---
if emit frobgit x y main a b c >/dev/null 2>&1; then
  echo "FAIL: unknown forge should be rejected" >&2; exit 1
fi

# --- round-trip through the ACTUAL config reader: emitted file is consumable ---
emit github oskr-test "bash + gh CLI" main WillyDallas oskr 1 > "$TMP"
assert_eq "github" "$(HARNESS_CONFIG="$TMP" bash -c "source '$HLIB'; _blacksmith_forge")" \
          "emitted github config reads back as forge=github" || exit 1
assert_eq "WillyDallas" "$(HARNESS_CONFIG="$TMP" bash -c "source '$HLIB'; blacksmith_config_get '.github.owner'")" \
          "emitted github config: owner reads back" || exit 1

emit forgejo sluice "" main https://git.squirrlylabs.dev squirrlylabs sluice > "$TMP"
assert_eq "forgejo" "$(HARNESS_CONFIG="$TMP" bash -c "source '$HLIB'; _blacksmith_forge")" \
          "emitted forgejo config reads back as forge=forgejo" || exit 1
assert_eq "squirrlylabs" "$(HARNESS_CONFIG="$TMP" bash -c "source '$HLIB'; blacksmith_config_get '.forgejo.owner'")" \
          "emitted forgejo config: owner reads back" || exit 1

echo "test_init_emit_config: PASS"
```

**Step 2: Run test to verify it fails**

Run: `bash tests/scripts/test_init_emit_config.sh`
Expected: FAIL — `init_emit_config` is undefined (`command not found` / empty output), non-zero exit.

**Step 3: Write minimal implementation**

Append to `bin/init-lib.sh`:

```bash
# init_emit_config <forge> <name> <tech_stack> <base_branch> <a> <b> <c>
#   forge=github  : a=owner    b=repo  c=project_number
#   forge=forgejo : a=base_url b=owner c=repo
# Echoes a complete harness-config.json on stdout, carrying the `forge`
# discriminator and EXACTLY the matching per-backend block. Pure jq; no network.
# NOTE (slice boundary): workflow.kind / actionable_columns intentionally match the
# current 9-col fixtures so this round-trips today; the 8-col reshape (T5) changes
# these defaults HERE in one place. project_number defaults to 0 pre-provisioning.
init_emit_config() {
  local forge="${1:-github}" name="$2" tech="${3:-}" base="${4:-main}"
  local a="${5:-}" b="${6:-}" c="${7:-}" backend
  [[ -n "$forge" ]] || forge=github
  case "$forge" in
    github)
      backend=$(jq -nc --arg o "$a" --arg r "$b" --argjson pn "${c:-0}" \
        '{github: {owner: $o, repo: $r, project_number: $pn}}') || return 1 ;;
    forgejo)
      backend=$(jq -nc --arg u "$a" --arg o "$b" --arg r "$c" \
        '{forgejo: {base_url: $u, owner: $o, repo: $r}}') || return 1 ;;
    *)
      _init_die "unknown forge '$forge' (expected github|forgejo)"; return 1 ;;
  esac
  jq -n \
    --arg forge "$forge" --arg name "$name" --arg tech "$tech" --arg base "$base" \
    --argjson backend "$backend" '
      {name: $name, forge: $forge}
      + $backend
      + {
          workflow: {
            kind: "gen-eval-9col",
            column_names: {},
            actionable_columns: ["needs_input", "approval", "ready", "in_review"]
          },
          paths: {plans: "docs/plans", research: "docs/research", plan_archive: "docs/_local_archive"},
          agent_context: {project_name: $name, tech_stack: $tech},
          base_branch: $base
        }
    '
}
```

**Step 4: Run test to verify it passes**

Run: `bash tests/scripts/test_init_emit_config.sh`
Expected: PASS — prints `test_init_emit_config: PASS`, exit 0.

**Step 5: Commit** — `feat(init): pure init_emit_config writer with forge discriminator (#57)`

---

## Task 3: `blacksmith_remote_exists` — the forge probe (shim-replayed)

**Files:**
- Modify: `bin/harness-lib.sh` (add public verb + two per-forge impls)
- Modify: `tests/scripts/lib/gh-shim.sh` (add `repo view` route)
- Modify: `tests/scripts/lib/curl-shim.sh` (add bare `/repos/{owner}/{repo}` route)
- Test: `tests/scripts/test_init_remote_probe.sh` (create)

**Acceptance Criteria:**
- [ ] `Run: bash tests/scripts/test_init_remote_probe.sh` → `Expected: exit 0` (prints `test_init_remote_probe: PASS`)
- [ ] GitHub probe: exists → rc 0, absent → rc != 0; the call log shows `gh repo view`.
- [ ] Forgejo probe: exists → rc 0, absent → rc != 0; the call log shows `GET .../repos/squirrlylabs/sluice`.
- [ ] `Run: bash tests/scripts/test_backend_no_inline_gh.sh` → `Expected: exit 0` (the new `gh repo view` lives in `harness-lib.sh`, exempt; init-lib has no forge calls).
- [ ] `Run: grep -qF 'blacksmith_remote_exists()' bin/harness-lib.sh` → `Expected: exit 0`

**Step 1: Write the failing test**

Create `tests/scripts/test_init_remote_probe.sh`:

```bash
#!/usr/bin/env bash
# blacksmith_remote_exists (init v2, #27 / #57): the one forge-coupled
# mode-detection input. GitHub goes through `gh` (gh-shim); Forgejo through the
# curl transport (curl-shim). Asserts both exists (rc 0) and absent (rc != 0),
# and that the probe actually hit the forge. PATH-boundary shim replay.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FIX="$REPO_ROOT/tests/scripts/fixtures"
LIB="$REPO_ROOT/bin/harness-lib.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"

SHIM_DIR=$(mktemp -d); trap 'rm -rf "$SHIM_DIR"' EXIT
cp "$SCRIPT_DIR/lib/gh-shim.sh"   "$SHIM_DIR/gh";   chmod +x "$SHIM_DIR/gh"
cp "$SCRIPT_DIR/lib/curl-shim.sh" "$SHIM_DIR/curl"; chmod +x "$SHIM_DIR/curl"

# --- GitHub: rc 0 = exists, and the probe hit `gh repo view` ---
GLOG="$SHIM_DIR/gh.log"; : > "$GLOG"
rc=0
PATH="$SHIM_DIR:$PATH" HARNESS_CONFIG="$FIX/harness-config.sample.json" \
  GH_SHIM_CALL_LOG="$GLOG" GH_SHIM_FIXTURE="$FIX/gh-project-discovery.json" \
  GH_SHIM_REPO_VIEW_RC=0 \
  bash -c "source '$LIB'; blacksmith_remote_exists WillyDallas oskr" || rc=$?
assert_eq "0" "$rc" "github probe: existing repo -> rc 0" || exit 1
grep -qF 'repo view' "$GLOG" || { echo "FAIL: github probe did not call gh repo view" >&2; exit 1; }

# --- GitHub: rc != 0 = absent ---
rc=0
PATH="$SHIM_DIR:$PATH" HARNESS_CONFIG="$FIX/harness-config.sample.json" \
  GH_SHIM_CALL_LOG="$SHIM_DIR/gh2.log" GH_SHIM_FIXTURE="$FIX/gh-project-discovery.json" \
  GH_SHIM_REPO_VIEW_RC=1 \
  bash -c "source '$LIB'; blacksmith_remote_exists WillyDallas nope" || rc=$?
assert_eq "1" "$rc" "github probe: missing repo -> rc 1" || exit 1

# --- Forgejo: rc 0 = exists, and the probe GET the repo ---
CLOG="$SHIM_DIR/curl.log"; : > "$CLOG"
rc=0
PATH="$SHIM_DIR:$PATH" HARNESS_CONFIG="$FIX/harness-config.forgejo.json" FORGEJO_TOKEN="t" \
  CURL_SHIM_CALL_LOG="$CLOG" CURL_SHIM_REPO_RC=0 \
  bash -c "source '$LIB'; blacksmith_remote_exists squirrlylabs sluice" || rc=$?
assert_eq "0" "$rc" "forgejo probe: existing repo -> rc 0" || exit 1
grep -qF '/repos/squirrlylabs/sluice' "$CLOG" || { echo "FAIL: forgejo probe did not GET the repo" >&2; exit 1; }

# --- Forgejo: rc != 0 = absent ---
rc=0
PATH="$SHIM_DIR:$PATH" HARNESS_CONFIG="$FIX/harness-config.forgejo.json" FORGEJO_TOKEN="t" \
  CURL_SHIM_CALL_LOG="$SHIM_DIR/curl2.log" CURL_SHIM_REPO_RC=22 \
  bash -c "source '$LIB'; blacksmith_remote_exists squirrlylabs nope" || rc=$?
[[ "$rc" -ne 0 ]] || { echo "FAIL: forgejo probe missing repo should be non-zero" >&2; exit 1; }

echo "test_init_remote_probe: PASS"
```

**Step 2: Run test to verify it fails**

Run: `bash tests/scripts/test_init_remote_probe.sh`
Expected: FAIL — `blacksmith_remote_exists` is undefined → dispatcher dies / non-zero, before any rc assertion passes.

**Step 3: Write minimal implementation**

(a) In `bin/harness-lib.sh`, add the public verb next to the other `blacksmith_*` dispatchers (after `blacksmith_base_branch`, ~line 104):

```bash
blacksmith_remote_exists()     { _blacksmith_dispatch remote_exists "$@"; }
```

(b) In the GitHub backend section (near `_blacksmith_github_pr_open_count`, ~line 540), add:

```bash
# Probe whether owner/repo exists on GitHub. Returns 0 if it exists, non-zero
# otherwise. Used by init v2 mode detection (create-new vs clone). No stdout.
#   remote_exists <owner> <repo>
_blacksmith_github_remote_exists() {
  local owner="$1" repo="$2"
  gh repo view "${owner}/${repo}" --json nameWithOwner >/dev/null 2>&1
}
```

(c) In the Forgejo backend section (near `_blacksmith_forgejo_find_item`, ~line 764), add:

```bash
# Probe whether owner/repo exists on the Forgejo instance. Returns 0 if it
# exists, non-zero otherwise. Same neutral contract as the GitHub probe.
#   remote_exists <owner> <repo>
_blacksmith_forgejo_remote_exists() {
  local owner="$1" repo="$2"
  _blacksmith_forgejo_curl GET "/repos/${owner}/${repo}" >/dev/null 2>&1
}
```

(d) In `tests/scripts/lib/gh-shim.sh`, add a route immediately **before** the final `emit < "$GH_SHIM_FIXTURE"` line:

```bash
if [[ "$args" == *"repo view"* ]]; then         # remote_exists probe: rc 0 = exists, non-zero = absent
  exit "${GH_SHIM_REPO_VIEW_RC:-0}"
fi
```

(e) In `tests/scripts/lib/curl-shim.sh`, add a route immediately **before** the final `echo "curl-shim: no route for: $args"` line (it is reached only after the more-specific `/issues`, `/labels`, `/milestones`, `/dependencies` routes have already returned, so a bare repo URL lands here):

```bash
if [[ "$args" == */repos/*/* ]]; then           # remote_exists probe: GET /repos/{owner}/{repo}; rc 0 = exists
  exit "${CURL_SHIM_REPO_RC:-0}"
fi
```

**Step 4: Run test to verify it passes**

Run: `bash tests/scripts/test_init_remote_probe.sh`
Expected: PASS — prints `test_init_remote_probe: PASS`, exit 0.
Then confirm the seam guard is intact — Run: `bash tests/scripts/test_backend_no_inline_gh.sh` → Expected: exit 0 (`test_backend_no_inline_gh: PASS`).

**Step 5: Commit** — `feat(blacksmith): remote_exists forge probe + shim routes (#57)`

---

## Task 4: SKILL.md Phase 0 — wire mode detection (infra substitution: grep ACs)

> **TDD substitution (declared):** `skills/init/SKILL.md` is interactive agent prose with no runnable unit boundary. The *behavior* is already unit-proven by Tasks 1 + 3. This task asserts the verbs are wired in and the stale GitHub-only / fresh-repo-only refusal is gone, via `grep` / `! grep`.

**Files:**
- Modify: `skills/init/SKILL.md` (Phase 0 detection + Branch block, ~lines 10–32)

**Acceptance Criteria:**
- [ ] `Run: grep -qF 'init_detect_mode' skills/init/SKILL.md` → `Expected: exit 0`
- [ ] `Run: grep -qF 'blacksmith_remote_exists' skills/init/SKILL.md` → `Expected: exit 0`
- [ ] `Run: grep -qF 'CLAUDE_PLUGIN_ROOT' skills/init/SKILL.md` → `Expected: exit 0` (portable lib sourcing, not relative path)
- [ ] `Run: ! grep -qF 'oskr#16' skills/init/SKILL.md` → `Expected: exit 0` (fresh-repo-only refusal removed)
- [ ] `Run: ! grep -qF 'fresh-repo bootstrap only' skills/init/SKILL.md` → `Expected: exit 0`
- [ ] `Run: grep -qF 'already-init' skills/init/SKILL.md` → `Expected: exit 0`

**Step 1: Write the acceptance criteria** — the six `grep`/`! grep` checks above are the contract.

**Step 2: Run the checks to verify they fail**

Run: `grep -qF 'init_detect_mode' skills/init/SKILL.md && grep -qF 'blacksmith_remote_exists' skills/init/SKILL.md && ! grep -qF 'oskr#16' skills/init/SKILL.md`
Expected: FAIL (non-zero) — the verbs are absent and `oskr#16` is still present.

**Step 3: Implement**

Replace the Phase 0 detection block and the "Branch" list (current lines ~14–32) with detection that sources the libs via `$CLAUDE_PLUGIN_ROOT` and computes the mode through the verbs. The new Phase 0 reads:

````markdown
## Phase 0: Pre-flight detection

Source the init helpers and the blacksmith (portable across the cache vs `--plugin-dir`):

```bash
source "$CLAUDE_PLUGIN_ROOT/bin/harness-lib.sh"
source "$CLAUDE_PLUGIN_ROOT/bin/init-lib.sh"

CWD=$(pwd)
DIR_NAME=$(basename "$CWD")
GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "")

IN_GIT=$([ -d .git ] || git rev-parse --git-dir >/dev/null 2>&1 && echo yes || echo no)
HAS_ORIGIN=$( [ "$IN_GIT" = yes ] && git remote get-url origin >/dev/null 2>&1 && echo yes || echo no)
HAS_CONFIG=$([ -f harness-config.json ] || [ -f .claude/harness-config.json ] && echo yes || echo no)

# Forge-existence probe (clone vs create-new). Ask owner/repo first if not yet known;
# default forge github. The probe is the blacksmith verb — never an inline gh/curl.
REMOTE_EXISTS=$(blacksmith_remote_exists "${OWNER:-$GH_USER}" "${REPO:-$DIR_NAME}" && echo yes || echo no)

MODE=$(init_detect_mode "$IN_GIT" "$HAS_ORIGIN" "$REMOTE_EXISTS" "$HAS_CONFIG")
echo "Detected mode: $MODE"
```

Report each fact on its own line, then branch on `$MODE`:

- **already-init** → Stop: "This directory is already an oskr-managed project (`harness-config.json` present). Re-init would overwrite config; delete it first if that is what you want."
- **create-new** → proceed to Phase 1 (greenfield: create repo + board).
- **clone** → the repo exists on the forge but not here; clone it, then proceed to Phase 1 to write config / verify the board.
- **adopt** → a local repo already wired to a remote; hand off to the **adopt path** (consent gate + register-only / full migration). *Adopt onboarding is built in a separate slice — do not provision over an existing board here.*
````

Remove the old `IN_GIT`/`HAS_REMOTE` heredoc and the three-bullet Branch block that referenced `oskr#16` and "fresh-repo bootstrap only". Also delete the duplicate `oskr#16` line in the closing **Key Rules** section (~line 441).

**Step 4: Run the checks to verify they pass**

Run: `grep -qF 'init_detect_mode' skills/init/SKILL.md && grep -qF 'blacksmith_remote_exists' skills/init/SKILL.md && grep -qF 'CLAUDE_PLUGIN_ROOT' skills/init/SKILL.md && ! grep -qF 'oskr#16' skills/init/SKILL.md && ! grep -qF 'fresh-repo bootstrap only' skills/init/SKILL.md && grep -qF 'already-init' skills/init/SKILL.md`
Expected: exit 0.

**Step 5: Commit** — `feat(init): Phase 0 routes via init_detect_mode + remote probe (#57)`

---

## Task 5: SKILL.md Phase 1/5 — backend choice + emit config via the verb (infra substitution: grep ACs)

> **TDD substitution (declared):** prose change; the config-writing behavior is unit-proven by Task 2. Greps assert the verb is called, the forge is selectable, and the old inline heredoc writer is gone.

**Files:**
- Modify: `skills/init/SKILL.md` (Phase 1 add a backend question; Phase 5 replace the inline `harness-config.json` heredoc with `init_emit_config`)

**Acceptance Criteria:**
- [ ] `Run: grep -qF 'init_emit_config' skills/init/SKILL.md` → `Expected: exit 0`
- [ ] `Run: grep -qiF 'forgejo' skills/init/SKILL.md` → `Expected: exit 0` (backend choice surfaced; default github)
- [ ] `Run: ! grep -qF 'WORKFLOW_BLOCK' skills/init/SKILL.md` → `Expected: exit 0` (inline heredoc writer removed)
- [ ] `Run: ! grep -qF 'cat > harness-config.json' skills/init/SKILL.md` → `Expected: exit 0`
- [ ] `Run: bash -n <(sed -n '/init_emit_config/,/^```/p' skills/init/SKILL.md | sed '1d;$d')` is not required; instead the load-bearing emission path is covered by `bash tests/scripts/test_init_emit_config.sh` → `Expected: exit 0`

**Step 1: Write the acceptance criteria** — the grep checks above plus the Task 2 suite are the contract.

**Step 2: Run the checks to verify they fail**

Run: `grep -qF 'init_emit_config' skills/init/SKILL.md`
Expected: FAIL (non-zero) — Phase 5 still uses the inline `cat > harness-config.json` heredoc.

**Step 3: Implement**

(a) Phase 1 — add a backend question after the GitHub-coordinates question:

````markdown
7. **Backend (forge)** — `github` (default) or `forgejo`. Ask: "Backend? github (default) or forgejo". Set `FORGE` accordingly (default `github`). For `forgejo`, also gather `BASE_URL` (e.g. `https://git.example.org`) and confirm `$FORGEJO_TOKEN` is set in the workspace `.env`.
````

(b) Phase 5 — replace the entire inline `WORKFLOW_BLOCK` + `cat > harness-config.json <<EOF ... EOF` block with a single call to the verb (coords differ by forge):

````markdown
## Phase 5: Write harness-config.json

Emit the config through the init writer — it stamps the `forge` discriminator and
the matching backend block. (`init-lib.sh` was sourced in Phase 0.)

```bash
if [[ "${FORGE:-github}" == "forgejo" ]]; then
  init_emit_config forgejo "$NAME" "$TECH_STACK" "$BASE_BRANCH" \
    "$BASE_URL" "$OWNER" "$REPO" > harness-config.json
else
  init_emit_config github "$NAME" "$TECH_STACK" "$BASE_BRANCH" \
    "$OWNER" "$REPO" "${PROJECT_NUMBER:-0}" > harness-config.json
fi

jq . harness-config.json > /dev/null || { echo "ABORT: malformed harness-config.json"; exit 1; }
```
````

For `create-new`/`clone`, `PROJECT_NUMBER` is the board number captured in Phase 4 (provisioning slice); if Phase 4 has not run yet it defaults to `0` and the provisioning slice backfills it.

**Step 4: Run the checks to verify they pass**

Run: `grep -qF 'init_emit_config' skills/init/SKILL.md && grep -qiF 'forgejo' skills/init/SKILL.md && ! grep -qF 'WORKFLOW_BLOCK' skills/init/SKILL.md && ! grep -qF 'cat > harness-config.json' skills/init/SKILL.md`
Expected: exit 0.
Then Run: `bash tests/scripts/run-tests.sh` → Expected: exit 0 (full suite green, including the three new tests; `test_harness_config.sh` and `test_backend_no_inline_gh.sh` unchanged & passing).

**Step 5: Commit** — `feat(init): Phase 5 emits config via init_emit_config + forge choice (#57)`; bump `.claude-plugin/plugin.json` patch version in the same PR per the repo convention.

---

## Final verification gate (run before opening the PR)

Run: `bash tests/scripts/run-tests.sh`
Expected: exit 0 — `Results: N/N passed, 0 failed`, with `test_init_detect_mode`, `test_init_emit_config`, `test_init_remote_probe` discovered and green, and `test_harness_config.sh` + `test_backend_no_inline_gh.sh` still passing untouched.

Run: `git diff --quiet -- tests/scripts/test_harness_config.sh`
Expected: exit 0 — the project-tier reader regression test was not edited.
