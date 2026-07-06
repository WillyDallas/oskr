# Sandboxed Teach Skill Implementation Plan

**Goal:** Ship `/oskr:teach <topic>` — a user-invoked teaching skill whose knowledge state lives in the brain via the existing `hjarne_*` seam and whose workspace resolution comes from a new forge-blind learning lib, never from CWD.
**Architecture:** A new sourceable `bin/learning-lib.sh` (resolver + topic-enumeration + resource-queue verbs) is tail-sourced by `bin/harness-lib.sh` after `hjarne-lib.sh`. Topic identity is normalized: the skill derives a topic's slug from a confirmed canonical name (pinned as the mission page H1), reconciling a new invocation against existing topics via `learning_list_topics` so a differently phrased re-invocation continues the same topic instead of forking a duplicate. The only mutation path is `learning_resource_mark`, which transforms the resources page in memory and persists exclusively through `hjarne_write_page` — the lib adds no byte-writing code for records. `skills/teach/SKILL.md` plus four colocated format specs adapt the vendored teach skill to this contract.
**Tech Stack:** bash 3.2-compatible shell (functions only, `set -euo pipefail`-safe), hermetic bash tests under `tests/scripts/` (auto-discovered by `run-tests.sh`), markdown skill files.
**Issue:** #99 (child of Area umbrella #30, area/learning; Area base branch `WillyDallas/30`)

---

## Plan-wide notes (read before Task 1)

- **TDD substitution declared:** Tasks 1–3 are strict TDD (failing test → implement → pass). Tasks 4–7 author harness-infrastructure prose (SKILL.md, format specs); per convention, TDD is substituted with *write acceptance criterion → grep/structural check → implement*. This substitution is deliberate.
- **Playwright exemption:** no UI surface anywhere in this plan — the deliverables are a bash lib, tests, and markdown skill files. No Playwright AC applies.
- **Design-rule ACs:** `.claude/rules/` does not exist in this repo (verified by glob). Design-rule ACs are a no-op.
- **Manual gate:** the interactive teaching loop (live first lesson, mission interview) is a manual gate per umbrella #30's Named Seams — it is NOT a test seam. Tests cover the lib; knowledge-write persistence is covered transitively because the queue test asserts the hjarne version stamp, proving delegation to the already-tested `hjarne_write_page`.
- **Source-order accuracy:** both libs are function-only, so bash resolves `hjarne_write_page` at call time regardless of source order. The hjarne→learning tail-source order is a readability/convention check; the wire test proves the *wiring* (a bare `source harness-lib.sh` exposes and drives the learning verbs), not an ordering requirement.
- **Redirection-regex caveat:** the seam-purity negative grep `(printf|echo|cat)[^|]*>>? ` deliberately spares `>&2` stderr refusals (no space after `>`) but would not catch heredoc-to-file constructs. `bin/learning-lib.sh` must contain no heredocs at all; the functional version-stamp assertion in `test_learning_queue.sh` is the real backstop.
- **Vendored immutability baseline (LOCAL ref):** diffs against the Area merge base use the pinned form `git diff --quiet WillyDallas/30...HEAD -- <path>` (three-dot = merge-base..HEAD). The pin is the LOCAL ref deliberately: `origin/WillyDallas/30` does not exist on the remote — the Area branch is local-only, so any `origin/…` form exits 128. **Precondition:** `git rev-parse --verify WillyDallas/30` must exit 0 in the execution worktree. Git worktrees share one ref store, so the ref resolves whenever the Area branch exists anywhere in the repo (execution worktrees branch off the Area base, so it normally does). If it does not resolve, materialize it before Task 8: push the Area branch from its home worktree (`git push -u origin WillyDallas/30`), then `git branch WillyDallas/30 origin/WillyDallas/30`.
- **Scope fence (#98 deferrals, hard non-goals):** NO `templates/learning/`, NO stamp verb (`learning_stamp*`), NO auto-populated "using oskr" lesson, NO `oskr-setup` Phase 4 wiring, NO plugin.json bump (child PR), NO registry entry. Task 8 carries the negative structural ACs.

**Queue marker contract (single source of truth, used by Tasks 2, 4, 6):** each resource entry on a topic's resources page carries an HTML-comment marker on its bullet line:

```
<!-- learning:resource id=<resource-slug> status=queued -->
```

`id` is a lowercase `[a-z0-9-]` slug; `status` is exactly `queued` or `ingested`. `learning_resource_status` parses it; `learning_resource_mark` rewrites it (in memory) and persists via `hjarne_write_page`. Both verbs validate the id against `^[a-z0-9-]+$` before touching the page. `RESOURCES-FORMAT.md` (Task 6) documents the same marker verbatim.

**Page-path contract:** the resources page for topic `<topic>` is the brain wiki page `wiki/learning-<topic-slug>-resources.md`, derived via `hjarne_route`. Slugging duplicates the transform hjarne already inlines (deliberate — `bin/hjarne-lib.sh:185-187` documents that a shared helper is out of scope because it would edit frozen code).

**Topic-identity model (name setting + resolution — used by Tasks 1.5, 4, 6):** a topic is keyed by its slug, but the slug is derived from a **confirmed canonical name**, never from the raw `$ARGUMENTS`. The skill normalizes the argument to a proposed name, reconciles it against existing topics via `learning_list_topics`, and only then slugs the confirmed name through `learning_topic_dir`. The canonical name is **pinned** at creation as the mission page's H1 (`# Mission: {Topic}` — MISSION-FORMAT.md line 1), which `learning_list_topics` reads back. This makes continuation robust: a later invocation phrased differently (`I want to lear rust` vs `rust`) normalizes and matches the pinned name instead of forking a duplicate `learning/i-want-to-lear-rust` topic. Matching is **in-context** over the enumerated list (a workspace holds a handful of topics) — no embeddings, no index. This is an interactive/manual-gate behavior (the normalize + confirm steps); the lib half it rides on (`learning_list_topics`) is hermetically tested.

---

## Task 1: Learning lib — resolver verbs

**Files:**
- Create: `bin/learning-lib.sh` (resolver half: `_learning_slug`, `learning_resolve_root`, `learning_topic_dir`, `learning_resources_page`)
- Test: `tests/scripts/test_learning_resolve.sh`

**Dependencies:** none (first task).

**Acceptance Criteria:**
- [ ] Run: `bash tests/scripts/test_learning_resolve.sh` → Expected: exit 0
- [ ] Run: `bash -n bin/learning-lib.sh` → Expected: exit 0
- [ ] Refusal is instructive: the test itself asserts stderr contains `not inside an oskr workspace` AND `oskr-setup` (see test body) — Run: `grep -qF 'oskr-setup' bin/learning-lib.sh` → Expected: exit 0
- [ ] Forge-blind (pattern aligned with the covering guard `tests/scripts/test_backend_no_inline_gh.sh:16`, which greps `gh (api|issue|pr|label|project)` precisely so prose comments cannot false-positive): Run: `! grep -qE '\bgh (api|issue|pr|label|project)\b|\bcurl\b' bin/learning-lib.sh` → Expected: exit 0
- [ ] Scope-assumption header present: Run: `grep -qF 'tail-sourced by bin/harness-lib.sh' bin/learning-lib.sh` → Expected: exit 0

**Step 1: Write the failing test**

Create `tests/scripts/test_learning_resolve.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"
source "$REPO_ROOT/bin/harness-lib.sh"    # blacksmith_workspace_dir + hjarne_* helpers
source "$REPO_ROOT/bin/learning-lib.sh"   # units under test

WS=$(cd "$(mktemp -d)" && pwd)            # canonicalized so /tmp symlinks don't break ==
OTHER=$(cd "$(mktemp -d)" && pwd)         # no .oskr/ anywhere above it
trap 'rm -rf "$WS" "$OTHER"' EXIT
mkdir -p "$WS/.oskr"
export OSKR_WORKSPACE="$WS"

# resolution inside a workspace: <workspace>/learning, from the resolver — never CWD
GOT=$(learning_resolve_root)
assert_eq "$WS/learning" "$GOT" "resolve_root == workspace/learning"

# topic-dir derivation + slugging (case folded, punctuation collapsed, edges trimmed)
GOT=$(learning_topic_dir "Rust Macros!")
assert_eq "$WS/learning/rust-macros" "$GOT" "topic dir is slugged under the learning root"

# resources page: canonical hjarne wiki page path (read-only derivation via hjarne_route)
GOT=$(learning_resources_page "Rust Macros!")
assert_eq "$WS/hjarne/wiki/learning-rust-macros-resources.md" "$GOT" \
  "resources page routes into the brain wiki"

# refusal outside a workspace: non-zero exit + INSTRUCTIVE stderr, nothing written.
# learning-lib sourced explicitly so this test does not depend on Task 3's tail-wire.
ERR=$(cd "$OTHER" && OSKR_WORKSPACE="" bash -c \
  "source '$REPO_ROOT/bin/harness-lib.sh' && source '$REPO_ROOT/bin/learning-lib.sh' && learning_resolve_root" 2>&1) \
  && { echo "FAIL: learning_resolve_root succeeded outside a workspace" >&2; exit 1; }
grep -qF "not inside an oskr workspace" <<<"$ERR" \
  || { echo "FAIL: refusal not loud/clear; got: $ERR" >&2; exit 1; }
grep -qF "oskr-setup" <<<"$ERR" \
  || { echo "FAIL: refusal not instructive (no oskr-setup remedy); got: $ERR" >&2; exit 1; }
[[ -z "$(ls -A "$OTHER")" ]] \
  || { echo "FAIL: refusal wrote into the CWD" >&2; exit 1; }

echo "test_learning_resolve: PASS"
```

**Step 2: Run test to verify it fails**
Run: `bash tests/scripts/test_learning_resolve.sh`
Expected: FAIL — `bin/learning-lib.sh: No such file or directory` (the `source` on line 8 fails under `set -e`).

**Step 3: Write minimal implementation**

Create `bin/learning-lib.sh`:

```bash
#!/usr/bin/env bash
# learning-lib.sh — the learning-domain seam: oskr's pure-filesystem teaching helpers.
# Sourceable; not directly executable. Forge-blind: no forge CLI calls, no HTTP,
# no board layer.
#
# These helpers resolve the workspace learning domain (<workspace>/learning, one
# subdir per topic) and manage the per-resource ingest queue on a topic's hjarne
# resources page. The /teach skill drives them. The ONLY mutation path is
# learning_resource_mark, and it persists exclusively via hjarne_write_page —
# this lib adds no byte-writing code for knowledge records.
#
# Scope assumption: this file is tail-sourced by bin/harness-lib.sh AFTER
# hjarne-lib.sh, so blacksmith_workspace_dir and the hjarne_* helpers are in
# scope by call time (both libs are function-only, so bash resolves the names
# at call time; the ordering is convention, not a load-order requirement). It
# defines functions only — no top-level statement runs, so it is safe to
# `source` under `set -euo pipefail`.

# Slug transform — DELIBERATELY duplicated verbatim from hjarne_raw_path's inlined
# transform (see bin/hjarne-lib.sh:185-187: a shared helper is out of scope there
# because it would edit frozen code). Private to this lib.
_learning_slug() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

# Echo the learning root: <workspace>/learning. NEVER derived from CWD content —
# blacksmith_workspace_dir walks to the nearest ancestor .oskr/ (or honours
# OSKR_WORKSPACE). Loud, instructive refusal to stderr + non-zero exit when no
# workspace resolves.
learning_resolve_root() {
  local ws
  if ! ws=$(blacksmith_workspace_dir 2>/dev/null); then
    echo "learning: not inside an oskr workspace — no ancestor .oskr/ found and OSKR_WORKSPACE unset." >&2
    echo "learning: cd into your workspace (or export OSKR_WORKSPACE=<path>), or run /oskr:oskr-setup to create one. Nothing was written." >&2
    return 1
  fi
  echo "$ws/learning"
}

# Echo the topic directory: <learning-root>/<topic-slug>. Does not create it.
# learning_topic_dir <topic>
learning_topic_dir() {
  local topic="$1" root slug
  root=$(learning_resolve_root) || return 1
  slug=$(_learning_slug "$topic")
  echo "$root/$slug"
}

# Echo the canonical hjarne page path for the topic's resources (read-only path
# derivation): <brain>/wiki/learning-<topic-slug>-resources.md via hjarne_route.
# learning_resources_page <topic>
learning_resources_page() {
  local topic="$1" slug
  slug=$(_learning_slug "$topic")
  hjarne_route "learning-${slug}-resources"
}
```

**Step 4: Run test to verify it passes**
Run: `bash tests/scripts/test_learning_resolve.sh`
Expected: PASS (`test_learning_resolve: PASS`). Then run the remaining ACs at this commit point (the `bash -n` and the three greps) — each exits 0; in particular the forge-blind grep passes because the header comment says "no forge CLI calls, no HTTP", never the bare tool names.

**Step 5: Commit**
`feat(learning): add learning-lib resolver verbs (root, topic dir, resources page) (#99)`

---

## Task 1.5: Learning lib — topic enumeration verb

**Files:**
- Modify: `bin/learning-lib.sh` (append `learning_list_topics`)
- Test: `tests/scripts/test_learning_topics.sh`

**Dependencies:** Task 1 (same lib file). Leans on the already-wired `hjarne_*` seam to find the brain wiki (`hjarne_resolve_brain`, in scope because `harness-lib.sh` tail-sources `hjarne-lib.sh` pre-#99). Enables Task 4's Step 0.5 reconcile.

**Acceptance Criteria:**
- [ ] Run: `bash tests/scripts/test_learning_topics.sh` → Expected: exit 0
- [ ] Run: `bash -n bin/learning-lib.sh` → Expected: exit 0
- [ ] Forge-blind still holds: Run: `! grep -qE '\bgh (api|issue|pr|label|project)\b|\bcurl\b' bin/learning-lib.sh` → Expected: exit 0
- [ ] Read-only (no mutation added): the Task-2 seam-purity greps still pass over the whole file — Run: `! grep -qF 'sed -i' bin/learning-lib.sh && ! grep -qE '(printf|echo|cat)[^|]*>>? ' bin/learning-lib.sh` → Expected: exit 0 (the verb prints to stdout, never redirects to a file)
- [ ] Canonical name from the pinned H1, not the slug: asserted inside the test (name column comes from each mission page's `# Mission: {Topic}`)
- [ ] Empty when no topics exist: a fresh workspace (no brain wiki dir) yields no output and exit 0 — asserted in the test

**Step 1: Write the failing test**

Create `tests/scripts/test_learning_topics.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"
source "$REPO_ROOT/bin/harness-lib.sh"    # blacksmith_workspace_dir + hjarne_* helpers
source "$REPO_ROOT/bin/learning-lib.sh"   # unit under test

WS=$(cd "$(mktemp -d)" && pwd)
trap 'rm -rf "$WS"' EXIT
mkdir -p "$WS/.oskr"
export OSKR_WORKSPACE="$WS"

# fresh workspace: no brain wiki yet -> empty output, exit 0 (zero topics is legit)
GOT=$(learning_list_topics)
assert_eq "" "$GOT" "no topics in a fresh workspace"

# seed two mission pages THROUGH the seam, canonical name in each H1 (the pin)
hjarne_write_page "$(hjarne_route learning-rust-mission)" \
  $'# Mission: Rust\n\n## Why\nShip a CLI to my team.'
hjarne_write_page "$(hjarne_route learning-french-cooking-mission)" \
  $'# Mission: French Cooking\n\n## Why\nHost a dinner party.'

# enumeration: one "<slug>\t<canonical name>" line per topic, sorted for stability
GOT=$(learning_list_topics | sort)
EXPECT=$'french-cooking\tFrench Cooking\nrust\tRust'
assert_eq "$EXPECT" "$GOT" "lists both topics with canonical names from the mission H1"

# the name column is the H1 text (capitalized) — proves it is the pinned name, NOT the slug
learning_list_topics | grep -qF $'rust\tRust' \
  || { echo "FAIL: canonical name not read from the mission H1 (got the slug?)" >&2; exit 1; }

echo "test_learning_topics: PASS"
```

**Step 2: Run test to verify it fails**
Run: `bash tests/scripts/test_learning_topics.sh`
Expected: FAIL — `learning_list_topics: command not found` (exit 127 in the command substitution; the substitution yields empty and the first non-empty assertion fails), because the verb is not defined yet.

**Step 3: Write minimal implementation**

Append to `bin/learning-lib.sh`:

```bash
# Echo one line per existing topic — "<slug><TAB><canonical name>" — the name read
# from the topic's mission page H1 (`# Mission: {Topic}`, the pinned canonical name).
# Enumerates the brain wiki (learning-*-mission.md). READ-ONLY: never creates the
# brain, never mutates a page. Empty output + exit 0 when no brain/topics exist yet
# (a fresh workspace legitimately has zero topics). The /teach reconcile step matches
# a normalized argument against this list to continue an existing topic rather than
# fork a duplicate.
learning_list_topics() {
  local brain wiki page slug name
  brain=$(hjarne_resolve_brain 2>/dev/null) || return 0
  wiki="$brain/wiki"
  [[ -d "$wiki" ]] || return 0
  for page in "$wiki"/learning-*-mission.md; do
    [[ -e "$page" ]] || continue          # bash 3.2: skip an unexpanded glob
    slug=$(basename "$page" .md); slug=${slug#learning-}; slug=${slug%-mission}
    name=$(sed -n '1s/^# Mission: //p' "$page")
    printf '%s\t%s\n' "$slug" "$name"
  done
}
```

**Step 4: Run test to verify it passes**
Run: `bash tests/scripts/test_learning_topics.sh` → Expected: PASS. Re-run `bash tests/scripts/test_learning_resolve.sh` → PASS (no regression).

**Step 5: Commit**
`feat(learning): learning_list_topics — enumerate topics by pinned mission name (#99)`

---

## Task 2: Learning lib — resource-queue verbs

**Files:**
- Modify: `bin/learning-lib.sh` (append `_learning_check_id`, `learning_resource_status`, `learning_resource_mark`)
- Test: `tests/scripts/test_learning_queue.sh`

**Dependencies:** Task 1 (uses `learning_resources_page`; test sources the same lib).

**Acceptance Criteria:**
- [ ] Run: `bash tests/scripts/test_learning_queue.sh` → Expected: exit 0
- [ ] Run: `bash -n bin/learning-lib.sh` → Expected: exit 0
- [ ] Seam purity, positive: Run: `grep -qF 'hjarne_write_page' bin/learning-lib.sh` → Expected: exit 0
- [ ] Seam purity, negative: Run: `! grep -qF 'sed -i' bin/learning-lib.sh` → Expected: exit 0 (the lib's own comments must not spell the literal either — say "in-place sed")
- [ ] Seam purity, negative: Run: `! grep -qE '(printf|echo|cat)[^|]*>>? ' bin/learning-lib.sh` → Expected: exit 0 (spares `>&2`; heredocs are forbidden by construction — the version-stamp assertion below is the functional backstop)
- [ ] Id guard: malformed resource ids (outside `^[a-z0-9-]+$`) refused by both verbs before any page read — asserted inside the test
- [ ] Version-stamp proof (functional, inside the test): the persisted page carries `> Written <today> · v2` on line 2 after a mark, and exactly one stamp line — proving the write went through `hjarne_write_page`, not a raw write

**Step 1: Write the failing test**

Create `tests/scripts/test_learning_queue.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"
source "$REPO_ROOT/bin/harness-lib.sh"
source "$REPO_ROOT/bin/learning-lib.sh"   # units under test

WS=$(cd "$(mktemp -d)" && pwd)
trap 'rm -rf "$WS"' EXIT
mkdir -p "$WS/.oskr"
export OSKR_WORKSPACE="$WS"

TOPIC="Rust Macros"
PAGE=$(learning_resources_page "$TOPIC")

# Seed the resources page THROUGH the seam (v1) — the same way /teach seeds it.
SEED=$'# Rust Macros Resources\n\n## Knowledge\n\n- [Book: The Little Book of Rust Macros](https://example.com/lbrm) <!-- learning:resource id=little-book status=queued -->\n  Covers declarative macros end to end. How to use: read one chapter before each macro_rules! lesson.\n- [Article: Rust Reference — Macros](https://example.com/ref) <!-- learning:resource id=rust-reference status=queued -->\n  Normative grammar. How to use: consult for exact token-tree rules when a lesson hits edge cases.'
hjarne_write_page "$PAGE" "$SEED"

# initial status: queued
assert_eq queued "$(learning_resource_status "$TOPIC" little-book)" "seeded resource starts queued"

# queued -> ingested; sibling resource untouched
learning_resource_mark "$TOPIC" little-book ingested
assert_eq ingested "$(learning_resource_status "$TOPIC" little-book)" "mark flips to ingested"
assert_eq queued "$(learning_resource_status "$TOPIC" rust-reference)" "other resources untouched"

# persisted via hjarne_write_page: line-2 stamp, bumped to v2, today, EXACTLY one stamp,
# title preserved. This is the functional proof the mark did not raw-write the file.
TODAY=$(date +%F)
L2=$(sed -n 2p "$PAGE")
grep -qE '^> Written [0-9]{4}-[0-9]{2}-[0-9]{2} .* v[0-9]+' <<<"$L2" \
  || { echo "FAIL: no version stamp on line 2 ($L2)" >&2; exit 1; }
grep -qF 'v2' <<<"$L2" || { echo "FAIL: mark did not bump to v2 ($L2)" >&2; exit 1; }
grep -qF "$TODAY" <<<"$L2" || { echo "FAIL: stamp date not refreshed ($L2)" >&2; exit 1; }
[[ "$(grep -cE '^> Written ' "$PAGE")" -eq 1 ]] \
  || { echo "FAIL: duplicated stamp lines — mark did not strip the old stamp" >&2; exit 1; }
[[ "$(sed -n 1p "$PAGE")" == '# Rust Macros Resources' ]] \
  || { echo "FAIL: title line clobbered" >&2; exit 1; }

# idempotent re-mark: exit 0, still ingested
learning_resource_mark "$TOPIC" little-book ingested
assert_eq ingested "$(learning_resource_status "$TOPIC" little-book)" "re-mark is idempotent"

# unknown resource -> non-zero from both verbs; invalid status -> non-zero
assert_exit 1 learning_resource_status "$TOPIC" no-such-resource
assert_exit 1 learning_resource_mark "$TOPIC" no-such-resource ingested
assert_exit 1 learning_resource_mark "$TOPIC" little-book done

# malformed ids refused up front (marker contract pins ids to [a-z0-9-])
assert_exit 1 learning_resource_status "$TOPIC" 'Not_A_Slug'
assert_exit 1 learning_resource_mark "$TOPIC" 'Not_A_Slug' ingested

# seam purity (structural): hjarne_write_page is the ONLY mutation path
grep -qF 'hjarne_write_page' "$REPO_ROOT/bin/learning-lib.sh" \
  || { echo "FAIL: learning-lib does not call hjarne_write_page" >&2; exit 1; }
! grep -qF 'sed -i' "$REPO_ROOT/bin/learning-lib.sh" \
  || { echo "FAIL: sed -i found in learning-lib" >&2; exit 1; }
! grep -qE '(printf|echo|cat)[^|]*>>? ' "$REPO_ROOT/bin/learning-lib.sh" \
  || { echo "FAIL: raw file redirection found in learning-lib" >&2; exit 1; }

echo "test_learning_queue: PASS"
```

**Step 2: Run test to verify it fails**
Run: `bash tests/scripts/test_learning_queue.sh`
Expected: FAIL — stderr shows `learning_resource_status: command not found` (exit 127 inside the command substitution, whose status is discarded in argument position); the substitution yields empty output, so `assert_eq` fails the `seeded resource starts queued` comparison and the script exits non-zero.

**Step 3: Write minimal implementation**

Append to `bin/learning-lib.sh`:

```bash
# Guard: resource ids are lowercase [a-z0-9-] slugs (the marker contract). The
# id is interpolated into an ERE below, so refusing anything else keeps the
# pattern literal and makes unknown-resource errors unambiguous. Private.
_learning_check_id() {
  [[ "$1" =~ ^[a-z0-9-]+$ ]] && return 0
  echo "learning: invalid resource id '$1' — ids are lowercase [a-z0-9-] slugs" >&2
  return 1
}

# Echo a resource's queue status (queued|ingested) parsed from the topic's
# resources page marker: <!-- learning:resource id=<slug> status=<status> -->.
# Non-zero + stderr on malformed id, missing page, or unknown resource.
# learning_resource_status <topic> <resource>
learning_resource_status() {
  local topic="$1" resource="$2"
  local page line
  _learning_check_id "$resource" || return 1
  page=$(learning_resources_page "$topic") || return 1
  if [[ ! -f "$page" ]]; then
    echo "learning: no resources page for topic '$topic' (expected $page) — seed the topic first" >&2
    return 1
  fi
  line=$(grep -m1 -E "learning:resource id=${resource} status=(queued|ingested)" "$page" || true)
  if [[ -z "$line" ]]; then
    echo "learning: unknown resource '$resource' in topic '$topic' — no marker in $page" >&2
    return 1
  fi
  printf '%s\n' "$line" | sed -nE 's/.*status=(queued|ingested).*/\1/p'
}

# Flip a resource's queue status. Rejects malformed ids up front, reads the page,
# transforms it IN MEMORY (drops the line-2 version stamp — hjarne_write_page
# re-mints it — and rewrites the marker), then persists EXCLUSIVELY via
# hjarne_write_page, inheriting version stamping — no in-place sed, no direct
# file writes, no heredocs: this is the lib's only mutation path. Idempotent for
# a same-status re-mark (still a stamped rewrite).
# learning_resource_mark <topic> <resource> <queued|ingested>
learning_resource_mark() {
  local topic="$1" resource="$2" status="$3"
  local page content
  _learning_check_id "$resource" || return 1
  case "$status" in
    queued|ingested) ;;
    *) echo "learning: invalid status '$status' (expected queued|ingested)" >&2; return 1 ;;
  esac
  page=$(learning_resources_page "$topic") || return 1
  if [[ ! -f "$page" ]]; then
    echo "learning: no resources page for topic '$topic' (expected $page) — seed the topic first" >&2
    return 1
  fi
  if ! grep -qE "learning:resource id=${resource} status=(queued|ingested)" "$page"; then
    echo "learning: unknown resource '$resource' in topic '$topic' — no marker in $page" >&2
    return 1
  fi
  content=$(awk -v id="$resource" -v st="$status" '
    NR == 2 && /^> Written / { next }
    {
      sub("learning:resource id=" id " status=(queued|ingested)",
          "learning:resource id=" id " status=" st)
      print
    }
  ' "$page")
  hjarne_write_page "$page" "$content"
}
```

**Step 4: Run test to verify it passes**
Run: `bash tests/scripts/test_learning_queue.sh`
Expected: PASS. Also re-run: `bash tests/scripts/test_learning_resolve.sh` → PASS (no regression).

**Step 5: Commit**
`feat(learning): resource-queue status/mark verbs — persist only via hjarne_write_page (#99)`

---

## Task 3: harness-lib tail-source wire + wire test

**Files:**
- Modify: `bin/harness-lib.sh` (extend the tail-source block; learning after hjarne)
- Test: `tests/scripts/test_learning_lib_wire.sh`

**Dependencies:** Tasks 1–2 (the wire test drives `learning_resource_mark` end-to-end).

**Acceptance Criteria:**
- [ ] Run: `bash tests/scripts/test_learning_lib_wire.sh` → Expected: exit 0
- [ ] Run: `bash -n bin/harness-lib.sh` → Expected: exit 0
- [ ] Sourcing order (structural): the learning tail-source line appears after the hjarne one — asserted inside the wire test (line-number comparison)
- [ ] Exit-status-neutral guard: sourcing a copied `harness-lib.sh` + `hjarne-lib.sh` WITHOUT a sibling `learning-lib.sh` still exits 0 — asserted inside the wire test

**Step 1: Write the failing test**

Create `tests/scripts/test_learning_lib_wire.sh`:

```bash
#!/usr/bin/env bash
# harness-lib.sh tail-sources learning-lib.sh AFTER hjarne-lib.sh, exit-status-neutral.
# NOTE on order: both libs are function-only, so bash resolves hjarne_write_page at
# CALL time regardless of source order — the order check below is a convention
# check. The functional leg proves the WIRING: a bare `source harness-lib.sh` is
# enough to drive learning_resource_mark end to end.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"
LIB="$REPO_ROOT/bin/harness-lib.sh"

# present: bare source exposes the learning verbs
bash -c "set -e; source '$LIB'; declare -F learning_resolve_root >/dev/null; declare -F learning_resource_mark >/dev/null" \
  || { echo "FAIL: learning verbs not exposed via harness-lib.sh tail-wire" >&2; exit 1; }

# order: learning tail-source line sits after the hjarne one
H=$(grep -nF 'hjarne-lib.sh"' "$LIB" | head -1 | cut -d: -f1)
L=$(grep -nF 'learning-lib.sh"' "$LIB" | head -1 | cut -d: -f1)
[[ -n "$H" && -n "$L" && "$L" -gt "$H" ]] \
  || { echo "FAIL: learning-lib.sh not tail-sourced after hjarne-lib.sh (hjarne=$H learning=$L)" >&2; exit 1; }

# absent: harness-lib + hjarne-lib WITHOUT sibling learning-lib.sh still source cleanly
TMP=$(mktemp -d)
WS=$(cd "$(mktemp -d)" && pwd)
trap 'rm -rf "$TMP" "$WS"' EXIT
cp "$LIB" "$TMP/harness-lib.sh"
cp "$REPO_ROOT/bin/hjarne-lib.sh" "$TMP/hjarne-lib.sh"
OUT=$(bash -c "set -e; source '$TMP/harness-lib.sh'; echo ok")
[[ "$OUT" == "ok" ]] \
  || { echo "FAIL: harness-lib.sh did not source cleanly without sibling learning-lib.sh ('$OUT')" >&2; exit 1; }

# functional: end-to-end mark through a BARE `source harness-lib.sh`
mkdir -p "$WS/.oskr"
export OSKR_WORKSPACE="$WS"
bash -c '
  set -euo pipefail
  source "$1"
  SEED="# Wire Topic Resources

- [Doc](https://example.com) <!-- learning:resource id=doc status=queued -->
  How to use: skim before the first lesson."
  hjarne_write_page "$(learning_resources_page "Wire Topic")" "$SEED"
  learning_resource_mark "Wire Topic" doc ingested
' _ "$LIB"
GOT=$(bash -c 'source "$1"; learning_resource_status "Wire Topic" doc' _ "$LIB")
assert_eq ingested "$GOT" "mark round-trips through bare harness-lib sourcing"
grep -qF 'v2' "$WS/hjarne/wiki/learning-wire-topic-resources.md" \
  || { echo "FAIL: wire mark did not version-stamp via hjarne_write_page" >&2; exit 1; }

echo "test_learning_lib_wire: PASS"
```

**Step 2: Run test to verify it fails**
Run: `bash tests/scripts/test_learning_lib_wire.sh`
Expected: FAIL with `FAIL: learning verbs not exposed via harness-lib.sh tail-wire` (tail block not extended yet).

**Step 3: Write minimal implementation**

In `bin/harness-lib.sh`, immediately after the existing hjarne tail block (currently lines 1340–1342):

```bash
# --- hjarne write seam (optional sibling; tail-sourced, exit-status-neutral) ---
_HJARNE_LIB="$(dirname "${BASH_SOURCE[0]}")/hjarne-lib.sh"
if [[ -r "$_HJARNE_LIB" ]]; then source "$_HJARNE_LIB"; fi
```

append the same guard pattern for the learning lib:

```bash
# --- learning-domain seam (optional sibling; tail-sourced AFTER hjarne, exit-status-neutral) ---
_LEARNING_LIB="$(dirname "${BASH_SOURCE[0]}")/learning-lib.sh"
if [[ -r "$_LEARNING_LIB" ]]; then source "$_LEARNING_LIB"; fi
```

**Step 4: Run test to verify it passes**
Run: `bash tests/scripts/test_learning_lib_wire.sh`
Expected: PASS. Also run: `bash tests/scripts/test_hjarne_lib_wire.sh` → PASS (existing guard unchanged).

**Step 5: Commit**
`feat(learning): tail-source learning-lib.sh from harness-lib after hjarne (#99)`

---

## Task 4: `skills/teach/SKILL.md` — frontmatter, domain resolution, brain contract, seed step

*(TDD substitution: prose deliverable — AC greps written first, then the file.)*

**Files:**
- Create: `skills/teach/SKILL.md` (first half: frontmatter through Step 1)

**Dependencies:** Tasks 1–3, and Task 1.5 (Step 0.5 reconcile calls `learning_list_topics`). References `learning_topic_dir`, `learning_list_topics`, `learning_resources_page`, `learning_resource_mark` by name; the tail-wire makes `source bin/harness-lib.sh` sufficient.

**Acceptance Criteria:**
- [ ] Run: `grep -qF 'disable-model-invocation: true' skills/teach/SKILL.md` → Expected: exit 0
- [ ] Run: `grep -qF 'argument-hint:' skills/teach/SKILL.md` → Expected: exit 0
- [ ] Run: `grep -qF 'allowed-tools:' skills/teach/SKILL.md` → Expected: exit 0
- [ ] CLI-open-lesson tool scoped: Run: `grep -qF 'Bash(open *)' skills/teach/SKILL.md` → Expected: exit 0
- [ ] Note-unique provenance shape: Run: `grep -qF 'learning/<topic>:' skills/teach/SKILL.md` → Expected: exit 0
- [ ] Resolver invoked by name: Run: `grep -qF 'learning_topic_dir' skills/teach/SKILL.md` → Expected: exit 0
- [ ] Reconcile-to-continue wired: Run: `grep -qF 'learning_list_topics' skills/teach/SKILL.md` → Expected: exit 0
- [ ] Slug keyed off the confirmed name, not the raw argument: Run: `grep -qF 'confirmed canonical name' skills/teach/SKILL.md` → Expected: exit 0
- [ ] Queue mutations via the verb: Run: `grep -qF 'learning_resource_mark' skills/teach/SKILL.md` → Expected: exit 0
- [ ] Refusal remedy relayed: Run: `grep -qF '/oskr:oskr-setup' skills/teach/SKILL.md` → Expected: exit 0
- [ ] No loose-markdown knowledge store: Run: `! grep -qE '\b(MISSION|RESOURCES|GLOSSARY|NOTES)\.md\b' skills/teach/SKILL.md` → Expected: exit 0 (the `-FORMAT.md` spec references do not match)
- [ ] Queue marker documented: Run: `grep -qF 'learning:resource id=' skills/teach/SKILL.md` → Expected: exit 0
- [ ] Inbox-staged seed handled: Run: `grep -qF 'inbox' skills/teach/SKILL.md` → Expected: exit 0

**Step 1 (write AC greps):** the criteria above ARE the checks; run them against the not-yet-existing file to confirm they fail (grep exits 2/1 on missing file).

**Step 2: Write the file (first half)**

Frontmatter follows `writing-skills`: user-invoked process (`disable-model-invocation: true`), human-facing one-line description with trigger lists stripped, deliberate `allowed-tools` in the `skills/clean-up` scoped-Bash style:

````markdown
---
name: teach
description: Teach a topic across sessions — seed a mission and resource queue into the brain, then run interactive lessons from the workspace learning domain.
disable-model-invocation: true
argument-hint: "<topic> — what would you like to learn?"
allowed-tools: Bash(source bin/harness-lib.sh*) Bash(open *) Bash(mkdir *) Bash(ls *) Bash(date *) Read Write Glob Grep WebFetch WebSearch AskUserQuestion
---

Teaching is stateful — the user learns `$ARGUMENTS` over multiple sessions. All state
survives in two places and ONLY two places:

- **Knowledge state** (mission, resources + ingest queue, glossary, learning records) —
  hjarne pages in the brain, written through the `hjarne_*` seam.
- **Presentation artifacts** (lessons, reference sheets, shared assets) — files under
  the topic directory in the workspace learning domain.

Never store knowledge as loose markdown in the topic directory, and never write
presentation artifacts into the brain.

## Step 0 — Resolve the learning domain (always first)

```bash
source bin/harness-lib.sh          # tail-sources hjarne-lib.sh + learning-lib.sh
learning_resolve_root >/dev/null   # loud, instructive refusal outside a workspace
```

The resolver walks to the workspace root — it works from any directory inside the
workspace and never trusts the CWD. **If it fails: STOP.** Relay its stderr
instructions to the user verbatim (cd into a workspace, export `OSKR_WORKSPACE`, or
run `/oskr:oskr-setup`) and write NOTHING — no directory, no page, no artifact.

## Step 0.5 — Name the topic and reconcile (before any write)

The slug that keys every page is derived from a **confirmed canonical name**, never
from the raw `$ARGUMENTS`. A user may type a sentence or a typo (`I want to lear
rust`); do not slug that.

1. **Normalize.** Turn `$ARGUMENTS` into a short canonical topic name — fix typos,
   drop filler (`I want to lear rust` → `Rust`).
2. **Reconcile against existing topics:**
   ```bash
   learning_list_topics   # one line per topic: <slug><TAB><canonical name>
   ```
   Match your normalized name against this list **semantically** — it is a handful of
   entries; read them in-context, no fuzzy library needed.
   - **Match found** → confirm with the user via AskUserQuestion ("Continue your
     existing **Rust** topic?"). On yes, adopt that topic's stored name verbatim.
   - **No match** → propose the canonical name and confirm ("Start a new topic,
     **Rust**?"). On yes, that is the name.
3. **Fix the topic for the session** — only now derive the directory:
   ```bash
   TOPIC="<confirmed canonical name>"
   TOPIC_DIR=$(learning_topic_dir "$TOPIC")
   ```
   Use `$TOPIC` for every `<topic>` reference below. The slug stays stable across
   sessions because the name is **pinned** as the mission page's H1
   (`# Mission: {Topic}`), which `learning_list_topics` reads back — so a differently
   phrased re-invocation reconciles to the same topic instead of forking a duplicate.

Done when: `$TOPIC` is a confirmed canonical name (a continued topic's, or a newly
agreed one), `TOPIC_DIR` echoes `<workspace>/learning/<topic-slug>`, and nothing has
been written yet — or the session ended with the refusal relayed and zero writes.

## The brain contract

Every knowledge write goes through the hjarne seam with a **note-unique** provenance
of the shape `learning/<topic>:<slug>`:

| Page | Provenance | System slug (wiki page) | Format spec |
|---|---|---|---|
| Mission | `learning/<topic>:mission` | `learning-<topic-slug>-mission` | [MISSION-FORMAT.md](./MISSION-FORMAT.md) |
| Resources | `learning/<topic>:resources` | `learning-<topic-slug>-resources` — path from `learning_resources_page "<topic>"` | [RESOURCES-FORMAT.md](./RESOURCES-FORMAT.md) |
| Glossary | `learning/<topic>:glossary` | `learning-<topic-slug>-glossary` | [GLOSSARY-FORMAT.md](./GLOSSARY-FORMAT.md) |
| Learning record NNNN | `learning/<topic>:record-NNNN-<slug>` | `learning-<topic-slug>-record-NNNN-<slug>` | [LEARNING-RECORD-FORMAT.md](./LEARNING-RECORD-FORMAT.md) |

- **First write** of a page: `hjarne_integrate 'learning/<topic>:<slug>' '<system-slug>' "$CONTENT"` —
  archives the raw note, version-stamps the wiki page, logs a dated entry.
- **Inbox-staged seed** (brain not initialized): when the brain directory is absent,
  `hjarne_integrate` stages the note to the workspace inbox instead of writing the
  wiki page — the resources page then does not exist and `learning_resource_mark`
  fails with `no resources page`. Recognize that state, tell the user, and have them
  initialize the brain and drain the inbox (`/oskr:hjarne`) before continuing — never
  hand-create the page.
- **Update** of an existing page: `hjarne_write_page "<page-path>" "$CONTENT"` then
  `hjarne_log_append "<what changed>"` — never re-`integrate` (same provenance dedups
  to a no-op).
- **Resource queue flips**: ONLY `learning_resource_mark "<topic>" <resource-id> queued|ingested`.
  Never edit a `status=` marker by hand, never `sed` the page, never re-seed to flip status.

## Step 1 — Seed the topic (first session)

1. **Mission interview.** If no mission page exists, interview the user on WHY they
   want this (per MISSION-FORMAT.md — push back on vagueness), then integrate the
   mission page.
2. **Resource drop.** Ask the user for sources AND how to use each one. Each entry
   carries a one-line annotation, a `How to use:` instruction, and the queue marker
   `<!-- learning:resource id=<resource-slug> status=queued -->` (per
   RESOURCES-FORMAT.md). Integrate the resources page.

Done when: mission + resources pages exist in the brain (version-stamped) and every
supplied resource has an id, a How-to-use instruction, and `status=queued`.
````

**Step 3: Run the AC greps**
Run: all AC commands above → Expected: each exits 0.

**Step 4: Commit**
`feat(teach): SKILL.md frontmatter, domain resolution, brain contract, seed step (#99)`

---

## Task 5: `skills/teach/SKILL.md` — teaching loop, write gates, artifacts

*(TDD substitution: prose deliverable — AC greps first.)*

**Files:**
- Modify: `skills/teach/SKILL.md` (append second half)

**Dependencies:** Task 4; Task 2 (the loop drives `learning_resource_status` — a Task-2 verb — by name).

**Acceptance Criteria:**
- [ ] Run: `grep -qF 'learning_resource_status' skills/teach/SKILL.md` → Expected: exit 0
- [ ] Supersession preserved: Run: `grep -qF 'superseded by' skills/teach/SKILL.md` → Expected: exit 0
- [ ] Write gate stated: Run: `grep -qF 'demonstrated understanding' skills/teach/SKILL.md` → Expected: exit 0
- [ ] Artifacts pinned to the topic dir: Run: `grep -qF '$TOPIC_DIR/lessons/' skills/teach/SKILL.md && grep -qF '$TOPIC_DIR/reference/' skills/teach/SKILL.md && grep -qF '$TOPIC_DIR/assets/' skills/teach/SKILL.md` → Expected: exit 0
- [ ] CLI-open-lesson step present: Run: `grep -qF 'open "$TOPIC_DIR/lessons/' skills/teach/SKILL.md` → Expected: exit 0
- [ ] Loose-markdown ban still holds: Run: `! grep -qE '\b(MISSION|RESOURCES|GLOSSARY|NOTES)\.md\b' skills/teach/SKILL.md` → Expected: exit 0

**Step 1 (write AC greps):** run the criteria against the Task-4 file to confirm the new ones fail.

**Step 2: Append to the file**

```markdown
## Step 2 — The teaching loop (every session)

1. **Read state first**: the mission page, learning records, glossary, and the queue
   (`learning_resource_status "<topic>" <id>` per resource). Compute the zone of
   proximal development from the records — never from parametric memory of the user.
2. **Ingest before teaching**: pick the next `queued` resource whose How-to-use fits
   the lesson, read/fetch it as its instruction says, then
   `learning_resource_mark "<topic>" <id> ingested`. Ground the lesson in ingested
   resources, with citations — never in parametric knowledge alone.
3. **Author the lesson**: one self-contained HTML file at
   `$TOPIC_DIR/lessons/NNNN-<dash-case-name>.html` (NNNN increments). Short, beautiful
   (think Tufte), one tangible win, tied to the mission, inside the user's zone of
   proximal development. Reuse components from `$TOPIC_DIR/assets/` (a shared
   stylesheet is the first component every topic earns); compress durable knowledge
   into `$TOPIC_DIR/reference/*.html`. Presentation artifacts land under `$TOPIC_DIR`
   and nowhere else — never in the brain, never in the repo.
4. **Open it for the user**: `open "$TOPIC_DIR/lessons/NNNN-<dash-case-name>.html"`.
5. **Run the feedback loop**: retrieval practice, spacing, interleaving; immediate
   feedback; quiz answers formatted so length gives no clue.

Done when: the lesson file exists under `$TOPIC_DIR/lessons/`, is open for the user,
and every resource the lesson drew on is marked `ingested`.

## Write gates — records and glossary

Both are gated on **demonstrated understanding**, not coverage:

- **Learning record** (`learning/<topic>:record-NNNN-<slug>`): write one only when the
  user demonstrably understood something non-trivial, disclosed prior knowledge,
  corrected a misconception, or the mission shifted (per LEARNING-RECORD-FORMAT.md).
  NNNN = highest existing record number for the topic, plus one.
- **Glossary term**: promote a term only when the user can use it correctly.
- **Supersede, never delete**: when a later record contradicts an earlier one, rewrite
  the OLD record's page via `hjarne_write_page`, adding `Status: superseded by
  record-NNNN`, then integrate the new record. When the mission shifts, update the
  mission page (via `hjarne_write_page`) AND write a record — confirm with the user
  first.

Done when: the session's demonstrated learning is captured as record/glossary pages in
the brain, the queue reflects what was actually ingested, and the topic directory
holds only `lessons/`, `reference/`, and `assets/`.
```

**Step 3: Run the AC greps**
Run: all AC commands above (plus Task 4's, unchanged) → Expected: each exits 0.

**Step 4: Commit**
`feat(teach): SKILL.md teaching loop, write gates, artifact pinning (#99)`

---

## Task 6: Format specs — MISSION-FORMAT.md + RESOURCES-FORMAT.md

*(TDD substitution: prose deliverables — AC greps first.)*

**Files:**
- Create: `skills/teach/MISSION-FORMAT.md`
- Create: `skills/teach/RESOURCES-FORMAT.md`

**Dependencies:** Task 4 (SKILL.md links these names); Task 2 (the resources marker must match what `learning_resource_status`/`learning_resource_mark` parse).

**Acceptance Criteria:**
- [ ] Run: `grep -qF 'hjarne' skills/teach/MISSION-FORMAT.md` → Expected: exit 0 (spec rewritten against the brain contract, not a workspace file)
- [ ] Run: `grep -qF 'learning/<topic>:mission' skills/teach/MISSION-FORMAT.md` → Expected: exit 0
- [ ] Canonical-name pin documented (the H1 is what `learning_list_topics` reads back): Run: `grep -qF 'learning_list_topics' skills/teach/MISSION-FORMAT.md` → Expected: exit 0
- [ ] Marker matches the lib parser exactly: Run: `grep -qF '<!-- learning:resource id=' skills/teach/RESOURCES-FORMAT.md && grep -qF 'status=queued' skills/teach/RESOURCES-FORMAT.md` → Expected: exit 0
- [ ] Per-resource usage instruction required: Run: `grep -qF 'How to use:' skills/teach/RESOURCES-FORMAT.md` → Expected: exit 0
- [ ] Status flips route through the verb: Run: `grep -qF 'learning_resource_mark' skills/teach/RESOURCES-FORMAT.md` → Expected: exit 0
- [ ] No vendored-path references: Run: `! grep -rqF 'mattpocock' skills/teach/` → Expected: exit 0

**Step 1 (write AC greps):** the criteria above ARE the checks; run them against the not-yet-existing files to confirm the file-targeting ones fail (grep exits 2 on a missing file). The negative `! grep -rqF 'mattpocock' skills/teach/` already holds after Tasks 4–5 and must keep holding.

**Step 2: Write the files**

`skills/teach/MISSION-FORMAT.md`:

````markdown
# Mission Format

The mission is a brain page — `wiki/learning-<topic-slug>-mission.md`, first written
via `hjarne_integrate 'learning/<topic>:mission' 'learning-<topic-slug>-mission' …`,
updated via `hjarne_write_page` (the seam stamps line 2 with `> Written <date> · v<N>`;
never write that line yourself). It captures the _reason_ the user is learning this
topic. Every teaching decision — what to teach next, which resources to surface, which
exercises to design — traces back to this page.

## Template (the content you hand the seam)

```md
# Mission: {Topic}

## Why
{1-3 sentences. The concrete real-world goal. Avoid abstract framings like "to
understand X" — push for the underlying outcome.}

## Success looks like
- {A specific, observable thing the user will be able to do}
- {…}

## Constraints
- {Time, budget, prior commitments, learning preferences}

## Out of scope
- {Adjacent topics the user explicitly is not chasing — protects the zone of
  proximal development}
```

## Rules

- **The H1 is the pinned canonical name.** Line 1 `# Mission: {Topic}` IS the topic's
  canonical name — `learning_list_topics` reads it back so a differently phrased
  re-invocation reconciles to this topic. Set it from the name confirmed at the skill's
  Step 0.5 and keep it stable; renaming it forks the topic.
- **One mission per topic.** Two unrelated goals are two topics.
- **Concrete over abstract.** "Ship a Rust CLI to my team" beats "learn Rust."
- **Push back on vagueness.** If the user cannot articulate why, interview them
  before writing anything. A bad mission is worse than no mission.
- **Revise when reality shifts** — via `hjarne_write_page` (version bump), with a
  learning record capturing the change. Confirm with the user first.
- **Keep it short.** Past a screen, it has stopped being a compass.
````

`skills/teach/RESOURCES-FORMAT.md`:

````markdown
# Resources Format

The resources page is a brain page — path from `learning_resources_page "<topic>"`,
first written via `hjarne_integrate 'learning/<topic>:resources'
'learning-<topic-slug>-resources' …`, later rewritten via `hjarne_write_page` (the
seam owns the line-2 version stamp). It is the curated set of trusted sources for
the topic AND the ingest queue that persists across sessions.

## Structure (the content you hand the seam)

```md
# {Topic} Resources

## Knowledge

- [Book: _Title_ — Author](https://example.com) <!-- learning:resource id=title-author status=queued -->
  What it covers, in one line. How to use: {the instruction the user gave for this
  source — e.g. "read one chapter before each lesson", "skim §3 only"}.

## Wisdom (Communities)

- [Community name](https://example.com) <!-- learning:resource id=community-name status=queued -->
  Why it is high-signal. How to use: {when to send the user there}.
```

## The queue marker (contract with the learning lib)

Every resource bullet carries, on the bullet line itself:

```
<!-- learning:resource id=<resource-slug> status=queued -->
```

- `id` is a stable lowercase `[a-z0-9-]` slug, unique within the page.
- `status` is exactly `queued` or `ingested`.
- Flip status ONLY via `learning_resource_mark "<topic>" <id> ingested` — never by
  editing the marker. `learning_resource_status "<topic>" <id>` reads it.

## Rules

- **High-trust only.** Primary sources, recognised experts, peer-reviewed work,
  well-moderated communities. Marketing dressed as education stays out.
- **Annotate every entry** — one line on what it covers, plus a `How to use:`
  instruction. A bare link is useless in three months.
- **Surface gaps explicitly** in a `## Gaps` section when the mission needs a
  resource that does not exist yet. This drives future search.
- **Prune ruthlessly** — rewrite the page through `hjarne_write_page`; wrong or
  off-mission resources are removed, not buried.
- **Record community preferences.** If the user opted out of communities, note it
  here so future sessions stop proposing them.
````

**Step 3: Run the AC greps**
Run: all AC commands above → Expected: each exits 0.

**Step 4: Commit**
`feat(teach): mission + resources format specs against the hjarne contract (#99)`

---

## Task 7: Format specs — GLOSSARY-FORMAT.md + LEARNING-RECORD-FORMAT.md

*(TDD substitution: prose deliverables — AC greps first.)*

**Files:**
- Create: `skills/teach/GLOSSARY-FORMAT.md`
- Create: `skills/teach/LEARNING-RECORD-FORMAT.md`

**Dependencies:** Task 5 (write gates + supersession language these specs elaborate); Task 6 (sibling specs, same conventions).

**Acceptance Criteria:**
- [ ] Run: `grep -qF 'learning/<topic>:glossary' skills/teach/GLOSSARY-FORMAT.md` → Expected: exit 0
- [ ] Write gate carried: Run: `grep -qiF 'understands' skills/teach/GLOSSARY-FORMAT.md` → Expected: exit 0
- [ ] Run: `grep -qF 'learning/<topic>:record-' skills/teach/LEARNING-RECORD-FORMAT.md` → Expected: exit 0
- [ ] Supersession, not deletion: Run: `grep -qF 'superseded by' skills/teach/LEARNING-RECORD-FORMAT.md && ! grep -qiF 'delete the record' skills/teach/LEARNING-RECORD-FORMAT.md` → Expected: exit 0
- [ ] All four specs colocated: Run: `ls skills/teach/MISSION-FORMAT.md skills/teach/RESOURCES-FORMAT.md skills/teach/GLOSSARY-FORMAT.md skills/teach/LEARNING-RECORD-FORMAT.md` → Expected: exit 0

**Step 1 (write AC greps):** the criteria above ARE the checks; run them against the not-yet-existing files to confirm they fail (grep exits 2 on a missing file; the colocation `ls` exits non-zero until all four specs exist).

**Step 2: Write the files**

`skills/teach/GLOSSARY-FORMAT.md`:

````markdown
# Glossary Format

The glossary is a brain page — `wiki/learning-<topic-slug>-glossary.md`, first written
via `hjarne_integrate 'learning/<topic>:glossary' 'learning-<topic-slug>-glossary' …`,
updated via `hjarne_write_page`. It is the canonical language for the topic: every
lesson, reference sheet, and learning record adheres to its terminology.

## Structure (the content you hand the seam)

```md
# {Topic} Glossary

{One or two sentences on what this glossary covers.}

## Terms

**Hypertrophy**:
Muscle growth driven by mechanical tension and metabolic stress over repeated
training sessions.
_Avoid_: Bulking, getting big
```

## Rules

- **Add a term only when the user understands it.** The glossary records compressed
  knowledge — it is not a dictionary the user reads to learn. Wait until they can use
  the term correctly (this is the write gate).
- **Be opinionated.** One best word per concept; the rest listed as aliases to avoid.
- **Keep definitions tight.** One or two sentences; what the term IS.
- **Use the glossary's own terms inside definitions.**
- **Group under subheadings** when clusters emerge; flat is fine when terms cohere.
- **Flag ambiguities explicitly** ("in this topic, 'set' always means a working set").
- **Revise as understanding deepens** — update in place via `hjarne_write_page`
  (version bump); no stale entries.
````

`skills/teach/LEARNING-RECORD-FORMAT.md`:

````markdown
# Learning Record Format

Learning records are individual brain pages — the teaching equivalent of ADRs. Record
NNNN for a topic lives at `wiki/learning-<topic-slug>-record-NNNN-<slug>.md`, written
via `hjarne_integrate 'learning/<topic>:record-NNNN-<slug>'
'learning-<topic-slug>-record-NNNN-<slug>' …`. They capture non-obvious lessons, key
insights, and stated prior knowledge, and are the input to the zone of proximal
development.

## Template (the content you hand the seam)

```md
# {Short title of what was learned or established}

{1-3 sentences: what was learned, and why it matters for future sessions.}
```

A record can be a single paragraph. Optional sections only when they add value:
**Status** (`active | superseded by record-NNNN`), **Evidence** (how the user
demonstrated the understanding), **Implications** (what this unlocks or rules out).

## Numbering

NNNN = highest number among existing `learning-<topic-slug>-record-*` pages in the
brain wiki, plus one. Glob the wiki directory; do not keep a counter elsewhere.

## When to write one (the write gate)

Only on demonstrated understanding — never mere coverage:

1. The user demonstrably understood something non-trivial (evidence, not exposure).
2. The user disclosed prior knowledge ("I already know X"), including claimed depth.
3. A misconception was corrected.
4. The mission shifted in response to learning — cross-link and update the mission page.

Not a journal, not a duplicate of a glossary definition.

## Supersession

When a later record contradicts an earlier one, rewrite the OLD record's page via
`hjarne_write_page`, adding `Status: superseded by record-NNNN`. Records are
superseded, never removed — how understanding evolved is itself signal.
````

**Step 3: Run the AC greps**
Run: all AC commands above → Expected: each exits 0.

**Step 4: Commit**
`feat(teach): glossary + learning-record format specs against the hjarne contract (#99)`

---

## Task 8: Full-suite verification, scope fence, immutability

**Files:**
- None created/modified — verification only.

**Dependencies:** Tasks 1–7.

**Acceptance Criteria:**
- [ ] Precondition — the LOCAL Area ref resolves (see the plan-wide immutability note; `origin/WillyDallas/30` does not exist, so all diffs below pin the local ref): Run: `git rev-parse --verify WillyDallas/30` → Expected: exit 0
- [ ] Full hermetic suite green (new tests auto-discovered): Run: `bash tests/scripts/run-tests.sh` → Expected: exit 0, output includes `test_learning_resolve`, `test_learning_topics`, `test_learning_queue`, `test_learning_lib_wire`
- [ ] Forge-blind guard covers the new lib (covering test, NOT extended — it already `find`-scans all `bin/*.sh` and `bash -n`'s them): Run: `bash tests/scripts/test_backend_no_inline_gh.sh` → Expected: exit 0
- [ ] Vendored teach source untouched vs the Area merge base: Run: `git diff --quiet WillyDallas/30...HEAD -- docs/reference/` → Expected: exit 0
- [ ] No plugin.json bump (child PR): Run: `git diff --quiet WillyDallas/30...HEAD -- .claude-plugin/plugin.json` → Expected: exit 0
- [ ] hjarne seam unmodified: Run: `git diff --quiet WillyDallas/30...HEAD -- bin/hjarne-lib.sh` → Expected: exit 0
- [ ] Scope fence — no templates dir: Run: `test ! -e templates/learning` → Expected: exit 0
- [ ] Scope fence — no templates plumbing referenced: Run: `! grep -rqF 'templates/learning' bin/learning-lib.sh skills/teach/` → Expected: exit 0
- [ ] Scope fence — no stamp verb: Run: `! grep -qF 'learning_stamp' bin/learning-lib.sh` → Expected: exit 0
- [ ] Scope fence — no oskr-setup Phase 4 wiring: Run: `git diff --quiet WillyDallas/30...HEAD -- bin/oskr-setup.sh skills/oskr-setup/` → Expected: exit 0

**Step 1:** Run every command above in order; all must meet Expected. If the precondition fails, materialize the local Area ref per the plan-wide note before anything else.
**Step 2:** If any fails, fix within the owning task's contract (no new scope) and re-run the full list.
**Step 3: Commit** (only if fixes were needed): `chore(learning): verification fixes for #99 scope fence`

---

## Demo note (manual gate, not an AC)

Per the issue: invoke `/oskr:teach <topic>` from an arbitrary directory inside a workspace — it seeds the topic and the mission/resources pages land in the brain, version-stamped; invoke it outside any workspace — it refuses with the instructive message and writes nothing. This is the umbrella's manual gate (live first lesson); the hermetic tests above cover every seam it rides on.
