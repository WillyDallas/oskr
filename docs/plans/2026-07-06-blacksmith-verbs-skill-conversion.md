# Blacksmith Delivery Verbs + Skill Conversion Implementation Plan

**Goal:** Add the 7 missing forge-neutral blacksmith verbs (issue view/close/label-remove, PR create/list-merged/open-exists, repo-create) with hermetic shim-replay coverage on both forges, then convert all 9 delivery-path skills off raw `gh issue`/`gh pr` onto the verbs, guarded against regression.

**Architecture:** Every verb is a one-line `blacksmith_<verb>` dispatcher in `bin/harness-lib.sh` routing via `_blacksmith_dispatch` to `_blacksmith_github_*` / `_blacksmith_forgejo_*` arms — identical to the 20+ existing verbs. Tests are hermetic shim-replay (Named Seam 1: gh-shim + curl-shim + fixtures, asserting request shape and neutral output contract, never internals). Skill conversion is mechanical prose+snippet replacement, locked in by extending `tests/scripts/test_backend_no_inline_gh.sh`.

**Tech Stack:** bash 3.2-compatible shell, `jq`, gh CLI / GitHub REST, Forgejo (Gitea-family) REST over `curl`.

**Issue:** #101

---

## Plan-level contracts and exemptions

- **Testing tier:** hermetic shim-replay only (Named Seam 1). The live `bin/smoke/forgejo-roundtrip.sh` gate (Named Seam 2) is **explicitly excluded** — it belongs to sibling T7 of umbrella #29. This exemption is per the frozen DoD.
- **Playwright exemption:** no Playwright AC in this plan — there is no UI surface. Deliverables are a bash library, shell tests, and markdown skill files. No Q&A Playwright-scope block exists and none is needed.
- **Design-rule ACs:** no `.claude/rules/` directory exists in this repo (verified at plan time) — design-rule ACs are a no-op.
- **Version bump:** this is an Area child under #29. **Do NOT touch `.claude-plugin/plugin.json`** — the land-area PR owns the single bump.
- **TDD substitution:** Tasks 1–3 (shell verbs) use true failing-shim-test-first TDD. Tasks 4–8 (skill markdown + seam-guard) are harness-infrastructure work and use the substituted form *write acceptance criterion → grep/structural check → implement* — noted here deliberately so plan-reviewer knows the exception is intentional.
- **`issue_view` output is a superset of the DoD minimum.** The DoD freezes `{title,body,labels,comments}`; the verb returns `{number, title, state, stateReason, body, labels, comments, url}`. The four extra keys are additive (the frozen minimum is asserted verbatim in tests): `state`/`stateReason` are required by clean-up's shipped/not-planned classification (`skills/clean-up/SKILL.md:54` reads `--json state,stateReason` today) and `url` by its evidence links — without them the seam-guard allowlist could not be empty, contradicting the DoD's own reconciliation note. `stateReason` is `null` on Forgejo (no close-reason concept); GitHub REST casing (lowercase `open`/`closed`, `completed`/`not_planned`) is the neutral baseline.
- **Allowlist is EMPTY.** Every `gh issue`/`gh pr` operation in the 9 delivery skills maps to a verb (existing: `issue_comment`, `issue_add_label`; new: the 7 here). The seam-guard's per-skill negative grep is therefore flat and unconditional. The one residual forge call is `gh api .../parent` in `skills/planning-session/SKILL.md:32` — a `gh api` call, deliberately outside the `\bgh (issue|pr)\b` scan and outside this task's contract (no parent-resolution verb exists yet; follow-up material, already prose-branched per forge in that skill).
- **`issue_close` gets no skill conversion.** No delivery skill calls `gh issue close` today (verified by grep; the two `gh issue close` hits are in `skills/init/SKILL.md`, which is out of scope). The verb ships contract-only, per the scoping-review info note.
- **Dependency graph:** Task 1 → Task 2 → Task 3 are the verb tasks (Task 2 builds on Task 1's dispatchers and shim routes, and both edit `bin/harness-lib.sh` and the two shims). Task 4, 5 depend on Task 1. Task 6, 7 depend on Tasks 1 + 2. Task 8 depends on Tasks 4–7. Tasks 4–7 are mutually independent.

### Verb contracts (neutral JSON, GitHub-REST shape as baseline)

| Verb | Args | Output / rc |
|---|---|---|
| `blacksmith_issue_view` | `<issue#>` | `{number, title, state, stateReason, body, labels:[name], comments:[body], url}`; loud failure |
| `blacksmith_issue_close` | `<issue#> [reason]` | no stdout; reason defaults `completed` (Forgejo accepts-and-ignores it); loud failure |
| `blacksmith_issue_remove_label` | `<issue#> <label>` | no stdout; **never fails the caller** (mirrors `issue_add_label` family; missing label = no-op) |
| `blacksmith_pr_create` | `<head> <base> <title> <body>` | `{number, url}`; loud failure |
| `blacksmith_pr_list_merged` | `<base>` | `[ {number, title, headBranch} ]` (merged only); loud failure |
| `blacksmith_pr_open_exists` | `<head> <base>` | no stdout; rc 0 = an open PR head→base exists, rc 1 otherwise (mirrors `remote_exists`) |
| `blacksmith_repo_create` | `<owner> <repo>` | `{url}`; private repo; Forgejo routes org-owned (`POST /orgs/{owner}/repos`) vs user-owned (`POST /user/repos`) by comparing `<owner>` to `GET /user`'s login; loud failure |

Single-page caps (`per_page=100` / `limit=100`) match the existing arms (`list_issues`, `pr_open_count`) and are documented in each function header.

---

## Task 1: Issue verbs — `issue_view`, `issue_close`, `issue_remove_label`

**Files:**
- Modify: `bin/harness-lib.sh`
- Modify: `tests/scripts/lib/gh-shim.sh` (comments route)
- Modify: `tests/scripts/lib/curl-shim.sh` (comments fixture opt-in)
- Create: `tests/scripts/fixtures/gh-issue-view.json`, `tests/scripts/fixtures/gh-issue-comments.json`, `tests/scripts/fixtures/forgejo-issue-view.json`, `tests/scripts/fixtures/forgejo-issue-comments.json`, `tests/scripts/fixtures/forgejo-issue-labels.json`
- Test: `tests/scripts/test_blacksmith_issue_ops.sh`

**Acceptance Criteria:**
- [ ] Run: `bash tests/scripts/test_blacksmith_issue_ops.sh` → Expected: exit 0, last line `test_blacksmith_issue_ops: PASS`
- [ ] Run: `bash -c 'source bin/harness-lib.sh 2>/dev/null; declare -F _blacksmith_github_issue_view _blacksmith_forgejo_issue_view _blacksmith_github_issue_close _blacksmith_forgejo_issue_close _blacksmith_github_issue_remove_label _blacksmith_forgejo_issue_remove_label >/dev/null'` → Expected: exit 0 (both arms exist for all three verbs)
- [ ] Loud-failure AC (inside the test): dispatching `blacksmith_issue_view` under a config with `"forge":"gitlab"` exits non-zero and stderr contains `has no implementation for 'issue_view'` → Expected: covered by the test's final section, so the first AC's exit 0 proves it
- [ ] Run: `bash tests/scripts/test_backend_no_inline_gh.sh` → Expected: exit 0 (harness-lib still parses; no seam violation introduced)

**Step 1: Write the failing test**

Create `tests/scripts/test_blacksmith_issue_ops.sh`:

```bash
#!/usr/bin/env bash
# Issue delivery verbs (#101): issue_view / issue_close / issue_remove_label on
# both forges, hermetic via gh-shim + curl-shim. Asserts request shape + the
# neutral output contract only — never internals. Also proves the loud dispatch
# failure for a forge with no implementation.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB="$REPO_ROOT/bin/harness-lib.sh"
FIX="$REPO_ROOT/tests/scripts/fixtures"
source "$SCRIPT_DIR/lib/assert.sh"

SHIM_DIR=$(mktemp -d); trap 'rm -rf "$SHIM_DIR"' EXIT
cp "$SCRIPT_DIR/lib/gh-shim.sh"   "$SHIM_DIR/gh";   chmod +x "$SHIM_DIR/gh"
cp "$SCRIPT_DIR/lib/curl-shim.sh" "$SHIM_DIR/curl"; chmod +x "$SHIM_DIR/curl"

gh_run() {  # $1 = call log, $2 = verb expression
  PATH="$SHIM_DIR:$PATH" HARNESS_CONFIG="$FIX/harness-config.sample.json" \
  GH_SHIM_CALL_LOG="$1" GH_SHIM_FIXTURE="$FIX/gh-project-discovery.json" \
  GH_SHIM_ISSUE_FIXTURE="$FIX/gh-issue-view.json" \
  GH_SHIM_COMMENTS_FIXTURE="$FIX/gh-issue-comments.json" \
  bash -c "source '$LIB'; $2"
}
fj_run() {  # $1 = call log, $2 = verb expression
  PATH="$SHIM_DIR:$PATH" HARNESS_CONFIG="$FIX/harness-config.forgejo.json" FORGEJO_TOKEN="test-token" \
  CURL_SHIM_CALL_LOG="$1" CURL_SHIM_ISSUE_FIXTURE="$FIX/forgejo-issue-view.json" \
  CURL_SHIM_COMMENTS_FIXTURE="$FIX/forgejo-issue-comments.json" \
  CURL_SHIM_ISSUE_LABELS_FIXTURE="$FIX/forgejo-issue-labels.json" \
  bash -c "source '$LIB'; $2"
}

# --- issue_view: GitHub -------------------------------------------------------
L="$SHIM_DIR/gh-view.log"; : > "$L"
out=$(gh_run "$L" "blacksmith_issue_view 61")
# The DoD-frozen minimum keys, asserted verbatim:
assert_eq 'Fix the widget'  "$(jq -r '.title' <<<"$out")"          "gh issue_view: title" || exit 1
assert_eq '## What
Fix it.' "$(jq -r '.body' <<<"$out")"                              "gh issue_view: body" || exit 1
assert_eq '["area/pipeline","dispatch-incomplete"]' "$(jq -c '.labels' <<<"$out")" "gh issue_view: labels are names" || exit 1
assert_eq '["## Research Digest
findings","## Implementation Plan
plan"]' "$(jq -c '.comments' <<<"$out")"                           "gh issue_view: comments are bodies" || exit 1
# The additive keys (clean-up classification + evidence link):
assert_eq 'closed'    "$(jq -r '.state' <<<"$out")"                "gh issue_view: state (REST lowercase)" || exit 1
assert_eq 'completed' "$(jq -r '.stateReason' <<<"$out")"          "gh issue_view: stateReason" || exit 1
assert_eq '61'        "$(jq -r '.number' <<<"$out")"               "gh issue_view: number" || exit 1
assert_eq 'https://github.com/WillyDallas/oskr/issues/61' "$(jq -r '.url' <<<"$out")" "gh issue_view: url" || exit 1
# Request shape: the issue read and the comments read.
grep -qE 'gh api repos/WillyDallas/oskr/issues/61( |$)' "$L" || { echo "FAIL: no issue GET" >&2; exit 1; }
grep -qF 'issues/61/comments' "$L" || { echo "FAIL: no comments GET" >&2; exit 1; }

# --- issue_view: Forgejo (same neutral shape; stateReason null) -----------------
L="$SHIM_DIR/fj-view.log"; : > "$L"
out=$(fj_run "$L" "blacksmith_issue_view 61")
assert_eq 'Fix the widget' "$(jq -r '.title' <<<"$out")"           "fj issue_view: title" || exit 1
assert_eq '["area/pipeline","dispatch-incomplete"]' "$(jq -c '.labels' <<<"$out")" "fj issue_view: labels" || exit 1
assert_eq '["## Research Digest
findings"]' "$(jq -c '.comments' <<<"$out")"                       "fj issue_view: comments" || exit 1
assert_eq 'closed' "$(jq -r '.state' <<<"$out")"                   "fj issue_view: state" || exit 1
assert_eq 'null'   "$(jq -r '.stateReason' <<<"$out")"             "fj issue_view: stateReason null (no close reasons)" || exit 1
# Identical key set on both forges — the contract IS the shape.
assert_eq '["body","comments","labels","number","state","stateReason","title","url"]' \
  "$(jq -c 'keys' <<<"$out")" "fj issue_view: neutral key set" || exit 1
grep -qF '/repos/squirrlylabs/sluice/issues/61' "$L" || { echo "FAIL: no fj issue GET" >&2; exit 1; }
grep -qF '/issues/61/comments' "$L" || { echo "FAIL: no fj comments GET" >&2; exit 1; }

# --- issue_close ---------------------------------------------------------------
L="$SHIM_DIR/gh-close.log"; : > "$L"
gh_run "$L" "blacksmith_issue_close 61" >/dev/null
grep -qF 'issues/61' "$L" && grep -qF 'PATCH' "$L" || { echo "FAIL: gh close not a PATCH on the issue" >&2; exit 1; }
grep -qF 'state=closed' "$L"              || { echo "FAIL: gh close missing state=closed" >&2; exit 1; }
grep -qF 'state_reason=completed' "$L"    || { echo "FAIL: gh close missing default state_reason" >&2; exit 1; }
L="$SHIM_DIR/gh-close2.log"; : > "$L"
gh_run "$L" "blacksmith_issue_close 61 not_planned" >/dev/null
grep -qF 'state_reason=not_planned' "$L"  || { echo "FAIL: gh close reason arg not honored" >&2; exit 1; }

L="$SHIM_DIR/fj-close.log"; : > "$L"
fj_run "$L" "blacksmith_issue_close 61" >/dev/null
grep -qF 'PATCH' "$L" && grep -qF '/issues/61' "$L" || { echo "FAIL: fj close not a PATCH" >&2; exit 1; }
grep -qF '"state":"closed"' "$L"          || { echo "FAIL: fj close missing state body" >&2; exit 1; }

# --- issue_remove_label ----------------------------------------------------------
L="$SHIM_DIR/gh-rmlabel.log"; : > "$L"
gh_run "$L" "blacksmith_issue_remove_label 61 dispatch-incomplete" >/dev/null
grep -qF 'DELETE' "$L" && grep -qF 'issues/61/labels/dispatch-incomplete' "$L" \
  || { echo "FAIL: gh remove_label not a DELETE by name" >&2; exit 1; }

L="$SHIM_DIR/fj-rmlabel.log"; : > "$L"
fj_run "$L" "blacksmith_issue_remove_label 61 dispatch-incomplete" >/dev/null
# Forgejo removes BY LABEL ID: name resolved to id 12 off the fixture, then DELETE.
grep -qF 'DELETE' "$L" && grep -qF '/issues/61/labels/12' "$L" \
  || { echo "FAIL: fj remove_label did not resolve name->id 12 and DELETE" >&2; exit 1; }

# --- loud dispatch failure (missing impl) ----------------------------------------
UNKNOWN_CFG="$SHIM_DIR/harness-config.gitlab.json"
printf '{"forge":"gitlab"}' > "$UNKNOWN_CFG"
if HARNESS_CONFIG="$UNKNOWN_CFG" bash -c "source '$LIB'; blacksmith_issue_view 1" 2>"$SHIM_DIR/dispatch.err"; then
  echo "FAIL: issue_view dispatched for a forge with no implementation" >&2; exit 1
fi
grep -qF "has no implementation for 'issue_view'" "$SHIM_DIR/dispatch.err" \
  || { echo "FAIL: missing-impl error not loud" >&2; cat "$SHIM_DIR/dispatch.err" >&2; exit 1; }

echo "test_blacksmith_issue_ops: PASS"
```

Create the fixtures:

`tests/scripts/fixtures/gh-issue-view.json`:
```json
{
  "number": 61,
  "title": "Fix the widget",
  "state": "closed",
  "state_reason": "completed",
  "body": "## What\nFix it.",
  "html_url": "https://github.com/WillyDallas/oskr/issues/61",
  "labels": [{"name": "area/pipeline"}, {"name": "dispatch-incomplete"}]
}
```

`tests/scripts/fixtures/gh-issue-comments.json`:
```json
[
  {"body": "## Research Digest\nfindings"},
  {"body": "## Implementation Plan\nplan"}
]
```

`tests/scripts/fixtures/forgejo-issue-view.json`:
```json
{
  "number": 61,
  "title": "Fix the widget",
  "state": "closed",
  "body": "## What\nFix it.",
  "html_url": "https://git.squirrlylabs.dev/squirrlylabs/sluice/issues/61",
  "labels": [{"id": 9, "name": "area/pipeline"}, {"id": 12, "name": "dispatch-incomplete"}]
}
```

`tests/scripts/fixtures/forgejo-issue-comments.json`:
```json
[
  {"body": "## Research Digest\nfindings"}
]
```

`tests/scripts/fixtures/forgejo-issue-labels.json`:
```json
[{"id": 9, "name": "area/pipeline"}, {"id": 12, "name": "dispatch-incomplete"}]
```

**Step 2: Run test to verify it fails**

Run: `bash tests/scripts/test_blacksmith_issue_ops.sh`
Expected: FAIL — non-zero exit with `blacksmith_issue_view: command not found` (the verb does not exist yet).

**Step 3: Write minimal implementation**

3a. In `bin/harness-lib.sh`, after the `blacksmith_list_issues` / `blacksmith_create_milestone` dispatcher block (~line 167), add:

```bash
# #101 delivery verbs: issue read/close/label-remove, PR create/list/probe,
# repo create — the last raw-gh ops the delivery skills needed.
blacksmith_issue_view()         { _blacksmith_dispatch issue_view "$@"; }
blacksmith_issue_close()        { _blacksmith_dispatch issue_close "$@"; }
blacksmith_issue_remove_label() { _blacksmith_dispatch issue_remove_label "$@"; }
blacksmith_pr_create()          { _blacksmith_dispatch pr_create "$@"; }
blacksmith_pr_list_merged()     { _blacksmith_dispatch pr_list_merged "$@"; }
blacksmith_pr_open_exists()     { _blacksmith_dispatch pr_open_exists "$@"; }
blacksmith_repo_create()        { _blacksmith_dispatch repo_create "$@"; }
```

(All seven public dispatchers land here in Task 1; Tasks 2–3 add only the per-forge arms. A dispatcher whose arms are missing hits the existing loud `_blacksmith_dispatch` failure — never a silent no-op.)

3b. GitHub arms — add in the GitHub backend section, after `_blacksmith_github_list_issues`:

```bash
# --- Issue read/close/label-remove (delivery verbs; #101) --------------------

# Echo one issue in the neutral shape:
#   { number, title, state, stateReason, body, labels:[name], comments:[body], url }
# Superset of the #101 minimum {title,body,labels,comments}: state/stateReason back
# clean-up's shipped/not-planned classification; url backs its evidence links.
# GitHub-REST casing is the neutral baseline (state lowercase; stateReason
# completed|not_planned|null — null on forges without close reasons).
# Comments: first 100 (single page, matching list_issues' cap), oldest first —
# "most recent" = last.   issue_view <issue_number>
_blacksmith_github_issue_view() {
  local issue="$1" owner repo raw comments
  owner=$(blacksmith_config_get '.github.owner') || return 1
  repo=$(blacksmith_config_get '.github.repo')   || return 1
  raw=$(gh api "repos/${owner}/${repo}/issues/${issue}" 2>/dev/null) \
    || { _blacksmith_die "issue_view: cannot read #$issue"; return 1; }
  comments=$(gh api "repos/${owner}/${repo}/issues/${issue}/comments?per_page=100" 2>/dev/null) || comments='[]'
  jq -c --argjson c "$comments" '{
      number, title, state,
      stateReason: (.state_reason // null),
      body: (.body // ""),
      labels: [ (.labels // [])[] | .name ],
      comments: [ $c[] | .body ],
      url: .html_url
    }' <<<"$raw"
}

# Close an issue. reason = GitHub state_reason (completed | not_planned), default
# completed; the Forgejo arm accepts-and-ignores it (no close-reason concept).
# Side-effect op; no stdout; loud failure.   issue_close <issue> [reason]
_blacksmith_github_issue_close() {
  local issue="$1" reason="${2:-completed}" owner repo
  owner=$(blacksmith_config_get '.github.owner') || return 1
  repo=$(blacksmith_config_get '.github.repo')   || return 1
  gh api "repos/${owner}/${repo}/issues/${issue}" -X PATCH -f state=closed -f state_reason="$reason" >/dev/null 2>&1 \
    || { _blacksmith_die "issue_close: failed to close #$issue"; return 1; }
}

# Remove a label from an issue by NAME (never fails the caller — mirrors the
# issue_add_label family; an absent label is a no-op).
#   issue_remove_label <issue> <label>
_blacksmith_github_issue_remove_label() {
  local issue="$1" label="$2" owner repo
  owner=$(blacksmith_config_get '.github.owner') || return 1
  repo=$(blacksmith_config_get '.github.repo')   || return 1
  gh api -X DELETE "repos/${owner}/${repo}/issues/${issue}/labels/${label}" >/dev/null 2>&1 || true
}
```

3c. Forgejo arms — add in the Forgejo backend section, after `_blacksmith_forgejo_list_issues`:

```bash
# --- Issue read/close/label-remove (delivery verbs; #101) --------------------

# Same neutral shape as the GitHub arm. Forgejo has no close reason, so
# stateReason is always null here.   issue_view <issue_number>
_blacksmith_forgejo_issue_view() {
  local issue="$1" owner repo raw comments
  owner=$(blacksmith_config_get '.forgejo.owner') || return 1
  repo=$(blacksmith_config_get '.forgejo.repo')   || return 1
  raw=$(_blacksmith_forgejo_curl GET "/repos/${owner}/${repo}/issues/${issue}") \
    || { _blacksmith_die "issue_view (forgejo): cannot read #$issue"; return 1; }
  comments=$(_blacksmith_forgejo_curl GET "/repos/${owner}/${repo}/issues/${issue}/comments" 2>/dev/null) || comments='[]'
  jq -c --argjson c "$comments" '{
      number, title, state,
      stateReason: null,
      body: (.body // ""),
      labels: [ (.labels // [])[] | .name ],
      comments: [ $c[] | .body ],
      url: .html_url
    }' <<<"$raw"
}

# Close an issue (reason accepted-and-ignored — Forgejo has no close reason).
_blacksmith_forgejo_issue_close() {
  local issue="$1" owner repo
  owner=$(blacksmith_config_get '.forgejo.owner') || return 1
  repo=$(blacksmith_config_get '.forgejo.repo')   || return 1
  _blacksmith_forgejo_curl PATCH "/repos/${owner}/${repo}/issues/${issue}" \
    "$(jq -nc '{state: "closed"}')" >/dev/null \
    || { _blacksmith_die "issue_close (forgejo): failed to close #$issue"; return 1; }
}

# Remove a label by NAME. Forgejo deletes BY LABEL ID, so resolve name -> id off
# the issue's labels first (same id-resolution archive_item uses). Never fails
# the caller; unresolvable name = no-op.
_blacksmith_forgejo_issue_remove_label() {
  local issue="$1" label="$2" owner repo lid
  owner=$(blacksmith_config_get '.forgejo.owner') || return 1
  repo=$(blacksmith_config_get '.forgejo.repo')   || return 1
  lid=$(_blacksmith_forgejo_curl GET "/repos/${owner}/${repo}/issues/${issue}/labels" 2>/dev/null \
        | jq -r --arg n "$label" '[.[] | select(.name == $n)][0].id // empty')
  [[ -n "$lid" ]] || return 0
  _blacksmith_forgejo_curl DELETE "/repos/${owner}/${repo}/issues/${issue}/labels/${lid}" >/dev/null 2>&1 || true
}
```

3d. Shim routes. In `tests/scripts/lib/gh-shim.sh`, insert **before** the existing `*"/issues/"*` route (currently the second-to-last route):

```bash
if [[ "$args" == *"/comments"* && -n "${GH_SHIM_COMMENTS_FIXTURE:-}" ]]; then  # GET issue comments (issue_view)
  emit < "$GH_SHIM_COMMENTS_FIXTURE"; exit 0
fi
```

In `tests/scripts/lib/curl-shim.sh`, replace the comments route body (currently unconditionally `echo '{"id":1}'`) with a fixture opt-in:

```bash
if [[ "$args" == */issues/*/comments* ]]; then          # comments: GET (issue_view) / POST (comment)
  [[ -n "${CURL_SHIM_COMMENTS_FIXTURE:-}" ]] && { cat "$CURL_SHIM_COMMENTS_FIXTURE"; exit 0; }
  echo '{"id":1}'; exit 0
fi
```

**Step 4: Run test to verify it passes**

Run: `bash tests/scripts/test_blacksmith_issue_ops.sh`
Expected: PASS

Run: `bash tests/scripts/run-tests.sh`
Expected: exit 0 — the shim edits must not break any existing test (the comments/fixture routes are opt-in via new env vars).

**Step 5: Commit**

`git commit` message: `feat(blacksmith): issue_view / issue_close / issue_remove_label on both forges (#101)`

---

## Task 2: PR verbs — `pr_create`, `pr_list_merged`, `pr_open_exists`

**Depends on:** Task 1 (dispatchers and shim routes land there; same three files edited).

**Files:**
- Modify: `bin/harness-lib.sh`
- Modify: `tests/scripts/lib/gh-shim.sh` (pulls route), `tests/scripts/lib/curl-shim.sh` (pulls route)
- Create: `tests/scripts/fixtures/gh-pull-create.json`, `tests/scripts/fixtures/gh-pulls-closed.json`, `tests/scripts/fixtures/gh-pulls-open.json`, `tests/scripts/fixtures/forgejo-pull-create.json`, `tests/scripts/fixtures/forgejo-pulls-closed.json`, `tests/scripts/fixtures/forgejo-pulls-open.json`
- Test: `tests/scripts/test_blacksmith_pr_ops.sh`

**Acceptance Criteria:**
- [ ] Run: `bash tests/scripts/test_blacksmith_pr_ops.sh` → Expected: exit 0, last line `test_blacksmith_pr_ops: PASS`
- [ ] Run: `bash -c 'source bin/harness-lib.sh 2>/dev/null; declare -F _blacksmith_github_pr_create _blacksmith_forgejo_pr_create _blacksmith_github_pr_list_merged _blacksmith_forgejo_pr_list_merged _blacksmith_github_pr_open_exists _blacksmith_forgejo_pr_open_exists >/dev/null'` → Expected: exit 0
- [ ] Run: `bash tests/scripts/run-tests.sh` → Expected: exit 0

**Step 1: Write the failing test**

Create `tests/scripts/test_blacksmith_pr_ops.sh` (repo_create coverage joins this file in Task 3 — one file covers the non-issue write verbs):

```bash
#!/usr/bin/env bash
# PR delivery verbs (#101): pr_create / pr_list_merged / pr_open_exists on both
# forges, hermetic via gh-shim + curl-shim. Task 3 appends repo_create coverage.
# Asserts request shape + neutral output contract only — never internals.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB="$REPO_ROOT/bin/harness-lib.sh"
FIX="$REPO_ROOT/tests/scripts/fixtures"
source "$SCRIPT_DIR/lib/assert.sh"

SHIM_DIR=$(mktemp -d); trap 'rm -rf "$SHIM_DIR"' EXIT
cp "$SCRIPT_DIR/lib/gh-shim.sh"   "$SHIM_DIR/gh";   chmod +x "$SHIM_DIR/gh"
cp "$SCRIPT_DIR/lib/curl-shim.sh" "$SHIM_DIR/curl"; chmod +x "$SHIM_DIR/curl"

gh_run() {  # $1 = call log, $2 = pulls fixture, $3 = verb expression
  PATH="$SHIM_DIR:$PATH" HARNESS_CONFIG="$FIX/harness-config.sample.json" \
  GH_SHIM_CALL_LOG="$1" GH_SHIM_FIXTURE="$FIX/gh-project-discovery.json" \
  GH_SHIM_PULLS_FIXTURE="$2" \
  bash -c "source '$LIB'; $3"
}
fj_run() {  # $1 = call log, $2 = pulls fixture, $3 = verb expression
  PATH="$SHIM_DIR:$PATH" HARNESS_CONFIG="$FIX/harness-config.forgejo.json" FORGEJO_TOKEN="test-token" \
  CURL_SHIM_CALL_LOG="$1" CURL_SHIM_PULLS_FIXTURE="$2" \
  bash -c "source '$LIB'; $3"
}

# --- pr_create: GitHub ----------------------------------------------------------
L="$SHIM_DIR/gh-create.log"; : > "$L"
out=$(gh_run "$L" "$FIX/gh-pull-create.json" \
      "blacksmith_pr_create 'feature/61-widget' 'area/pipeline' 'Fix the widget' 'PR body'")
assert_eq '88' "$(jq -r '.number' <<<"$out")"                                "gh pr_create: number" || exit 1
assert_eq 'https://github.com/WillyDallas/oskr/pull/88' "$(jq -r '.url' <<<"$out")" "gh pr_create: url" || exit 1
assert_eq '["number","url"]' "$(jq -c 'keys' <<<"$out")"                     "gh pr_create: neutral keys only" || exit 1
grep -qF 'repos/WillyDallas/oskr/pulls' "$L"  || { echo "FAIL: gh pr_create wrong endpoint" >&2; exit 1; }
grep -qF 'head=feature/61-widget' "$L"        || { echo "FAIL: head not sent" >&2; exit 1; }
grep -qF 'base=area/pipeline' "$L"            || { echo "FAIL: base not sent" >&2; exit 1; }
grep -qF 'title=Fix the widget' "$L"          || { echo "FAIL: title not sent" >&2; exit 1; }
grep -qF 'body=PR body' "$L"                  || { echo "FAIL: body not sent" >&2; exit 1; }

# --- pr_create: Forgejo -----------------------------------------------------------
L="$SHIM_DIR/fj-create.log"; : > "$L"
out=$(fj_run "$L" "$FIX/forgejo-pull-create.json" \
      "blacksmith_pr_create 'feature/61-widget' 'area/pipeline' 'Fix the widget' 'PR body'")
assert_eq '88' "$(jq -r '.number' <<<"$out")"            "fj pr_create: number" || exit 1
assert_eq '["number","url"]' "$(jq -c 'keys' <<<"$out")" "fj pr_create: neutral keys only" || exit 1
grep -qF '/repos/squirrlylabs/sluice/pulls' "$L" || { echo "FAIL: fj pr_create wrong endpoint" >&2; exit 1; }
grep -qF '"head":"feature/61-widget"' "$L"       || { echo "FAIL: fj head not sent" >&2; exit 1; }
grep -qF '"base":"area/pipeline"' "$L"           || { echo "FAIL: fj base not sent" >&2; exit 1; }

# --- pr_list_merged: GitHub (server-side base filter; merged_at != null) ---------
L="$SHIM_DIR/gh-merged.log"; : > "$L"
out=$(gh_run "$L" "$FIX/gh-pulls-closed.json" "blacksmith_pr_list_merged 'area/pipeline'")
assert_eq '[{"number":71,"title":"Task 1","headBranch":"feature/61-widget"},{"number":73,"title":"Task 3","headBranch":"feature/63-seam"}]' \
  "$(jq -c '.' <<<"$out")" "gh pr_list_merged: merged-only neutral list" || exit 1
grep -qF 'pulls?base=area/pipeline&state=closed' "$L" || { echo "FAIL: gh merged-list request shape" >&2; exit 1; }

# --- pr_list_merged: Forgejo (client-side base filter; merged flag) ---------------
L="$SHIM_DIR/fj-merged.log"; : > "$L"
out=$(fj_run "$L" "$FIX/forgejo-pulls-closed.json" "blacksmith_pr_list_merged 'area/pipeline'")
assert_eq '[{"number":71,"title":"Task 1","headBranch":"feature/61-widget"}]' \
  "$(jq -c '.' <<<"$out")" "fj pr_list_merged: merged + base-filtered" || exit 1
grep -qF 'pulls?state=closed' "$L" || { echo "FAIL: fj merged-list request shape" >&2; exit 1; }

# --- pr_open_exists: probe semantics (rc 0 = exists, rc 1 = absent) ---------------
L="$SHIM_DIR/gh-open.log"; : > "$L"
gh_run "$L" "$FIX/gh-pulls-open.json" "blacksmith_pr_open_exists 'area/pipeline' 'main'" \
  || { echo "FAIL: gh pr_open_exists rc!=0 for an existing open PR" >&2; exit 1; }
# GitHub's head filter requires the owner: prefix.
grep -qF 'head=WillyDallas:area/pipeline' "$L" || { echo "FAIL: gh head filter missing owner: prefix" >&2; exit 1; }
grep -qF 'base=main' "$L" && grep -qF 'state=open' "$L" || { echo "FAIL: gh open-probe request shape" >&2; exit 1; }
EMPTY="$SHIM_DIR/empty.json"; printf '[]' > "$EMPTY"
if gh_run "$SHIM_DIR/gh-open2.log" "$EMPTY" "blacksmith_pr_open_exists 'area/pipeline' 'main'"; then
  echo "FAIL: gh pr_open_exists rc 0 with no open PR" >&2; exit 1
fi

fj_run "$SHIM_DIR/fj-open.log" "$FIX/forgejo-pulls-open.json" "blacksmith_pr_open_exists 'area/pipeline' 'main'" \
  || { echo "FAIL: fj pr_open_exists rc!=0 for an existing open PR" >&2; exit 1; }
if fj_run "$SHIM_DIR/fj-open2.log" "$EMPTY" "blacksmith_pr_open_exists 'area/pipeline' 'main'"; then
  echo "FAIL: fj pr_open_exists rc 0 with no open PR" >&2; exit 1
fi

echo "test_blacksmith_pr_ops: PASS"
```

Create the fixtures:

`tests/scripts/fixtures/gh-pull-create.json`:
```json
{"number": 88, "html_url": "https://github.com/WillyDallas/oskr/pull/88", "title": "Fix the widget"}
```

`tests/scripts/fixtures/gh-pulls-closed.json` (one closed-unmerged PR proves the merged filter):
```json
[
  {"number": 71, "title": "Task 1", "merged_at": "2026-07-01T00:00:00Z", "head": {"ref": "feature/61-widget"}, "base": {"ref": "area/pipeline"}},
  {"number": 72, "title": "Task 2", "merged_at": null, "head": {"ref": "feature/62-abandoned"}, "base": {"ref": "area/pipeline"}},
  {"number": 73, "title": "Task 3", "merged_at": "2026-07-02T00:00:00Z", "head": {"ref": "feature/63-seam"}, "base": {"ref": "area/pipeline"}}
]
```

`tests/scripts/fixtures/gh-pulls-open.json`:
```json
[{"number": 90, "title": "Area PR", "head": {"ref": "area/pipeline"}, "base": {"ref": "main"}}]
```

`tests/scripts/fixtures/forgejo-pull-create.json`:
```json
{"number": 88, "html_url": "https://git.squirrlylabs.dev/squirrlylabs/sluice/pulls/88", "title": "Fix the widget"}
```

`tests/scripts/fixtures/forgejo-pulls-closed.json` (a wrong-base merged PR proves the client-side base filter):
```json
[
  {"number": 71, "title": "Task 1", "merged": true, "head": {"ref": "feature/61-widget"}, "base": {"ref": "area/pipeline"}},
  {"number": 72, "title": "Task 2", "merged": false, "head": {"ref": "feature/62-abandoned"}, "base": {"ref": "area/pipeline"}},
  {"number": 74, "title": "Other area", "merged": true, "head": {"ref": "feature/70-other"}, "base": {"ref": "area/other"}}
]
```

`tests/scripts/fixtures/forgejo-pulls-open.json`:
```json
[{"number": 90, "title": "Area PR", "head": {"ref": "area/pipeline"}, "base": {"ref": "main"}}]
```

**Step 2: Run test to verify it fails**

Run: `bash tests/scripts/test_blacksmith_pr_ops.sh`
Expected: FAIL — non-zero exit; `_blacksmith_dispatch` dies with `forge 'github' has no implementation for 'pr_create'` (the public dispatchers exist from Task 1; the arms do not).

**Step 3: Write minimal implementation**

3a. GitHub arms (after the Task 1 issue-verb block in the GitHub section):

```bash
# --- PR create / list-merged / open-probe (delivery verbs; #101) --------------

# Open a PR; echoes the neutral { number, url }. The head branch must already be
# pushed (REST create does not push). pr_create <head> <base> <title> <body>
_blacksmith_github_pr_create() {
  local head="$1" base="$2" title="$3" body="${4:-}" owner repo raw
  [[ -n "$head" && -n "$base" && -n "$title" ]] || { _blacksmith_die "pr_create: head, base and title required"; return 1; }
  owner=$(blacksmith_config_get '.github.owner') || return 1
  repo=$(blacksmith_config_get '.github.repo')   || return 1
  raw=$(gh api "repos/${owner}/${repo}/pulls" -f head="$head" -f base="$base" -f title="$title" -f body="$body" 2>/dev/null) \
    || { _blacksmith_die "pr_create: failed ($head -> $base)"; return 1; }
  jq -c '{number, url: .html_url}' <<<"$raw"
}

# Echo the MERGED PRs whose base is <base>, as [ { number, title, headBranch } ].
# GitHub filters base server-side; merged = merged_at set (state=closed includes
# unmerged closures). Single page (100), matching the other list verbs' cap.
#   pr_list_merged <base>
_blacksmith_github_pr_list_merged() {
  local base="$1" owner repo raw
  [[ -n "$base" ]] || { _blacksmith_die "pr_list_merged: base branch required"; return 1; }
  owner=$(blacksmith_config_get '.github.owner') || return 1
  repo=$(blacksmith_config_get '.github.repo')   || return 1
  raw=$(gh api "repos/${owner}/${repo}/pulls?base=${base}&state=closed&per_page=100" 2>/dev/null) \
    || { _blacksmith_die "pr_list_merged: query failed for base $base"; return 1; }
  jq -c '[ .[] | select(.merged_at != null) | {number, title, headBranch: .head.ref} ]' <<<"$raw"
}

# Probe: does an OPEN PR <head> -> <base> exist? rc 0 = yes, non-zero = no
# (mirrors remote_exists; no stdout). GitHub's head filter needs owner:branch.
#   pr_open_exists <head> <base>
_blacksmith_github_pr_open_exists() {
  local head="$1" base="$2" owner repo n
  [[ -n "$head" && -n "$base" ]] || { _blacksmith_die "pr_open_exists: head and base required"; return 1; }
  owner=$(blacksmith_config_get '.github.owner') || return 1
  repo=$(blacksmith_config_get '.github.repo')   || return 1
  n=$(gh api "repos/${owner}/${repo}/pulls?head=${owner}:${head}&base=${base}&state=open" --jq 'length' 2>/dev/null) || n=0
  [[ "$n" -gt 0 ]]
}
```

3b. Forgejo arms (after the Task 1 issue-verb block in the Forgejo section):

```bash
# --- PR create / list-merged / open-probe (delivery verbs; #101) --------------

_blacksmith_forgejo_pr_create() {
  local head="$1" base="$2" title="$3" body="${4:-}" owner repo raw
  [[ -n "$head" && -n "$base" && -n "$title" ]] || { _blacksmith_die "pr_create: head, base and title required"; return 1; }
  owner=$(blacksmith_config_get '.forgejo.owner') || return 1
  repo=$(blacksmith_config_get '.forgejo.repo')   || return 1
  raw=$(_blacksmith_forgejo_curl POST "/repos/${owner}/${repo}/pulls" \
        "$(jq -nc --arg h "$head" --arg b "$base" --arg t "$title" --arg d "$body" \
            '{head:$h, base:$b, title:$t, body:$d}')") \
    || { _blacksmith_die "pr_create (forgejo): failed ($head -> $base)"; return 1; }
  jq -c '{number, url: .html_url}' <<<"$raw"
}

# Forgejo's pulls list has no base filter param — filter client-side on
# .base.ref; merged is the boolean flag. Same neutral output as the GitHub arm.
_blacksmith_forgejo_pr_list_merged() {
  local base="$1" owner repo raw
  [[ -n "$base" ]] || { _blacksmith_die "pr_list_merged: base branch required"; return 1; }
  owner=$(blacksmith_config_get '.forgejo.owner') || return 1
  repo=$(blacksmith_config_get '.forgejo.repo')   || return 1
  raw=$(_blacksmith_forgejo_curl GET "/repos/${owner}/${repo}/pulls?state=closed&limit=100") \
    || { _blacksmith_die "pr_list_merged (forgejo): query failed"; return 1; }
  jq -c --arg b "$base" \
    '[ .[] | select(.base.ref == $b and .merged == true) | {number, title, headBranch: .head.ref} ]' <<<"$raw"
}

_blacksmith_forgejo_pr_open_exists() {
  local head="$1" base="$2" owner repo n
  [[ -n "$head" && -n "$base" ]] || { _blacksmith_die "pr_open_exists: head and base required"; return 1; }
  owner=$(blacksmith_config_get '.forgejo.owner') || return 1
  repo=$(blacksmith_config_get '.forgejo.repo')   || return 1
  n=$(_blacksmith_forgejo_curl GET "/repos/${owner}/${repo}/pulls?state=open&limit=100" 2>/dev/null \
      | jq --arg h "$head" --arg b "$base" \
          '[ .[] | select(.head.ref == $h and .base.ref == $b) ] | length') || n=0
  [[ "$n" -gt 0 ]]
}
```

3c. Shim routes. `tests/scripts/lib/gh-shim.sh` — insert before the `*"/issues/"*` route (and before the Task 1 comments route, order among the two is irrelevant — no URL matches both):

```bash
if [[ "$args" == *"/pulls"* && -n "${GH_SHIM_PULLS_FIXTURE:-}" ]]; then   # PR create/list (pr_* verbs)
  emit < "$GH_SHIM_PULLS_FIXTURE"; exit 0
fi
```

`tests/scripts/lib/curl-shim.sh` — insert after the milestones route:

```bash
if [[ "$args" == *"/pulls"* ]]; then                    # PR create / list (pr_* verbs)
  [[ -n "${CURL_SHIM_PULLS_FIXTURE:-}" ]] && { cat "$CURL_SHIM_PULLS_FIXTURE"; exit 0; }
  echo '[]'; exit 0
fi
```

**Step 4: Run test to verify it passes**

Run: `bash tests/scripts/test_blacksmith_pr_ops.sh`
Expected: PASS

Run: `bash tests/scripts/run-tests.sh`
Expected: exit 0

**Step 5: Commit**

`git commit` message: `feat(blacksmith): pr_create / pr_list_merged / pr_open_exists on both forges (#101)`

---

## Task 3: `repo_create` (GitHub + Forgejo org/user routing)

**Depends on:** Task 2 (appends to the same test file).

**Files:**
- Modify: `bin/harness-lib.sh`
- Modify: `tests/scripts/lib/gh-shim.sh`, `tests/scripts/lib/curl-shim.sh`
- Create: `tests/scripts/fixtures/forgejo-user.json`, `tests/scripts/fixtures/forgejo-repo-create.json`
- Test: `tests/scripts/test_blacksmith_pr_ops.sh` (append a `repo_create` section)

**Acceptance Criteria:**
- [ ] Run: `bash tests/scripts/test_blacksmith_pr_ops.sh` → Expected: exit 0 (now including the repo_create section)
- [ ] Run: `bash -c 'source bin/harness-lib.sh 2>/dev/null; declare -F _blacksmith_github_repo_create _blacksmith_forgejo_repo_create >/dev/null'` → Expected: exit 0
- [ ] Run: `bash tests/scripts/run-tests.sh` → Expected: exit 0

**Step 1: Write the failing test** — append to `tests/scripts/test_blacksmith_pr_ops.sh`, before the final PASS echo:

```bash
# --- repo_create: GitHub -----------------------------------------------------------
L="$SHIM_DIR/gh-repo.log"; : > "$L"
out=$(PATH="$SHIM_DIR:$PATH" HARNESS_CONFIG="$FIX/harness-config.sample.json" \
      GH_SHIM_CALL_LOG="$L" GH_SHIM_FIXTURE="$FIX/gh-project-discovery.json" \
      GH_SHIM_REPO_CREATE_URL="https://github.com/WillyDallas/newrepo" \
      bash -c "source '$LIB'; blacksmith_repo_create WillyDallas newrepo")
assert_eq 'https://github.com/WillyDallas/newrepo' "$(jq -r '.url' <<<"$out")" "gh repo_create: url" || exit 1
grep -qF 'repo create WillyDallas/newrepo' "$L" || { echo "FAIL: gh repo_create wrong target" >&2; exit 1; }
grep -qF -- '--private' "$L"                    || { echo "FAIL: gh repo_create not private" >&2; exit 1; }

# --- repo_create: Forgejo, USER-owned (owner == authenticated login) ----------------
fj_repo_run() {  # $1 = call log, $2 = owner arg
  PATH="$SHIM_DIR:$PATH" HARNESS_CONFIG="$FIX/harness-config.forgejo.json" FORGEJO_TOKEN="test-token" \
  CURL_SHIM_CALL_LOG="$1" CURL_SHIM_USER_FIXTURE="$FIX/forgejo-user.json" \
  CURL_SHIM_REPO_CREATE_FIXTURE="$FIX/forgejo-repo-create.json" \
  bash -c "source '$LIB'; blacksmith_repo_create $2 sluice"
}
L="$SHIM_DIR/fj-repo-user.log"; : > "$L"
out=$(fj_repo_run "$L" willy)   # forgejo-user.json login = willy
assert_eq 'https://git.squirrlylabs.dev/squirrlylabs/sluice' "$(jq -r '.url' <<<"$out")" "fj repo_create: url" || exit 1
grep -qF '/user/repos' "$L"          || { echo "FAIL: user-owned create not POST /user/repos" >&2; exit 1; }
grep -qF '"name":"sluice"' "$L"      || { echo "FAIL: fj repo name not sent" >&2; exit 1; }
grep -qF '"private":true' "$L"       || { echo "FAIL: fj repo not private" >&2; exit 1; }

# --- repo_create: Forgejo, ORG-owned (owner != authenticated login) -----------------
L="$SHIM_DIR/fj-repo-org.log"; : > "$L"
out=$(fj_repo_run "$L" squirrlylabs)
grep -qF '/orgs/squirrlylabs/repos' "$L" || { echo "FAIL: org-owned create not POST /orgs/{org}/repos" >&2; exit 1; }
if grep -qF '/user/repos' "$L"; then echo "FAIL: org-owned create hit /user/repos" >&2; exit 1; fi
```

Create fixtures:

`tests/scripts/fixtures/forgejo-user.json`:
```json
{"login": "willy"}
```

`tests/scripts/fixtures/forgejo-repo-create.json`:
```json
{"name": "sluice", "html_url": "https://git.squirrlylabs.dev/squirrlylabs/sluice"}
```

**Step 2: Run test to verify it fails**

Run: `bash tests/scripts/test_blacksmith_pr_ops.sh`
Expected: FAIL with `forge 'github' has no implementation for 'repo_create'`.

**Step 3: Write minimal implementation**

3a. GitHub arm:

```bash
# --- Repo creation (delivery verb; #101) --------------------------------------
# Create a PRIVATE repo; echoes the neutral { url }. gh routes user- vs
# org-owned itself from the owner/ prefix. Wiring this into init/oskr-setup is
# the provisioning path (#26/#27) — out of scope here; the verb is the contract.
#   repo_create <owner> <repo>
_blacksmith_github_repo_create() {
  local owner="$1" repo="$2" url
  [[ -n "$owner" && -n "$repo" ]] || { _blacksmith_die "repo_create: owner and repo required"; return 1; }
  url=$(gh repo create "${owner}/${repo}" --private 2>/dev/null) \
    || { _blacksmith_die "repo_create: failed for ${owner}/${repo}"; return 1; }
  jq -nc --arg u "$url" '{url: $u}'
}
```

3b. Forgejo arm:

```bash
# Forgejo repo create: org-owned (POST /orgs/{owner}/repos) when <owner> is not
# the authenticated user, else user-owned (POST /user/repos). Reads only
# .forgejo.base_url from config (owner comes in as the arg — at create time the
# config's .forgejo.owner may not exist yet).   repo_create <owner> <repo>
_blacksmith_forgejo_repo_create() {
  local owner="$1" repo="$2" login raw payload
  [[ -n "$owner" && -n "$repo" ]] || { _blacksmith_die "repo_create: owner and repo required"; return 1; }
  login=$(_blacksmith_forgejo_curl GET "/user" 2>/dev/null | jq -r '.login // empty')
  payload=$(jq -nc --arg n "$repo" '{name: $n, private: true, auto_init: false}')
  if [[ -n "$login" && "$owner" == "$login" ]]; then
    raw=$(_blacksmith_forgejo_curl POST "/user/repos" "$payload") \
      || { _blacksmith_die "repo_create (forgejo): failed for user repo ${repo}"; return 1; }
  else
    raw=$(_blacksmith_forgejo_curl POST "/orgs/${owner}/repos" "$payload") \
      || { _blacksmith_die "repo_create (forgejo): failed for ${owner}/${repo}"; return 1; }
  fi
  jq -c '{url: .html_url}' <<<"$raw"
}
```

3c. Shim routes. `tests/scripts/lib/gh-shim.sh` — insert next to the `repo view` route:

```bash
if [[ "$args" == *"repo create"* ]]; then       # repo_create: prints the new repo URL
  [[ "${GH_SHIM_REPO_CREATE_RC:-0}" -eq 0 ]] && printf '%s\n' "${GH_SHIM_REPO_CREATE_URL:-https://github.com/test/repo}"
  exit "${GH_SHIM_REPO_CREATE_RC:-0}"
fi
```

`tests/scripts/lib/curl-shim.sh` — insert **before** the `/repos/` catch-all routes at the bottom, ordered org/user-repos before the bare `/user` probe (`/user/repos` would otherwise match it):

```bash
if [[ "$args" == *"/orgs/"*"/repos"* || "$args" == *"/user/repos"* ]]; then  # repo_create
  [[ -n "${CURL_SHIM_REPO_CREATE_FIXTURE:-}" ]] && { cat "$CURL_SHIM_REPO_CREATE_FIXTURE"; exit 0; }
  echo '{}'; exit 0
fi
if [[ "$args" == *"/api/v1/user"* ]]; then      # GET authenticated user (repo_create routing)
  [[ -n "${CURL_SHIM_USER_FIXTURE:-}" ]] && { cat "$CURL_SHIM_USER_FIXTURE"; exit 0; }
  echo '{"login":"test-user"}'; exit 0
fi
```

**Step 4: Run test to verify it passes**

Run: `bash tests/scripts/test_blacksmith_pr_ops.sh`
Expected: PASS

Run: `bash tests/scripts/run-tests.sh`
Expected: exit 0

**Step 5: Commit**

`git commit` message: `feat(blacksmith): repo_create — gh + Forgejo org/user-owned routing (#101)`

---

## Task 4: Convert `research`, `decompose`, `scope`

**Depends on:** Task 1. *(Harness-infra substitution: AC → grep check → implement. Frontmatter changes are tool-list-only — no name/description/invocation changes, so the writing-skills rubric is not implicated.)*

**Files:**
- Modify: `skills/research/SKILL.md`, `skills/decompose/SKILL.md`, `skills/scope/SKILL.md`

**Acceptance Criteria:**
- [ ] Run: `! grep -qE '\bgh (issue|pr)\b' skills/research/SKILL.md` → Expected: exit 0
- [ ] Run: `! grep -qE '\bgh (issue|pr)\b' skills/decompose/SKILL.md` → Expected: exit 0
- [ ] Run: `! grep -qE '\bgh (issue|pr)\b' skills/scope/SKILL.md` → Expected: exit 0
- [ ] Run: `grep -qF 'blacksmith_issue_view' skills/research/SKILL.md && grep -qF 'blacksmith_issue_comment' skills/research/SKILL.md` → Expected: exit 0
- [ ] Run: `grep -qF 'blacksmith_issue_view' skills/decompose/SKILL.md` → Expected: exit 0
- [ ] Run: `grep -qF 'blacksmith_issue_view' skills/scope/SKILL.md && grep -qF 'blacksmith_issue_add_label' skills/scope/SKILL.md` → Expected: exit 0
- [ ] Run: `! grep -qF 'Bash(gh *)' skills/research/SKILL.md && ! grep -qF 'Bash(gh *)' skills/decompose/SKILL.md && ! grep -qF 'Bash(gh *)' skills/scope/SKILL.md` → Expected: exit 0 (permission narrowed away with the last raw call)

**Edits (exact):**

`skills/research/SKILL.md`:
- Frontmatter line 5: `allowed-tools: Bash(gh *) Bash(sync-development.sh*) ...` → `allowed-tools: Bash(source bin/harness-lib.sh*) Bash(sync-development.sh*) Read Glob Grep Agent Skill`
- Line 14: `` read it (`gh issue view <n> --json title,body,comments`) `` → `` read it (`source bin/harness-lib.sh && blacksmith_issue_view <n>`) ``
- Line 22: `` **Post it** as a `## Research Digest` comment (`gh issue comment <n>`), `` → `` **Post it** as a `## Research Digest` comment (`source bin/harness-lib.sh && blacksmith_issue_comment <n> "<digest>"`), ``

`skills/decompose/SKILL.md`:
- Frontmatter line 5: drop `Bash(gh *)`, add `Bash(source bin/harness-lib.sh*)` as the first entry.
- Line 12: `` `gh issue view <umbrella> --json title,body,labels` `` → `` `source bin/harness-lib.sh && blacksmith_issue_view <umbrella>` ``

`skills/scope/SKILL.md`:
- Frontmatter line 6: drop `Bash(gh *)`, add `Bash(source bin/harness-lib.sh*)` (keep the rest).
- Line 13: `` load it (`gh issue view <n> --json title,body,labels,comments`) `` → `` load it (`source bin/harness-lib.sh && blacksmith_issue_view <n>`) ``
- Line 30: replace the whole bullet:
  - Before: `` - add labels `area/<slug>` **and** `type/umbrella` (`gh issue edit <umbrella> --add-label "area/<slug>,type/umbrella"`). ``
  - After: `` - add labels `area/<slug>` **and** `type/umbrella` (`source bin/harness-lib.sh && blacksmith_issue_add_label <umbrella> "area/<slug>" && blacksmith_issue_add_label <umbrella> "type/umbrella"` — one label per call). ``

**Verify:** run the AC commands above.

**Commit:** `refactor(skills): research/decompose/scope issue ops through the blacksmith (#101)`

---

## Task 5: Convert `planning-session`, `plan-approval`

**Depends on:** Task 1. *(Harness-infra substitution, as Task 4.)*

**Files:**
- Modify: `skills/planning-session/SKILL.md`, `skills/plan-approval/SKILL.md`

**Acceptance Criteria:**
- [ ] Run: `! grep -qE '\bgh (issue|pr)\b' skills/planning-session/SKILL.md` → Expected: exit 0
- [ ] Run: `! grep -qE '\bgh (issue|pr)\b' skills/plan-approval/SKILL.md` → Expected: exit 0
- [ ] Run: `grep -qF 'blacksmith_issue_view' skills/planning-session/SKILL.md && grep -qF 'blacksmith_issue_comment' skills/planning-session/SKILL.md` → Expected: exit 0
- [ ] Run: `grep -qF 'blacksmith_issue_view' skills/plan-approval/SKILL.md && grep -qF 'blacksmith_issue_comment' skills/plan-approval/SKILL.md` → Expected: exit 0
- [ ] Run: `grep -qF 'Bash(gh api *)' skills/planning-session/SKILL.md` → Expected: exit 0 (permission narrowed to the one residual `gh api` parent lookup, not dropped)
- [ ] Run: `! grep -qF 'Bash(gh *)' skills/plan-approval/SKILL.md` → Expected: exit 0

**Edits (exact):**

`skills/planning-session/SKILL.md`:
- Frontmatter line 5: `Bash(gh *)` → `Bash(gh api *) Bash(source bin/harness-lib.sh*)` — the `gh api .../parent` lookup (line 32) keeps a narrowed permission; it is a `gh api` call with no blacksmith verb yet (deliberately outside this task's `gh issue`/`gh pr` contract; the skill already carries the per-forge branch in prose).
- Lines 13–15 code block:
  ```bash
  source bin/harness-lib.sh
  blacksmith_issue_view <NUMBER>   # neutral {number,title,state,stateReason,body,labels,comments,url}
  ```
- Line 34: `` 2. Read the umbrella's `## Named Seams`: `gh issue view <PARENT> --json body`, then extract that section. `` → `` 2. Read the umbrella's `## Named Seams`: `blacksmith_issue_view <PARENT> | jq -r '.body'`, then extract that section. ``
- Line 208 code block: replace the `gh issue comment <NUMBER> --body "$(cat <<'COMMENT'` opener with:
  ```bash
  source bin/harness-lib.sh
  blacksmith_issue_comment <NUMBER> "$(cat <<'COMMENT'
  ```
  (heredoc body and closer unchanged; drop the trailing `--body`-era `)"` shape only as far as syntax requires — the `COMMENT` / `)"` closers stay).

`skills/plan-approval/SKILL.md`:
- Frontmatter line 6: drop `Bash(gh *)`, add `Bash(source bin/harness-lib.sh*)` as the first entry.
- Line 16 code block: `gh issue view <n> --json labels` → `source bin/harness-lib.sh && blacksmith_issue_view <n> | jq '.labels'`
- Line 26: `` (`gh issue view <child#> --json comments`) `` → `` (`blacksmith_issue_view <child#> | jq '.comments'`) ``
- Line 64 code block: `gh issue comment <child#> --body "$(cat <<'COMMENT'` → `source bin/harness-lib.sh` on its own line, then `blacksmith_issue_comment <child#> "$(cat <<'COMMENT'` (closers unchanged).

**Verify:** run the AC commands above.

**Commit:** `refactor(skills): planning-session/plan-approval issue ops through the blacksmith (#101)`

---

## Task 6: Convert `execute-plan`, `hjarne`

**Depends on:** Tasks 1 + 2. *(Harness-infra substitution, as Task 4.)*

**Files:**
- Modify: `skills/execute-plan/SKILL.md`, `skills/hjarne/SKILL.md`

**Acceptance Criteria:**
- [ ] Run: `! grep -qE '\bgh (issue|pr)\b' skills/execute-plan/SKILL.md` → Expected: exit 0
- [ ] Run: `! grep -qE '\bgh (issue|pr)\b' skills/hjarne/SKILL.md` → Expected: exit 0
- [ ] Run: `grep -qF 'blacksmith_pr_create' skills/execute-plan/SKILL.md && grep -qF 'blacksmith_issue_remove_label' skills/execute-plan/SKILL.md && grep -qF 'blacksmith_issue_comment' skills/execute-plan/SKILL.md && grep -qF 'blacksmith_issue_view' skills/execute-plan/SKILL.md` → Expected: exit 0
- [ ] Run: `grep -qF 'git push -u origin' skills/execute-plan/SKILL.md` → Expected: exit 0 (explicit push before the REST PR create — `blacksmith_pr_create` does not push)
- [ ] Run: `grep -qF 'blacksmith_issue_view' skills/hjarne/SKILL.md` → Expected: exit 0
- [ ] Run: `! grep -qF 'Bash(gh *)' skills/execute-plan/SKILL.md` → Expected: exit 0

**Edits (exact):**

`skills/execute-plan/SKILL.md`:
- Frontmatter line 5: drop `Bash(gh *)`, add `Bash(source bin/harness-lib.sh*)` as the first entry.
- Line 22: `` Fetch the issue: `gh issue view <NUMBER> --json title,body,comments` `` → `` Fetch the issue: `source bin/harness-lib.sh && blacksmith_issue_view <NUMBER>` ``
- Completion step 2 (lines ~167–186): replace the `gh pr create` block with:
  ```bash
  source bin/harness-lib.sh
  git push -u origin "feature/<NUMBER>-<short-slug>"   # blacksmith_pr_create is REST — push first
  PR_JSON=$(blacksmith_pr_create "feature/<NUMBER>-<short-slug>" "$BASE_BRANCH" "<issue title>" "$(cat <<'EOF'
  ## Summary
  [2-3 bullet points of what was implemented]

  ## Tasks Completed
  - [x] Task 1: [name] — PASS (N iterations)
  - [x] Task 2: [name] — PASS (N iterations)

  ## Verification
  - type-check: PASS
  - reviewer sessions used: N, fallback respawns: M
  - [test results summary]
  EOF
  )")
  PR_NUMBER=$(jq -r '.number' <<<"$PR_JSON")
  ```
  (The surrounding prose about `Related:` vs `Closes` is untouched.)
- Line 192: `gh issue comment <NUMBER> --body "Implementation complete. PR #<PR_NUMBER> opened targeting \`$BASE_BRANCH\`."` → `blacksmith_issue_comment <NUMBER> "Implementation complete. PR #$PR_NUMBER opened targeting \`$BASE_BRANCH\`."`
- Line 197: `gh issue edit <NUMBER> --remove-label dispatch-incomplete 2>/dev/null || true` → `blacksmith_issue_remove_label <NUMBER> dispatch-incomplete` (the verb never fails the caller — the `|| true` is built in).

`skills/hjarne/SKILL.md` (frontmatter has unrestricted `Bash` — no permission change):
- Lines 80–81: replace
  ```bash
  DIGEST=$(gh issue view 28 --json comments \
    --jq '[.comments[] | select(.body | startswith("## Research Digest")) | .body] | last')
  ```
  with
  ```bash
  DIGEST=$(blacksmith_issue_view 28 \
    | jq -r '[.comments[] | select(startswith("## Research Digest"))] | last')
  ```
  (neutral `comments` is an array of body **strings**, so the `.body |` projection goes away; `harness-lib.sh` is already sourced two lines up).

**Verify:** run the AC commands above.

**Commit:** `refactor(skills): execute-plan/hjarne forge ops through the blacksmith (#101)`

---

## Task 7: Convert `land-area`, `clean-up`

**Depends on:** Tasks 1 + 2. *(Harness-infra substitution, as Task 4.)*

**Files:**
- Modify: `skills/land-area/SKILL.md`, `skills/clean-up/SKILL.md`

**Acceptance Criteria:**
- [ ] Run: `! grep -qE '\bgh (issue|pr)\b' skills/land-area/SKILL.md` → Expected: exit 0 (this includes the line-24 backend-note **prose** — the note is deleted, not just the commands)
- [ ] Run: `! grep -qE '\bgh (issue|pr)\b' skills/clean-up/SKILL.md` → Expected: exit 0
- [ ] Run: `grep -qF 'blacksmith_pr_list_merged' skills/land-area/SKILL.md && grep -qF 'blacksmith_pr_open_exists' skills/land-area/SKILL.md && grep -qF 'blacksmith_pr_create' skills/land-area/SKILL.md && grep -qF 'blacksmith_issue_view' skills/land-area/SKILL.md` → Expected: exit 0
- [ ] Run: `grep -qF 'blacksmith_issue_view' skills/clean-up/SKILL.md && grep -qF 'stateReason' skills/clean-up/SKILL.md` → Expected: exit 0
- [ ] Run: `! grep -qF 'Bash(gh *)' skills/land-area/SKILL.md && ! grep -qF 'Bash(gh *)' skills/clean-up/SKILL.md` → Expected: exit 0
- [ ] Run: `! grep -qiE 'GitHub-only' skills/land-area/SKILL.md` → Expected: exit 0 (the stale coupling note is gone)

**Edits (exact):**

`skills/land-area/SKILL.md`:
- Frontmatter line 5: drop `Bash(gh *)`, add `Bash(source bin/harness-lib.sh*)` as the first entry.
- Line 14: `` 1. **Load the Area.** `gh issue view <umbrella> --json number,title,body,labels`; confirm it carries `type/umbrella` `` → `` 1. **Load the Area.** `source bin/harness-lib.sh && blacksmith_issue_view <umbrella>`; confirm `.labels` carries `type/umbrella` ``
- Lines 20–22 code block: replace with
  ```bash
  blacksmith_pr_list_merged "$AREA" | jq -r '.[].headBranch'
  ```
- Line 24: **delete the entire backend-note line** (`*(Backend note: `gh pr list --base` is GitHub-only; the Forgejo equivalent is a follow-up — the same coupling the other delivery skills carry.)*`). The rewritten step 2 needs no replacement note — the verb dispatches per forge, so the coupling the note documented no longer exists. Nothing else on that line survives.
- Line 26: `` 3. **Open the Area → main PR** (skip cleanly if one already exists — `gh pr list --head "$AREA" --base "$MAIN" --state open`): `` → `` 3. **Open the Area → main PR** (skip cleanly if one already exists — `blacksmith_pr_open_exists "$AREA" "$MAIN"` exits 0 when an open Area→main PR is already there): ``
- Lines 27–38 code block: replace the `gh pr create` invocation with
  ```bash
  git push -u origin "$AREA"
  blacksmith_pr_create "$AREA" "$MAIN" "<Area title>" "$(cat <<EOF
  ## <Area title>
  [2–3 line summary drawn from the umbrella PRD]

  Closes #<umbrella>
  Closes #<child1>
  Closes #<child2>
  EOF
  )"
  ```

`skills/clean-up/SKILL.md`:
- Frontmatter line 5: drop `Bash(gh *)` (the `Bash(source bin/harness-lib.sh*)` entry already exists).
- Line 16: `` The neutral verbs (`blacksmith_list_board`) and `gh` read coordinates from there `` → `` The neutral verbs (`blacksmith_list_board`, `blacksmith_issue_view`) read coordinates from there ``
- Lines 53–57 code block: replace `gh issue view <NUMBER> --json state,stateReason,title,url` with
  ```bash
  source bin/harness-lib.sh && blacksmith_issue_view <NUMBER> \
    | jq '{number, title, state, stateReason, url}'
  ```
- Classification table (lines 59–64) — neutral (REST-lowercase) casing, plus the Forgejo degradation:
  - `shipped` row: `` `state == CLOSED` + `stateReason == COMPLETED` `` → `` `state == "closed"` + `stateReason == "completed"` (on forges without close reasons — Forgejo — `stateReason` is `null`: fall back to close state + every-child-closed) ``
  - `not-planned` row: `Closed `NOT_PLANNED`` → `Closed `not_planned`` (a `null` `stateReason` on a closed issue is **not** `not-planned` — treat it as `shipped`-candidate per the fallback above, or `in-flight` if children are open).
- Line 75: `` Re-run `gh issue view` (and `list-children.sh` for umbrellas) `` → `` Re-run `blacksmith_issue_view` (and `list-children.sh` for umbrellas) ``
- Line 166 gotcha: `` **`state: CLOSED` is not "shipped".** An issue can be closed `NOT_PLANNED`. `` → `` **`state: "closed"` is not "shipped".** An issue can be closed `not_planned`. ``
- Line 169 gotcha: `` use `gh` only for per-issue read/comment. `` → `` use `blacksmith_issue_view` / `blacksmith_issue_comment` for per-issue read/comment. ``

**Verify:** run the AC commands above.

**Commit:** `refactor(skills): land-area/clean-up PR + issue ops through the blacksmith (#101)`

---

## Task 8: Seam-guard extension + full-suite gate

**Depends on:** Tasks 4–7. *(Harness-infra substitution: the guard is itself the AC — write it, watch it pass against the converted skills, and prove it bites by reverting nothing: its FAIL branch is exercised by construction on any regression.)*

**Files:**
- Modify: `tests/scripts/test_backend_no_inline_gh.sh`

**Acceptance Criteria:**
- [ ] Run: `bash tests/scripts/test_backend_no_inline_gh.sh` → Expected: exit 0, last line `test_backend_no_inline_gh: PASS`
- [ ] Run: `bash -c 'echo "gh issue view 1" >> skills/research/SKILL.md; bash tests/scripts/test_backend_no_inline_gh.sh; rc=$?; git checkout -- skills/research/SKILL.md; exit $((rc == 0))'` → Expected: exit 0 (i.e. the guard FAILS on a planted regression, then the plant is reverted; the compound command exits 0 only when the guard exited non-zero)
- [ ] Run: `grep -qF 'Allowlist: EMPTY' tests/scripts/test_backend_no_inline_gh.sh` → Expected: exit 0 (the empty allowlist is stated explicitly, per the frozen DoD)
- [ ] Run: `bash tests/scripts/run-tests.sh` → Expected: exit 0 — the full hermetic suite is green (final DoD gate)

**Step 1: Implementation** — append to `tests/scripts/test_backend_no_inline_gh.sh`, before the final `[[ "$fail" -eq 0 ]]` line:

```bash
# 4. Delivery-path skills perform issue/PR operations only through blacksmith
#    verbs (#101). Scans the 9 delivery SKILL.md files for raw `gh issue` /
#    `gh pr` — code AND prose (a documented raw call regresses the same way).
#    Allowlist: EMPTY — every gh issue/pr operation in these skills has a verb
#    (issue_view/close/remove_label + pr_create/list_merged/open_exists new in
#    #101; issue_comment/issue_add_label pre-existing). `gh api` is deliberately
#    NOT scanned: planning-session's parent lookup has no verb yet (follow-up).
#    init/oskr-setup are the provisioning path (#26/#27) and are NOT scanned.
DELIVERY_SKILLS="scope research decompose planning-session plan-approval execute-plan land-area clean-up hjarne"
for s in $DELIVERY_SKILLS; do
  f="$REPO_ROOT/skills/$s/SKILL.md"
  [[ -f "$f" ]] || { echo "FAIL: missing delivery skill skills/$s/SKILL.md" >&2; fail=1; continue; }
  if grep -nE '\bgh (issue|pr)\b' "$f" >/dev/null 2>&1; then
    echo "FAIL: raw gh issue/pr call in skills/$s/SKILL.md — use a blacksmith verb:" >&2
    grep -nE '\bgh (issue|pr)\b' "$f" >&2
    fail=1
  fi
done
```

**Step 2: Verify**

Run: `bash tests/scripts/test_backend_no_inline_gh.sh`
Expected: PASS (all 9 skills are already converted by Tasks 4–7).

Run the planted-regression AC (second AC above).
Expected: the guard prints `FAIL: raw gh issue/pr call in skills/research/SKILL.md` and exits non-zero while planted.

Run: `bash tests/scripts/run-tests.sh`
Expected: exit 0.

**Step 3: Commit**

`git commit` message: `test(seam-guard): forbid raw gh issue/pr in delivery skills (#101)`

---

## Issue-AC → plan-AC traceability

| Issue #101 AC | Discharged by |
|---|---|
| `issue_view` neutral `{title,body,labels,comments}` both forges; `issue_close` / `issue_remove_label` both forges | Task 1 (test asserts the frozen minimum keys verbatim + the additive superset) |
| `pr_create` / `pr_list_merged` / `pr_open_exists` both forges; Forgejo `repo_create` org- or user-owned | Tasks 2, 3 |
| every new verb has hermetic shim-replay coverage asserting request shape + output contract | Tasks 1–3 (`test_blacksmith_issue_ops.sh`, `test_blacksmith_pr_ops.sh`) |
| delivery skills use only the verbs for issue/PR ops | Tasks 4–7 (per-skill positive + negative greps) |
| seam-guard extended so raw `gh` issue/PR cannot regress | Task 8 |
| full hermetic test suite green | Task 8 final AC (`run-tests.sh` exit 0) |
