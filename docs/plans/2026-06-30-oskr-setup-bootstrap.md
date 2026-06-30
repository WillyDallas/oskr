# `/oskr-setup` workspace bootstrap — Implementation Plan

**Goal:** Stand up a fresh oskr workspace once — skeleton dirs + populated global `.oskr/config.json` + empty `.oskr/registry.json` — via a seam-testable `bin/` verb wrapped by an interactive `/oskr-setup` skill that hands off to `init`.
**Architecture:** A new pure-filesystem `bin/oskr-setup.sh` exposes three verbs (`skeleton`, `write-config`, `bootstrap`) that create the workspace skeleton and emit a non-secret global config; it touches **no forge** (stays outside the backend seam). A new `skills/oskr-setup/SKILL.md` gathers config interactively, calls `bootstrap`, instruct-and-verifies credentials, delegates brain/teach **only if present**, and points the developer to `init`.
**Tech Stack:** Bash 3.2 (macOS) + `jq`; the hermetic `tests/scripts/` subshell-fixture harness (no forge shims needed — this slice is pure FS/JSON).
**Issue:** #59 (child of Area #27 — Workspace & setup)

> **Run-command convention:** every `Run:` below is **repo-root-relative** (run from the
> repository root, whatever path it is checked out at — `…/WillyDev/oskr` or a worktree).

---

## Context the implementer must hold

- **Workspace CREATION anchors at an explicit dir (default `$PWD`), NOT the T1 upward-`.oskr/` resolver.** You cannot resolve a workspace that does not exist yet; `blacksmith_workspace_dir` (T1) only *finds* an existing one. So this slice's verbs take a target dir and do not depend on T1 at runtime.
- **Secrets never land in `.oskr/config.json`.** The schema doc is explicit: "token comes from `$FORGEJO_TOKEN`, not this file" (`docs/harness-config.schema.md:18`). Global config records the **backend selection + non-secret coordinates + base branch**; credentials are **instruct-and-verified** into the workspace `.env` (Forgejo `FORGEJO_TOKEN`) / `gh` keychain (GitHub). This is the deliberate reading of AC "captures credentials" — capture = gather + verify presence, not persist a secret into a tracked file. Honors the stateless-plugin + secret-hygiene invariants (`docs/design/blacksmith.md`).
- **Empty registry shape is `{"projects": []}`** — byte-compatible with `repos/projects.example.json` (the legacy shape T2's migration shim relocates), so the file T3 first-creates is the same container T2's `bin/registry.sh` and the migration converge on.
- **Two-tier config (T1) is the reader; T3 is the writer.** The global `.oskr/config.json` shape T3 emits (`forge`, `base_branch`, `github.owner`, `forgejo.base_url`) is the subset of project-config keys T1 merges as lower-precedence defaults (project-wins). Keep the `forge` discriminator (**not** `backend`) — code/schema/live config all use `forge`.
- **Seam guard is unaffected.** `bin/oskr-setup.sh` issues no `gh`/`curl`, so `test_backend_no_inline_gh.sh` passes it trivially (it scans for `gh (api|issue|pr|label|project)` and `curl`+`api/v1`, neither present); it is not board-touching, so it need not source `harness-lib.sh`. It must pass `bash -n` (the guard runs it on every `bin/*.sh`).
- **Skill namespace:** the dir `skills/oskr-setup/` surfaces under the plugin as `/oskr:oskr-setup`; the design docs' shorthand is `/oskr-setup`. The `name:` field is `oskr-setup` to honor the contract's literal naming. Mirror `skills/init/SKILL.md` for frontmatter + phase shape.

---

## Definition of Done (frozen contract)

1. **Deliverables:**
   - Create: `bin/oskr-setup.sh` (verbs `skeleton`, `write-config`, `bootstrap`).
   - Create: `tests/scripts/test_oskr_setup.sh` (subshell-fixture, temp-dir asserted; auto-discovered by `run-tests.sh`).
   - Create: `skills/oskr-setup/SKILL.md` (interactive walkthrough).
   - Modify: `docs/harness-config.schema.md` (append the global `.oskr/config.json` shape).
   - Modify: `.claude-plugin/plugin.json` (version bump — new skill).
2. **Testing tier:** unit / hermetic-integration at the `bin/` verb boundary — the umbrella's single Named Seam (subshell + temp-dir fixtures; **no forge shims**, because this slice never touches a forge). Justification: every automatable behavior is "given a clean dir + env, the verb yields these files / this JSON" — pure resolution; the `test_harness_cache.sh` temp-dir-assertion style is exact prior art.
3. **Task granularity:** each task ≤ 5 min implementer work (one verb increment or one doc edit + its test block).
4. **Verification:** every acceptance criterion below has a runnable command (AC→test map). The interactive config-gather and credential-entry are the **only** manual surfaces (verified by guided checklist + grep over the SKILL prose, per the "manual steps are acceptable" principle).
5. **Dependencies:** declared in the final section (cross-task: T1 resolver, T2 registry CLI; shared-file: `plugin.json`).
6. **Harness-task exception (Task 4):** `skills/oskr-setup/SKILL.md` is prose/agent-instruction, not executable code. Per the agent definition it uses **write-acceptance-criterion → grep/structural check → implement** in place of RED-test-first. Flagged explicitly so the reviewer treats the substitution as deliberate.
7. **Playwright exemption (justified):** oskr is a CLI / Claude Code plugin harness with **no web UI** — there is no navigable surface to drive, so no Playwright AC applies. The #27 Q&A carries no Playwright-scope block, consistent with this exemption.
8. **Design-rule ACs (`.claude/rules/`):** no-op — the repo declares no `.claude/rules/` (verified: `Glob .claude/rules/**` → no files). No project design-rule greps to assert.

---

## AC → verification map

| #59 AC | Where satisfied | Runnable check |
|---|---|---|
| (a) clean dir → skeleton dirs + populated config + empty registry | Task 3 `bootstrap` | `bash tests/scripts/test_oskr_setup.sh` (bootstrap block) |
| (b) skeleton creation is a `bin/` verb asserted vs a fixture dir; interactive gather is the only manual part | Task 1 verb + test; Task 4 marks gather manual | `bash tests/scripts/test_oskr_setup.sh` (skeleton block) + `grep -qF 'oskr-setup.sh bootstrap' skills/oskr-setup/SKILL.md` |
| (c) global config captures backend(s)+creds+base branch; re-run guarded (no clobber) | Task 2 config + guard; Task 4 creds instruct-verify | `bash tests/scripts/test_oskr_setup.sh` (write-config + guard blocks) + creds greps in SKILL |
| (d) brain/teach invoked only if present; absence does not block | Task 4 SKILL prose | `grep -qiF 'if present' skills/oskr-setup/SKILL.md` + skip/never-block grep |
| (e) setup ends by pointing to `init` | Task 4 SKILL prose | `grep -qiE 'init.*project #?1' skills/oskr-setup/SKILL.md` |
| (DoD) full suite green incl. untouched `test_harness_config.sh` | Task 5 | `bash tests/scripts/run-tests.sh` |

---

## Task 1: `bin/oskr-setup.sh` — `skeleton` verb (dirs + empty registry)

**Files:**
- Create: `bin/oskr-setup.sh`
- Test: `tests/scripts/test_oskr_setup.sh`

**Acceptance Criteria:**
- [ ] `bin/oskr-setup.sh skeleton <dir>` creates `<dir>/.oskr`, `<dir>/projects`, `<dir>/hjarne`, `<dir>/learning`.
- [ ] It first-creates `<dir>/.oskr/registry.json` as `{"projects": []}` (valid JSON, empty `.projects`).
- [ ] Re-running `skeleton` is idempotent (no error; an existing empty registry is not overwritten).
- [ ] `Run: bash -n bin/oskr-setup.sh` → `Expected: exit 0`, and `Run: bash tests/scripts/test_backend_no_inline_gh.sh` → `Expected: exit 0`.

**Step 1: Write the failing test** — `tests/scripts/test_oskr_setup.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"
SETUP="$REPO_ROOT/bin/oskr-setup.sh"

TMPROOT=$(mktemp -d); trap 'rm -rf "$TMPROOT"' EXIT

# ---- skeleton: dirs + empty registry, asserted against a clean fixture dir ----
WS="$TMPROOT/ws-skel"
"$SETUP" skeleton "$WS"
for d in .oskr projects hjarne learning; do
  test -d "$WS/$d" || { echo "FAIL: skeleton missing dir $d" >&2; exit 1; }
done
test -f "$WS/.oskr/registry.json" || { echo "FAIL: registry.json missing" >&2; exit 1; }
assert_eq "[]" "$(jq -c '.projects' "$WS/.oskr/registry.json")" "registry empty" || exit 1

# idempotent: a second skeleton run must not error or clobber an empty registry
"$SETUP" skeleton "$WS"
assert_eq "[]" "$(jq -c '.projects' "$WS/.oskr/registry.json")" "registry survives re-skeleton" || exit 1

echo "test_oskr_setup skeleton: PASS"
```

**Step 2: Run test to verify it fails**
Run: `bash tests/scripts/test_oskr_setup.sh`
Expected: FAIL — `bin/oskr-setup.sh` does not exist (`No such file or directory` / non-zero exit).

**Step 3: Write minimal implementation** — `bin/oskr-setup.sh`

```bash
#!/usr/bin/env bash
# oskr-setup.sh — workspace-tier bootstrap verbs (skeleton + global config).
# Pure filesystem/JSON; touches NO forge, so it stays OUTSIDE the backend seam
# (no gh/curl). The interactive walkthrough lives in skills/oskr-setup/SKILL.md,
# which gathers config then calls these verbs.
#
# Workspace CREATION anchors at an explicit dir (default $PWD) — it does NOT use
# the upward .oskr/ resolver (blacksmith_workspace_dir), which only FINDS an
# existing workspace. Secrets are NEVER written here (creds live in .env / gh).
set -euo pipefail

_setup_die() { echo "[oskr-setup] $1" >&2; exit 1; }

# Create the workspace skeleton and first-create an empty project registry.
# Idempotent on dirs (mkdir -p) and on the registry (first-create only).
#   skeleton <workspace_dir>
oskr_setup_skeleton() {
  local ws="${1:-$PWD}"
  mkdir -p "$ws/.oskr" "$ws/projects" "$ws/hjarne" "$ws/learning"
  if [[ ! -f "$ws/.oskr/registry.json" ]]; then
    printf '%s\n' '{"projects": []}' > "$ws/.oskr/registry.json"
  fi
}

cmd="${1:-}"; [[ "$#" -gt 0 ]] && shift
case "$cmd" in
  skeleton) oskr_setup_skeleton "$@" ;;
  *)        _setup_die "usage: oskr-setup.sh {skeleton} [workspace_dir]" ;;
esac
```

Then make it executable: `chmod +x bin/oskr-setup.sh`.

**Step 4: Run test to verify it passes**
Run: `bash tests/scripts/test_oskr_setup.sh`
Expected: PASS — prints `test_oskr_setup skeleton: PASS`.
Also Run: `bash tests/scripts/test_backend_no_inline_gh.sh`
Expected: exit 0 (`bash -n` of the new script passes; no inline gh/curl).

**Step 5: Commit** — `feat(oskr-setup): skeleton verb — workspace dirs + empty registry (#59)`

---

## Task 2: `write-config` verb + no-clobber guard

**Files:**
- Modify: `bin/oskr-setup.sh`
- Modify: `tests/scripts/test_oskr_setup.sh`

**Acceptance Criteria:**
- [ ] `write-config <dir>` writes `<dir>/.oskr/config.json` from env (`OSKR_FORGE` default `github`, `OSKR_BASE_BRANCH` default `main`, `OSKR_GITHUB_OWNER`, `OSKR_FORGEJO_BASE_URL`).
- [ ] Emitted config is valid JSON with `.forge`, `.base_branch`, `.github.owner`, `.forgejo.base_url`; **no secret keys** anywhere (no `token`/`password`).
- [ ] A second `write-config` on a configured workspace exits **non-zero** and leaves the existing config **byte-for-byte unchanged**.
- [ ] `write-config` on a dir with no `.oskr/` exits non-zero with a clear `run 'skeleton' first` message.

**Step 1: Write the failing test** — append to `tests/scripts/test_oskr_setup.sh` (before the final `echo`)

```bash
# ---- write-config: populate config.json from env (non-secret) ----
WS2="$TMPROOT/ws-cfg"
"$SETUP" skeleton "$WS2"
OSKR_FORGE=forgejo OSKR_BASE_BRANCH=develop OSKR_FORGEJO_BASE_URL=https://sluice.example \
  "$SETUP" write-config "$WS2"
CFG="$WS2/.oskr/config.json"
jq . "$CFG" >/dev/null || { echo "FAIL: config.json malformed" >&2; exit 1; }
assert_eq "forgejo" "$(jq -r .forge "$CFG")"              "forge"        || exit 1
assert_eq "develop" "$(jq -r .base_branch "$CFG")"        "base_branch"  || exit 1
assert_eq "https://sluice.example" "$(jq -r .forgejo.base_url "$CFG")" "base_url" || exit 1
# secret-hygiene: no token/password keys anywhere in the emitted config
if jq -e '.. | objects | (has("token") or has("password"))' "$CFG" >/dev/null 2>&1; then
  echo "FAIL: secret key written into config.json" >&2; exit 1
fi

# default forge=github when OSKR_FORGE unset
WS3="$TMPROOT/ws-default"
"$SETUP" skeleton "$WS3"; "$SETUP" write-config "$WS3"
assert_eq "github" "$(jq -r .forge "$WS3/.oskr/config.json")" "default forge" || exit 1

# ---- no-clobber guard: re-config refuses + leaves bytes untouched ----
BEFORE=$(cat "$WS3/.oskr/config.json")
if OSKR_FORGE=forgejo "$SETUP" write-config "$WS3" 2>/dev/null; then
  echo "FAIL: re-config did not refuse" >&2; exit 1
fi
assert_eq "$BEFORE" "$(cat "$WS3/.oskr/config.json")" "config not clobbered" || exit 1

# ---- write-config without skeleton errors clearly ----
GUARD_OUT=$("$SETUP" write-config "$TMPROOT/ws-none" 2>&1 || true)
grep -qF "run 'skeleton' first" <<<"$GUARD_OUT" || { echo "FAIL: missing skeleton-first guard" >&2; exit 1; }
```

**Step 2: Run test to verify it fails**
Run: `bash tests/scripts/test_oskr_setup.sh`
Expected: FAIL — `write-config` is an unknown command (`usage: oskr-setup.sh {skeleton}` → non-zero).

**Step 3: Write minimal implementation** — add the function and case to `bin/oskr-setup.sh`

```bash
# Write .oskr/config.json from environment-supplied NON-SECRET values. Guarded:
# refuses if a config already exists so re-running setup never clobbers a live
# workspace. Credentials are NOT written here — they live in the workspace .env
# (FORGEJO_TOKEN) / gh keychain; this records only backend selection + coords.
#   write-config <workspace_dir>
# Env: OSKR_FORGE (default github)  OSKR_BASE_BRANCH (default main)
#      OSKR_GITHUB_OWNER (optional) OSKR_FORGEJO_BASE_URL (optional)
oskr_setup_write_config() {
  local ws="${1:-$PWD}" cfg
  [[ -d "$ws/.oskr" ]] || _setup_die "no .oskr/ at $ws — run 'skeleton' first"
  cfg="$ws/.oskr/config.json"
  [[ -f "$cfg" ]] && _setup_die "workspace already configured ($cfg); not clobbering"
  jq -n \
    --arg forge "${OSKR_FORGE:-github}" \
    --arg base  "${OSKR_BASE_BRANCH:-main}" \
    --arg owner "${OSKR_GITHUB_OWNER:-}" \
    --arg furl  "${OSKR_FORGEJO_BASE_URL:-}" \
    '{version: 1, forge: $forge, base_branch: $base,
      github: {owner: $owner}, forgejo: {base_url: $furl}}' > "$cfg.tmp" \
    && mv "$cfg.tmp" "$cfg"
  jq . "$cfg" >/dev/null || _setup_die "wrote malformed config"
}
```

And extend the dispatch `case`:
```bash
  skeleton)     oskr_setup_skeleton "$@" ;;
  write-config) oskr_setup_write_config "$@" ;;
  *)            _setup_die "usage: oskr-setup.sh {skeleton|write-config} [workspace_dir]" ;;
```

**Step 4: Run test to verify it passes**
Run: `bash tests/scripts/test_oskr_setup.sh`
Expected: PASS.

**Step 5: Commit** — `feat(oskr-setup): write-config verb + no-clobber guard (#59)`

---

## Task 3: `bootstrap` verb (skeleton + config in one command) — realizes AC (a)

**Files:**
- Modify: `bin/oskr-setup.sh`
- Modify: `tests/scripts/test_oskr_setup.sh`

**Acceptance Criteria:**
- [ ] `bootstrap <dir>` on a clean dir produces all four skeleton dirs **and** an empty `{"projects": []}` registry **and** a populated `config.json` in one invocation.
- [ ] `bootstrap` is re-runnable to completion if interrupted before config (skeleton idempotent, config first-create); once configured, a re-`bootstrap` exits non-zero (inherits the guard) without clobbering.

**Step 1: Write the failing test** — append to `tests/scripts/test_oskr_setup.sh`

```bash
# ---- bootstrap: one command yields dirs + registry + config (AC a) ----
WS4="$TMPROOT/ws-boot"
OSKR_FORGE=github OSKR_GITHUB_OWNER=WillyDallas OSKR_BASE_BRANCH=main \
  "$SETUP" bootstrap "$WS4"
for d in .oskr projects hjarne learning; do
  test -d "$WS4/$d" || { echo "FAIL: bootstrap missing dir $d" >&2; exit 1; }
done
assert_eq "[]"         "$(jq -c '.projects' "$WS4/.oskr/registry.json")" "bootstrap registry" || exit 1
assert_eq "WillyDallas" "$(jq -r .github.owner "$WS4/.oskr/config.json")" "bootstrap owner"    || exit 1
assert_eq "github"     "$(jq -r .forge "$WS4/.oskr/config.json")"        "bootstrap forge"     || exit 1

# re-bootstrap on a configured workspace refuses (guard inherited from write-config)
if "$SETUP" bootstrap "$WS4" 2>/dev/null; then echo "FAIL: re-bootstrap did not refuse" >&2; exit 1; fi
```

**Step 2: Run test to verify it fails**
Run: `bash tests/scripts/test_oskr_setup.sh`
Expected: FAIL — `bootstrap` unknown command (non-zero).

**Step 3: Write minimal implementation** — add to `bin/oskr-setup.sh`

```bash
# One-shot: skeleton then write-config. The single verb the skill calls after it
# gathers inputs.  bootstrap <workspace_dir>
oskr_setup_bootstrap() {
  local ws="${1:-$PWD}"
  oskr_setup_skeleton "$ws"
  oskr_setup_write_config "$ws"
}
```

Extend the dispatch `case`:
```bash
  bootstrap)    oskr_setup_bootstrap "$@" ;;
  *)            _setup_die "usage: oskr-setup.sh {skeleton|write-config|bootstrap} [workspace_dir]" ;;
```

**Step 4: Run test to verify it passes**
Run: `bash tests/scripts/test_oskr_setup.sh`
Expected: PASS.

**Step 5: Commit** — `feat(oskr-setup): bootstrap verb (skeleton+config one-shot) (#59)`

---

## Task 4: `skills/oskr-setup/SKILL.md` — interactive walkthrough  *(HARNESS / PROSE TASK)*

**TDD substitution (deliberate, per agent definition):** this deliverable is agent-instruction prose, not executable code. Verification is **write-AC → grep/structural check → implement**, not a RED unit test. Mirror the proven sibling `skills/init/SKILL.md` for frontmatter shape and phase structure; consult the `writing-skills` rubric for the model-invoked-ability vs user-invoked-process distinction before finalizing frontmatter.

**Files:**
- Create: `skills/oskr-setup/SKILL.md`

**Acceptance Criteria (each a grep, run from repo root):**
- [ ] AC4.1 frontmatter present: `Run: grep -qE '^name: oskr-setup$' skills/oskr-setup/SKILL.md` → `Expected: exit 0`
- [ ] AC4.2 calls the verb (skeleton is a bin verb; gather is the only manual part — AC b): `Run: grep -qF 'oskr-setup.sh bootstrap' skills/oskr-setup/SKILL.md` → `Expected: exit 0`
- [ ] AC4.3 captures backend + base branch via the verb's env contract (AC c): `Run: grep -qF 'OSKR_FORGE' skills/oskr-setup/SKILL.md && grep -qF 'OSKR_BASE_BRANCH' skills/oskr-setup/SKILL.md` → `Expected: exit 0`
- [ ] AC4.4 credentials instruct-and-verified into `.env` / gh, never into config (AC c): `Run: grep -qF 'FORGEJO_TOKEN' skills/oskr-setup/SKILL.md && grep -qiE 'gh auth (status|login)' skills/oskr-setup/SKILL.md` → `Expected: exit 0`
- [ ] AC4.5 brain/teach delegated **only if present**, never blocking (AC d): `Run: grep -qiF 'if present' skills/oskr-setup/SKILL.md && grep -qiE 'never block|does not block|skip cleanly' skills/oskr-setup/SKILL.md` → `Expected: exit 0`
- [ ] AC4.6 ends pointing to `init` for project #1 (AC e): `Run: grep -qiE 'init.*project #?1' skills/oskr-setup/SKILL.md` → `Expected: exit 0`
- [ ] AC4.7 no-clobber re-run surfaced to the developer: `Run: grep -qiF 'already' skills/oskr-setup/SKILL.md` → `Expected: exit 0`

**Step 1: Write the acceptance criteria** — the seven greps above (this is the contract; no RED unit test for prose).

**Step 2: Verify they fail**
Run: `grep -qE '^name: oskr-setup$' skills/oskr-setup/SKILL.md; echo $?`
Expected: non-zero — file does not exist yet.

**Step 3: Implement** — `skills/oskr-setup/SKILL.md` (complete content). Note: AC4.6's grep is line-based, so the closing line keeps `init` **and** `project #1` on **one** line.

````markdown
---
name: oskr-setup
description: One-time interactive bootstrap for a fresh oskr workspace. Creates the workspace skeleton (.oskr/, projects/, hjarne/, learning/) via the seam-tested bin/oskr-setup.sh verb, gathers global config (backend + default base branch) into .oskr/config.json, instruct-and-verifies credentials into the workspace .env / gh keychain, delegates brain/teach setup only if those skills are present, and hands off to init for project #1. Run from inside the directory you want to become the workspace control plane.
argument-hint: "(no arguments — interactive)"
allowed-tools: Bash(oskr-setup.sh*) Bash(mkdir *) Bash(jq *) Bash(cat *) Bash(echo *) Bash(test *) Bash(gh auth*) Read Write Edit
---

You are standing up a developer's oskr **workspace** — the control plane that holds
all oskr state, runs once, and is augmented in place. Be interactive: detect what you
can, ask only what you cannot infer, surface the impact of each step before doing it.
Workspace bootstrap happens **once**; project onboarding (`init`) happens many times.

## Phase 0: Pre-flight detection

```bash
WS="${OSKR_WORKSPACE:-$PWD}"
ALREADY=$([ -f "$WS/.oskr/config.json" ] && echo yes || echo no)
GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "")
```

Report in one line each: workspace dir (`$WS`), already-configured (`$ALREADY`), gh user.

**Guard:** if `$ALREADY = yes`, stop: "This directory is **already** an oskr workspace
(`$WS/.oskr/config.json` exists). Re-running setup will not clobber it. To reconfigure,
edit `.oskr/config.json` by hand or remove it first." Do not proceed.

## Phase 1: Gather global config (the only manual part)

Ask one question at a time; pre-fill defaults.

1. **Backend** — "Which forge backend? `github` (default) or `forgejo`?" → `OSKR_FORGE`.
2. **Default base branch** — "Default base branch for new projects? (default: `main`)" → `OSKR_BASE_BRANCH`.
3. If backend is `github`: **owner default** — "Default GitHub owner? (default: `$GH_USER`)" → `OSKR_GITHUB_OWNER`.
4. If backend is `forgejo`: **base URL** — "Forgejo base URL? (e.g. `https://sluice.example`)" → `OSKR_FORGEJO_BASE_URL`.

## Phase 2: Credentials — instruct and verify (never written to config)

Secrets live in the workspace `.env` / the `gh` keychain, **never** in the tracked
`.oskr/config.json`. Gather then verify presence:

- **GitHub:** run `gh auth status`. If not authenticated, instruct `gh auth login`
  (scopes: `repo`, `project`, `read:org`). Verify it returns success before continuing.
- **Forgejo:** instruct the developer to put `FORGEJO_TOKEN=<pat>` in `$WS/.env`, then
  verify: `test -n "$FORGEJO_TOKEN"` (after they `source $WS/.env`). Do not echo the token.

State plainly: credentials are **captured into `.env` / gh**, not into `.oskr/config.json`.

## Phase 3: Create the workspace (seam-tested verb)

Export the gathered values and call the bin verb — this is the seam-tested,
non-interactive core (dirs + empty registry + config in one shot):

```bash
OSKR_FORGE="$OSKR_FORGE" \
OSKR_BASE_BRANCH="${OSKR_BASE_BRANCH:-main}" \
OSKR_GITHUB_OWNER="${OSKR_GITHUB_OWNER:-}" \
OSKR_FORGEJO_BASE_URL="${OSKR_FORGEJO_BASE_URL:-}" \
  oskr-setup.sh bootstrap "$WS"
```

Confirm the result: `.oskr/config.json` populated, `.oskr/registry.json` is
`{"projects": []}`, and `projects/ hjarne/ learning/` exist.

## Phase 4: Brain / teach — delegate only if present, never block

These belong to later Areas (brain #28, teach #30) and may not exist yet.

- **Brain:** **if present** (a brain-setup skill is discoverable), invoke it to populate
  `hjarne/`; otherwise leave the empty `hjarne/` skeleton and say it can be set up when
  Area #28 lands. This **never blocks** setup.
- **Teach:** same rule — **if present**, invoke the teach/learning setup for `learning/`;
  otherwise **skip cleanly**. Their absence never blocks completion.

## Phase 5: Hand off to init

Close by pointing the developer to the next step:

> Workspace ready at `$WS`. Next, run **`init`** from your project directory to onboard **project #1**.
````

**Step 4: Verify all ACs pass**
Run: `grep -qE '^name: oskr-setup$' skills/oskr-setup/SKILL.md && grep -qF 'oskr-setup.sh bootstrap' skills/oskr-setup/SKILL.md && grep -qF 'OSKR_FORGE' skills/oskr-setup/SKILL.md && grep -qF 'OSKR_BASE_BRANCH' skills/oskr-setup/SKILL.md && grep -qF 'FORGEJO_TOKEN' skills/oskr-setup/SKILL.md && grep -qiE 'gh auth (status|login)' skills/oskr-setup/SKILL.md && grep -qiF 'if present' skills/oskr-setup/SKILL.md && grep -qiE 'never block|does not block|skip cleanly' skills/oskr-setup/SKILL.md && grep -qiE 'init.*project #?1' skills/oskr-setup/SKILL.md && grep -qiF 'already' skills/oskr-setup/SKILL.md && echo ALL_AC_PASS`
Expected: prints `ALL_AC_PASS` (exit 0).

**Step 5: Commit** — `feat(oskr-setup): /oskr-setup interactive walkthrough skill (#59)`

---

## Task 5: Schema doc note + version bump + full-suite regression

**Files:**
- Modify: `docs/harness-config.schema.md`
- Modify: `.claude-plugin/plugin.json`

**Acceptance Criteria:**
- [ ] AC5.1 the schema doc documents the global `.oskr/config.json` shape: `Run: grep -qF '.oskr/config.json' docs/harness-config.schema.md` → `Expected: exit 0`
- [ ] AC5.2 the new section reiterates secrets stay out of global config: `Run: grep -qF 'FORGEJO_TOKEN' docs/harness-config.schema.md` → `Expected: exit 0`
- [ ] AC5.3 `plugin.json` version bumped off the `main` baseline `0.3.5` and still valid semver: `Run: V=$(jq -r .version .claude-plugin/plugin.json); [ "$V" != "0.3.5" ] && printf '%s' "$V" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'` → `Expected: exit 0`
- [ ] AC5.4 the whole hermetic suite is green, incl. the new test and the untouched `test_harness_config.sh` regression: `Run: bash tests/scripts/run-tests.sh` → `Expected: exit 0` (`Results: N/N passed, 0 failed`).

**Step 1: Write the checks (no RED unit test — doc/config edits).**

**Step 2: Verify they fail**
Run: `grep -qF '.oskr/config.json' docs/harness-config.schema.md; echo $?`
Expected: non-zero — section not yet added.

**Step 3: Implement**

Append to `docs/harness-config.schema.md` (after the project-tier reference):

`````markdown
## Global config — `.oskr/config.json` (workspace tier)

Written once by `/oskr-setup` (`bin/oskr-setup.sh`); read as the **lower-precedence**
default layer by the two-tier resolver (project `harness-config.json` always wins).
Holds only **non-secret** shared defaults — credentials live in the workspace `.env`
(`FORGEJO_TOKEN`) / the `gh` keychain, never here.

```jsonc
{
  "version": 1,
  "forge": "github",              // default backend for new projects
  "base_branch": "main",          // default base branch
  "github":  { "owner": "" },     // optional default GitHub owner
  "forgejo": { "base_url": "" }   // optional default Forgejo base URL
}
```
`````

Bump `.claude-plugin/plugin.json` `version` from `0.3.5` to the next value (a new skill is
a feature → minor: `0.4.0`). If a sibling child PR on the Area branch already moved the
version, take the next free value instead — AC5.3 only requires "differs from the `0.3.5`
main baseline + valid semver", so a collision is non-fatal.

**Step 4: Verify**
Run: `V=$(jq -r .version .claude-plugin/plugin.json); [ "$V" != "0.3.5" ] && printf '%s' "$V" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' && grep -qF '.oskr/config.json' docs/harness-config.schema.md && grep -qF 'FORGEJO_TOKEN' docs/harness-config.schema.md && echo DOCS_VERSION_OK`
Expected: prints `DOCS_VERSION_OK`.
Run: `bash tests/scripts/run-tests.sh`
Expected: exit 0 — `Results: N/N passed, 0 failed`, including `test_oskr_setup` and an untouched `test_blacksmith_config: PASS`.

**Step 5: Commit** — `docs+chore(oskr-setup): global config schema note + version bump (#59)`

---

## Manual verification (guided checklist — out of automated scope, per the Named Seam)

These cover the interactive surfaces the seam assigns to a checklist, not automated tests:

1. **Clean-dir run:** in a throwaway dir, invoke `/oskr-setup`; answer the gather; confirm `.oskr/config.json` reflects your answers, `.oskr/registry.json` is `{"projects": []}`, and `projects/ hjarne/ learning/` exist.
2. **Re-run guard:** re-invoke `/oskr-setup` in the same dir → it stops with the "already an oskr workspace" message; `config.json` untouched.
3. **gh-auth gate:** with `gh` logged out, confirm Phase 2 blocks on `gh auth status` and resumes after `gh auth login`.
4. **Brain/teach absent:** with no brain/teach skill present, confirm Phase 4 skips cleanly and setup still completes.
5. **Handoff:** confirm the closing message points to `init` for project #1.

(Per `docs/design/platform-reframe.md`, run the real thing against a throwaway clean dir first, **not** against the live `squirrlylabs` workspace, which holds live mail + git infra.)

---

## Dependencies

- **Cross-task (Area #27 DAG):** T3/#59 is `blocked-by` **T1** (workspace-root resolver + two-tier additive config) and **T2** (registry CLI `bin/registry.sh` + relocation). The DAG sequences both before this slice. **By design this plan does not hard-depend on either at runtime:** workspace *creation* anchors at an explicit dir (not T1's upward resolver), and the empty registry is first-created directly as `{"projects": []}` (the same container T2 converges on). If T2's `bin/registry.sh` is present at execution time, prefer delegating the registry first-create to it; the canonical `{"projects": []}` literal is a deliberate, trivial duplication noted here so the reviewer sees it.
- **Reader/writer contract:** T3 is the **writer** of `.oskr/config.json`; T1's two-tier resolver is the **reader**. The emitted shape (`forge`, `base_branch`, `github.owner`, `forgejo.base_url`) is the subset of keys T1 merges as project-wins defaults. Keep `forge` (not `backend`).
- **Shared file (merge hazard):** `.claude-plugin/plugin.json` `version` is bumped by every sibling child PR on the Area branch. The Task 5 AC is tolerant (differs from `0.3.5` + valid semver) specifically to survive that collision; resolve any version conflict by taking the next free value.
- **No forge / no shim:** this slice never touches GitHub or Forgejo, so it needs **no** `gh-shim.sh` / `curl-shim.sh` replay and adds no live-acceptance burden (live Forgejo stays Area 5).
