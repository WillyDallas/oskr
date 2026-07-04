# hjarne Write Seam + `/hjarne integrate` (T2) Implementation Plan

**Goal:** Ship the pure-filesystem `hjarne_*` write seam in a NEW `bin/hjarne-lib.sh`, wire it into `bin/harness-lib.sh` via an exit-status-neutral tail block, and wrap it in a thin `skills/hjarne/SKILL.md` (`/hjarne integrate` + drain).
**Architecture:** `hjarne_*` helpers are forge-blind, `set -euo pipefail`-safe filesystem functions that assume `blacksmith_workspace_dir` / `_blacksmith_die` are in scope (provided by `harness-lib.sh`, which tail-sources this file). One derivation `hjarne_raw_path` feeds both the raw write and the `[[ -e ]]` dedup gate; `hjarne_integrate` orchestrates archive→route→write→log when a brain exists, and falls back to `hjarne_inbox_stage` when no brain resolves — never dropping the note, never auto-creating the brain; `hjarne_inbox_stage`/`hjarne_inbox_drain` add the deferred repo-side path. The skill owns judgement (distill + note-unique provenance), the helpers own bytes.
**Tech Stack:** Pure bash (bash 3.2 / macOS-safe: no `${var,,}`, no assoc arrays, no `mapfile`), `sed`/`grep`/`shasum`, Markdown. Tests use `tests/scripts/run-tests.sh` auto-discovery + `lib/assert.sh`. No new deps.
**Issue:** #70 (T2, child of the brain-hjarne Area)

---

## EXECUTION GATE — read before starting (do NOT skip)

Written now against FROZEN upstream contracts; T2 **executes only AFTER** both blockers merge into the Area branch:
- **#54** — `blacksmith_workspace_dir` (the workspace resolver the brain sits under).
- **T1 / #69** — `bin/hjarne-skeleton.sh` + `templates/hjarne/` (every hermetic test stamps the skeleton).

**Gate check (run at repo root before Task 1; must print `GATE_OK`):**
```
grep -qF 'blacksmith_workspace_dir()' bin/harness-lib.sh \
  && test -x bin/hjarne-skeleton.sh \
  && test -f templates/hjarne/schema.md \
  && echo GATE_OK
```
If it does not print `GATE_OK`, the upstream work has not landed. **Resolve via `sync-worktree`** (merge the Area branch in). Do NOT stub the upstream functions; do NOT start Task 1.

---

## Frozen DoD recap — exemptions & TDD substitutions (for plan-reviewer)

- **Testing tier:** unit / hermetic seam. Each test stamps `bin/hjarne-skeleton.sh "$WS/hjarne"` into an `mktemp` workspace (`.oskr/` present + `OSKR_WORKSPACE` set), sources `bin/harness-lib.sh` **and** `bin/hjarne-lib.sh`, exercises the REAL resolver (no stub, no shim, forge-blind), asserts file-state.
- **Why source BOTH libs:** the §6C tail-wire lands in a *later* task (Task 10). Sourcing `harness-lib.sh` (for `blacksmith_workspace_dir`) plus `hjarne-lib.sh` (unit under test) decouples every helper test from wire ordering. After Task 10 `harness-lib.sh` also tail-sources `hjarne-lib.sh`; the second explicit `source` is a harmless redefinition.
- **Brain-optional contract (restored — the drifted #70 AC "nothing dropped or double-homed"):** *no brain resolves* means `hjarne_resolve_brain` fails (no workspace) **OR** the resolved `hjarne/` dir does not exist. In that case `hjarne_integrate` stages the note to the inbox (`HJARNE_INBOX_DIR`, default `docs/brain-inbox/`) via `hjarne_inbox_stage` and returns 0 — **nothing dropped, brain never auto-created, nothing double-homed** (the brain write path is skipped entirely). The brain is optional, never a hard dependency (row M10).
- **TDD substitution (harness-infra form: write-AC → grep/structural → implement, NO RED unit test) applies to EXACTLY three tasks:** Task 10 (tail-wire — its regression IS the §6C sourcing test, which still runs RED→GREEN), Task 11 (`skills/hjarne/SKILL.md` — semantic quality dogfooded, not hermetically tested), Task 12 (version bump). Every other task is **true RED-first**.
- **No Playwright** — no web/UI/navigation/auth surface (pure shell + prose skill). Exemption deliberate.
- **No design/quality-rule ACs** — the repo declares no `.claude/rules/` (verified). No-op axis.

### Frozen test-matrix → file → task map

| Row | Assertion | Test file | Task |
|---|---|---|---|
| M1 | `resolve_brain == $(workspace)/hjarne == skeleton stamp target` | `test_hjarne_resolve_brain.sh` | 1 |
| M3 | `raw_path` injective (distinct→distinct, same→same) | `test_hjarne_raw_path.sh` | 2 |
| — | `route → wiki/<system>.md` (unit; co-covered by M6) | `test_hjarne_raw_path.sh` (extended) | 3 |
| — | `archive_raw` writes + `mkdir -p` parents | `test_hjarne_archive_raw.sh` | 4 |
| M4 | `log_append` appends dated entry; prior content preserved | `test_hjarne_log_append.sh` | 5 |
| M2 | version stamp: create `v1`; update `v2` + date refreshed | `test_hjarne_write_page.sh` | 6 |
| M7 | `inbox_stage` writes the `<!-- hjarne:meta … -->` fence | `test_hjarne_inbox.sh` | 7 |
| M5, M6, M9 | integrate routes/dedups; two distinct provenances both land | `test_hjarne_integrate.sh` | 8 |
| M10 | no brain resolves → integrate stages to inbox (nothing dropped, brain not auto-created, not double-homed, idempotent) | `test_hjarne_integrate.sh` | 8 |
| M8 | drain integrates + removes; dup still removes; 2nd drain no-op | `test_hjarne_inbox.sh` (extended) | 9 |
| §6C | tail-wire present→exposes fn; absent→sources cleanly | `test_hjarne_lib_wire.sh` | 10 |

The frozen deliverables enumerate exactly **8 test files**. Two "extra" helpers (`route`, `inbox_drain`) share a file with a sibling (`test_hjarne_raw_path.sh`, `test_hjarne_inbox.sh`) — fixture reuse; each still gets a genuine committed RED→GREEN assertion. M10 is an added assertion block inside the existing `test_hjarne_integrate.sh` (no new file).

---

## Dependencies (per-task headers repeat this)

```
GATE (#54 + T1 merged)
  └─ T1 resolve_brain ──┬─ T2 raw_path ──┬─ T3 route (extends T2 test)
                        │                └─ T4 archive_raw
                        ├─ T5 log_append
                        ├─ T6 write_page
                        └─ T7 inbox_stage
T8 integrate  ← {T1,T2,T3,T4,T5,T6,T7}   (inbox_stage is the no-brain fallback)
T9 inbox_drain ← {T8 integrate, T7 fence format}
T10 tail-wire ← {T1 (bin/hjarne-lib.sh exists)}   [TDD-sub: §6C regression]
T11 SKILL.md  ← {T8, T9}                           [TDD-sub: dogfooded]
T12 version + contract ← {T1..T11}                 [TDD-sub: config]
```

**Shared-file hazards:** `bin/hjarne-lib.sh` (each helper task appends one function, order per graph); `test_hjarne_raw_path.sh` (T2 seeds, T3 extends); `test_hjarne_inbox.sh` (T7 seeds, T9 extends); `.claude-plugin/plugin.json` `version` (T12).

**Version:** main baseline `0.3.7`. T1 sets the Area branch to `0.4.0`; T2 is minor → target `0.5.0`. Frozen AC only requires `!= 0.3.7` AND valid semver; if `0.5.0` is taken on rebase, take the next free value.

---

## STANDARD FIXTURE (copied verbatim into the top of every hermetic test)

Every `test_hjarne_*.sh` in Tasks 1–9 opens with this exact block. Per-task "Step 1" shows only the assertions that follow it (the `echo "<name>: PASS"` line closes the file). This block is the frozen hermetic contract: `mktemp` workspace, `.oskr/` marker, skeleton stamped at `<WS>/hjarne`, both libs sourced, `OSKR_WORKSPACE` exported, `trap` cleanup.

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"
source "$REPO_ROOT/bin/harness-lib.sh"   # blacksmith_workspace_dir / _blacksmith_die
source "$REPO_ROOT/bin/hjarne-lib.sh"    # units under test

WS=$(cd "$(mktemp -d)" && pwd)           # canonicalized so /tmp symlinks don't break ==
trap 'rm -rf "$WS"' EXIT
mkdir -p "$WS/.oskr"
bash "$REPO_ROOT/bin/hjarne-skeleton.sh" "$WS/hjarne"
export OSKR_WORKSPACE="$WS"
BRAIN="$WS/hjarne"
```

---

## Task 1: `hjarne_resolve_brain` + create `bin/hjarne-lib.sh`

**Depends on:** EXECUTION GATE (#54 + T1). CREATES `bin/hjarne-lib.sh`.

**Files:** Create `bin/hjarne-lib.sh`; Test `tests/scripts/test_hjarne_resolve_brain.sh`.

**Acceptance Criteria:**
- [ ] `Run: bash -n bin/hjarne-lib.sh` → `Expected: exit 0`
- [ ] `Run: bash tests/scripts/test_hjarne_resolve_brain.sh` → `Expected: exit 0` (prints `test_hjarne_resolve_brain: PASS`; M1)
- [ ] `Run: grep -qF 'hjarne_resolve_brain()' bin/hjarne-lib.sh` → `Expected: exit 0`

**Step 1: Write the failing test** — `tests/scripts/test_hjarne_resolve_brain.sh` = STANDARD FIXTURE then:
```bash
# M1: resolve_brain == workspace/hjarne == the skeleton stamp target.
GOT=$(hjarne_resolve_brain)
assert_eq "$WS/hjarne" "$GOT" "resolve_brain == workspace/hjarne"
test -d "$GOT/wiki" || { echo "FAIL: resolve_brain path is not the skeleton stamp target ($GOT)" >&2; exit 1; }

echo "test_hjarne_resolve_brain: PASS"
```

**Step 2: Run test to verify it fails** — Run: `bash tests/scripts/test_hjarne_resolve_brain.sh`. Expected: FAIL — `bin/hjarne-lib.sh` does not exist, so `source .../hjarne-lib.sh` aborts under `set -e` (no `PASS`, exit != 0).

**Step 3: Write minimal implementation** — create `bin/hjarne-lib.sh`:
```bash
#!/usr/bin/env bash
# hjarne-lib.sh — the brain write seam: oskr's pure-filesystem knowledge helpers.
# Sourceable; not directly executable. Forge-blind (no gh, no curl).
#
# These helpers file durable knowledge into the project brain (<workspace>/hjarne):
# raw archival, wiki routing, an append-only log, version-stamped pages, an inbox
# stage/drain, and the hjarne_integrate orchestrator. The /hjarne skill drives them.
#
# Scope assumption: this file is tail-sourced by bin/harness-lib.sh, so
# blacksmith_workspace_dir and _blacksmith_die are already in scope. It defines
# functions only — no top-level statement runs, so it is safe to `source` under
# `set -euo pipefail`.

# Echo the brain root: <workspace>/hjarne. Propagates blacksmith_workspace_dir's
# loud error to stderr when no workspace resolves.
hjarne_resolve_brain() {
  local ws
  ws=$(blacksmith_workspace_dir) || return 1
  echo "$ws/hjarne"
}
```

**Step 4: Run test to verify it passes** — Run: `bash tests/scripts/test_hjarne_resolve_brain.sh`. Expected: PASS (`test_hjarne_resolve_brain: PASS`, exit 0). Also `bash -n bin/hjarne-lib.sh` → exit 0.

**Step 5: Commit** — `git add bin/hjarne-lib.sh tests/scripts/test_hjarne_resolve_brain.sh && git commit -m "feat(hjarne): resolve_brain + bin/hjarne-lib.sh seam (#70)"`

---

## Task 2: `hjarne_raw_path` — the single injective derivation (§6A)

**Depends on:** Task 1.

**Files:** Modify `bin/hjarne-lib.sh` (append `hjarne_raw_path`); Test `tests/scripts/test_hjarne_raw_path.sh` (T3 extends).

**Acceptance Criteria:**
- [ ] `Run: bash tests/scripts/test_hjarne_raw_path.sh` → `Expected: exit 0` (prints `test_hjarne_raw_path: PASS`; M3)
- [ ] `Run: grep -qF 'hjarne_raw_path()' bin/hjarne-lib.sh` → `Expected: exit 0`
- [ ] `Run: bash -n bin/hjarne-lib.sh` → `Expected: exit 0`

**Step 1: Write the failing test** — `tests/scripts/test_hjarne_raw_path.sh` = STANDARD FIXTURE then:
```bash
# M3: deterministic — same provenance → same path.
P1=$(hjarne_raw_path '#70:board-dispatcher')
P2=$(hjarne_raw_path '#70:board-dispatcher')
assert_eq "$P1" "$P2" "same provenance → same raw path"

# M3: injective — distinct provenance → distinct paths.
P3=$(hjarne_raw_path '#70:find-item')
[[ "$P1" != "$P3" ]] || { echo "FAIL: distinct provenance collided ($P1)" >&2; exit 1; }

# M3: hash disambiguates a slug collision (#70:board-dispatcher vs #70/board-dispatcher).
P4=$(hjarne_raw_path '#70/board-dispatcher')
[[ "$P1" != "$P4" ]] || { echo "FAIL: hash failed to disambiguate slug collision" >&2; exit 1; }

# shape: <brain>/raw/<slug>-<hash>.md ; subdir routes under raw/<subdir>/
case "$P1" in "$BRAIN/raw/"*-*.md) : ;; *) echo "FAIL: raw_path shape ($P1)" >&2; exit 1 ;; esac
P5=$(hjarne_raw_path '#70:deep-dive' research)
case "$P5" in "$BRAIN/raw/research/"*-*.md) : ;; *) echo "FAIL: subdir shape ($P5)" >&2; exit 1 ;; esac

echo "test_hjarne_raw_path: PASS"
```

**Step 2: Run test to verify it fails** — Run: `bash tests/scripts/test_hjarne_raw_path.sh`. Expected: FAIL — `hjarne_raw_path` undefined; `P1=$(...)` → `command not found`, `set -e` aborts (no `PASS`).

**Step 3: Write minimal implementation** — append to `bin/hjarne-lib.sh`:
```bash
# The SINGLE raw-path derivation (§6A). Used by BOTH hjarne_archive_raw (write)
# and hjarne_integrate's [[ -e ]] dedup gate. Same provenance → same path
# (deterministic); the sha256 prefix disambiguates slug collisions (injective).
# hjarne_raw_path <provenance> [subdir]
hjarne_raw_path() {
  local provenance="$1" subdir="${2:-}"
  local slug hash brain dir
  slug=$(printf '%s' "$provenance" | tr '[:upper:]' '[:lower:]' \
         | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')
  hash=$(printf '%s' "$provenance" | shasum -a 256 | cut -c1-10)
  brain=$(hjarne_resolve_brain) || return 1
  dir="$brain/raw"
  [[ -n "$subdir" ]] && dir="$dir/$subdir"
  echo "$dir/${slug}-${hash}.md"
}
```

**Step 4: Run test to verify it passes** — Run: `bash tests/scripts/test_hjarne_raw_path.sh`. Expected: PASS.

**Step 5: Commit** — `git add bin/hjarne-lib.sh tests/scripts/test_hjarne_raw_path.sh && git commit -m "feat(hjarne): raw_path single injective derivation (#70)"`

---

## Task 3: `hjarne_route` — wiki page path

**Depends on:** Task 1 (`resolve_brain`) + Task 2 (extends `test_hjarne_raw_path.sh`).

**Files:** Modify `bin/hjarne-lib.sh` (append `hjarne_route`); Modify `tests/scripts/test_hjarne_raw_path.sh`.

**Acceptance Criteria:**
- [ ] `Run: bash tests/scripts/test_hjarne_raw_path.sh` → `Expected: exit 0` (now also asserts `route → wiki/<system>.md`)
- [ ] `Run: grep -qF 'hjarne_route()' bin/hjarne-lib.sh` → `Expected: exit 0`

**Step 1: Write the failing test** — in `tests/scripts/test_hjarne_raw_path.sh`, insert **immediately before** the final `echo "test_hjarne_raw_path: PASS"` line:
```bash
# hjarne_route: <brain>/wiki/<system-slug>.md (unit; also co-covered by integrate M6)
R=$(hjarne_route board-dispatcher)
assert_eq "$BRAIN/wiki/board-dispatcher.md" "$R" "route → wiki/<system>.md"
```

**Step 2: Run test to verify it fails** — Run: `bash tests/scripts/test_hjarne_raw_path.sh`. Expected: FAIL — `hjarne_route` undefined; the new `R=$(...)` line aborts under `set -e` (the raw_path assertions above it already pass — this line is the RED).

**Step 3: Write minimal implementation** — append to `bin/hjarne-lib.sh`:
```bash
# Echo the wiki page path for a system slug: <brain>/wiki/<system-slug>.md.
# hjarne_route <system-slug>
hjarne_route() {
  local system="$1" brain
  brain=$(hjarne_resolve_brain) || return 1
  echo "$brain/wiki/${system}.md"
}
```

**Step 4: Run test to verify it passes** — Run: `bash tests/scripts/test_hjarne_raw_path.sh`. Expected: PASS.

**Step 5: Commit** — `git add bin/hjarne-lib.sh tests/scripts/test_hjarne_raw_path.sh && git commit -m "feat(hjarne): route → wiki/<system>.md (#70)"`

---

## Task 4: `hjarne_archive_raw` — write raw + `mkdir -p` parents (§6A)

**Depends on:** Task 2 (`raw_path`).

**Files:** Modify `bin/hjarne-lib.sh` (append `hjarne_archive_raw`); Test `tests/scripts/test_hjarne_archive_raw.sh`.

**Acceptance Criteria:**
- [ ] `Run: bash tests/scripts/test_hjarne_archive_raw.sh` → `Expected: exit 0` (prints `test_hjarne_archive_raw: PASS`)
- [ ] `Run: grep -qF 'hjarne_archive_raw()' bin/hjarne-lib.sh` → `Expected: exit 0`

**Step 1: Write the failing test** — `tests/scripts/test_hjarne_archive_raw.sh` = STANDARD FIXTURE then:
```bash
CONTENT=$'# Board Dispatcher\n\nThe dispatcher polls the board.'

OUT=$(hjarne_archive_raw '#70:board-dispatcher' "$CONTENT")
EXPECT=$(hjarne_raw_path '#70:board-dispatcher')
assert_eq "$EXPECT" "$OUT" "archive_raw echoes the raw_path"
test -f "$OUT" || { echo "FAIL: archive_raw did not write the file" >&2; exit 1; }
grep -qF 'The dispatcher polls the board.' "$OUT" || { echo "FAIL: content not written" >&2; exit 1; }

# subdir parents created via mkdir -p
OUT2=$(hjarne_archive_raw '#70:lit-review' "$CONTENT" research)
test -f "$OUT2" || { echo "FAIL: subdir archive not written" >&2; exit 1; }
case "$OUT2" in "$BRAIN/raw/research/"*) : ;; *) echo "FAIL: subdir not honored ($OUT2)" >&2; exit 1 ;; esac

echo "test_hjarne_archive_raw: PASS"
```

**Step 2: Run test to verify it fails** — Run: `bash tests/scripts/test_hjarne_archive_raw.sh`. Expected: FAIL — `hjarne_archive_raw` undefined; `OUT=$(...)` aborts under `set -e` (no `PASS`).

**Step 3: Write minimal implementation** — append to `bin/hjarne-lib.sh`:
```bash
# Write content to hjarne_raw_path (creating parent dirs), echo the path.
# hjarne_archive_raw <provenance> <content> [subdir]
hjarne_archive_raw() {
  local provenance="$1" content="$2" subdir="${3:-}"
  local path
  path=$(hjarne_raw_path "$provenance" "$subdir") || return 1
  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$content" > "$path"
  echo "$path"
}
```

**Step 4: Run test to verify it passes** — Run: `bash tests/scripts/test_hjarne_archive_raw.sh`. Expected: PASS.

**Step 5: Commit** — `git add bin/hjarne-lib.sh tests/scripts/test_hjarne_archive_raw.sh && git commit -m "feat(hjarne): archive_raw writes raw + mkdir -p parents (#70)"`

---

## Task 5: `hjarne_log_append` — append-only dated entry (M4)

**Depends on:** Task 1 (`resolve_brain`).

**Files:** Modify `bin/hjarne-lib.sh` (append `hjarne_log_append`); Test `tests/scripts/test_hjarne_log_append.sh`.

**Acceptance Criteria:**
- [ ] `Run: bash tests/scripts/test_hjarne_log_append.sh` → `Expected: exit 0` (prints `test_hjarne_log_append: PASS`; M4)
- [ ] `Run: grep -qF 'hjarne_log_append()' bin/hjarne-lib.sh` → `Expected: exit 0`

**Step 1: Write the failing test** — `tests/scripts/test_hjarne_log_append.sh` = STANDARD FIXTURE then:
```bash
LOG="$BRAIN/log.md"
grep -qF '# Log' "$LOG" || { echo "FAIL: skeleton log.md missing its heading" >&2; exit 1; }

# entry count keyed on a dated bullet (the skeleton's example bullet is undated → not counted)
count() { grep -cE '^- [0-9]{4}-[0-9]{2}-[0-9]{2} ' "$LOG" || true; }
[[ "$(count)" -eq 0 ]] || { echo "FAIL: expected 0 dated entries before append" >&2; exit 1; }

hjarne_log_append 'integrated board-dispatcher note'
TODAY=$(date +%F)
[[ "$(count)" -eq 1 ]] || { echo "FAIL: expected exactly 1 dated entry after append" >&2; exit 1; }
tail -1 "$LOG" | grep -qF "$TODAY" || { echo "FAIL: appended line missing today's date" >&2; exit 1; }
tail -1 "$LOG" | grep -qF 'integrated board-dispatcher note' || { echo "FAIL: message not appended" >&2; exit 1; }
grep -qF '# Log' "$LOG" || { echo "FAIL: prior content lost" >&2; exit 1; }

echo "test_hjarne_log_append: PASS"
```

**Step 2: Run test to verify it fails** — Run: `bash tests/scripts/test_hjarne_log_append.sh`. Expected: FAIL — `hjarne_log_append` undefined; the call aborts under `set -e` (no `PASS`).

**Step 3: Write minimal implementation** — append to `bin/hjarne-lib.sh`:
```bash
# Append a dated bullet to <brain>/log.md, preserving prior content. The newline
# guard keeps the entry on its own line even if the file lacks a trailing newline.
# hjarne_log_append <message>
hjarne_log_append() {
  local message="$1" brain logfile
  brain=$(hjarne_resolve_brain) || return 1
  logfile="$brain/log.md"
  mkdir -p "$brain"
  [[ -f "$logfile" && -n "$(tail -c1 "$logfile")" ]] && printf '\n' >> "$logfile"
  printf -- '- %s — %s\n' "$(date +%F)" "$message" >> "$logfile"
}
```

**Step 4: Run test to verify it passes** — Run: `bash tests/scripts/test_hjarne_log_append.sh`. Expected: PASS.

**Step 5: Commit** — `git add bin/hjarne-lib.sh tests/scripts/test_hjarne_log_append.sh && git commit -m "feat(hjarne): log_append dated append-only entry (#70)"`

---

## Task 6: `hjarne_write_page` — version-stamped write/update (§6B, M2)

**Depends on:** Task 1 (`bin/hjarne-lib.sh` exists). `write_page` takes a page-path directly and does its own `mkdir -p`, so it is resolver-independent; the fixture stamps the skeleton only for a uniform `wiki/` home.

**Files:** Modify `bin/hjarne-lib.sh` (append `hjarne_write_page`); Test `tests/scripts/test_hjarne_write_page.sh`.

**Acceptance Criteria:**
- [ ] `Run: bash tests/scripts/test_hjarne_write_page.sh` → `Expected: exit 0` (prints `test_hjarne_write_page: PASS`; M2)
- [ ] `Run: grep -qF 'hjarne_write_page()' bin/hjarne-lib.sh` → `Expected: exit 0`

**Step 1: Write the failing test** — `tests/scripts/test_hjarne_write_page.sh` = STANDARD FIXTURE then:
```bash
PAGE="$BRAIN/wiki/board-dispatcher.md"
TODAY=$(date +%F)
CONTENT=$'# Board Dispatcher\n\nThe dispatcher polls the board and moves cards.'
STAMP_RE='^> Written [0-9]{4}-[0-9]{2}-[0-9]{2} .* v[0-9]+'   # frozen M2 regex (middot-tolerant)

# create → v1 + today on line 2, title preserved on line 1
hjarne_write_page "$PAGE" "$CONTENT"
[[ "$(sed -n 1p "$PAGE")" == '# Board Dispatcher' ]] || { echo "FAIL: title line clobbered" >&2; exit 1; }
L2=$(sed -n 2p "$PAGE")
grep -qE "$STAMP_RE" <<<"$L2" || { echo "FAIL: stamp shape wrong ($L2)" >&2; exit 1; }
grep -qF 'v1' <<<"$L2" || { echo "FAIL: create not v1 ($L2)" >&2; exit 1; }
grep -qF "$TODAY" <<<"$L2" || { echo "FAIL: create date not today ($L2)" >&2; exit 1; }

# backdate the stamp (stale page), then update → v2 + date refreshed to today
tmp=$(mktemp); sed -E 's/^> Written [0-9-]+ /> Written 2000-01-01 /' "$PAGE" > "$tmp" && mv "$tmp" "$PAGE"
grep -qF '2000-01-01' "$PAGE" || { echo "FAIL: backdate setup failed" >&2; exit 1; }

hjarne_write_page "$PAGE" "$CONTENT"
L2=$(sed -n 2p "$PAGE")
grep -qE "$STAMP_RE" <<<"$L2" || { echo "FAIL: update stamp shape wrong ($L2)" >&2; exit 1; }
grep -qF 'v2' <<<"$L2" || { echo "FAIL: update not v2 ($L2)" >&2; exit 1; }
grep -qF "$TODAY" <<<"$L2" || { echo "FAIL: update date not refreshed ($L2)" >&2; exit 1; }
! grep -qF '2000-01-01' "$PAGE" || { echo "FAIL: stale date not refreshed" >&2; exit 1; }

echo "test_hjarne_write_page: PASS"
```

**Step 2: Run test to verify it fails** — Run: `bash tests/scripts/test_hjarne_write_page.sh`. Expected: FAIL — `hjarne_write_page` undefined; the first call aborts under `set -e` (no `PASS`).

**Step 3: Write minimal implementation** — append to `bin/hjarne-lib.sh` (the `·` is a literal U+00B7 middot, consistent with T1 `schema.md`'s `> Written … · v<N>` shape):
```bash
# Write/update a page, enforcing the version stamp (§6B): a blockquote on line 2
# under the `# <Title>` H1. Create → v1 + today; update → read existing v<N>, write
# v<N+1> and refresh the date to today. Content's first line is the H1 title.
# hjarne_write_page <page-path> <content>
hjarne_write_page() {
  local path="$1" content="$2"
  local today n stampline title body
  today=$(date +%F)
  if [[ -f "$path" ]]; then
    stampline=$(grep -m1 -E '^> Written [0-9]{4}-[0-9]{2}-[0-9]{2} .* v[0-9]+' "$path" 2>/dev/null || true)
    n=$(printf '%s' "$stampline" | grep -oE 'v[0-9]+' | tail -1 | tr -d 'v')
    [[ -n "$n" ]] || n=0
    n=$((n + 1))
  else
    n=1
  fi
  mkdir -p "$(dirname "$path")"
  title=$(printf '%s\n' "$content" | head -1)
  body=$(printf '%s\n' "$content" | tail -n +2)
  {
    printf '%s\n' "$title"
    printf '> Written %s · v%s\n' "$today" "$n"
    printf '%s\n' "$body"
  } > "$path"
}
```

**Step 4: Run test to verify it passes** — Run: `bash tests/scripts/test_hjarne_write_page.sh`. Expected: PASS.

**Step 5: Commit** — `git add bin/hjarne-lib.sh tests/scripts/test_hjarne_write_page.sh && git commit -m "feat(hjarne): write_page version-stamped write/update (#70)"`

---

## Task 7: `hjarne_inbox_stage` — staged note + `hjarne:meta` fence (§6E, M7)

**Depends on:** Task 1 (`bin/hjarne-lib.sh` exists). `inbox_stage` is deliberately **resolver-independent** — it runs repo-side before a brain may exist, so it must NOT call `hjarne_resolve_brain`. It inlines the same slug+hash as `raw_path` (filename uniqueness is a separate concern from dedup, which `drain` keys off the fence provenance).

**Files:** Modify `bin/hjarne-lib.sh` (append `hjarne_inbox_stage`); Test `tests/scripts/test_hjarne_inbox.sh` (T9 extends).

**Acceptance Criteria:**
- [ ] `Run: bash tests/scripts/test_hjarne_inbox.sh` → `Expected: exit 0` (prints `test_hjarne_inbox: PASS`; M7)
- [ ] `Run: grep -qF 'hjarne_inbox_stage()' bin/hjarne-lib.sh` → `Expected: exit 0`

**Step 1: Write the failing test** — `tests/scripts/test_hjarne_inbox.sh` = STANDARD FIXTURE then:
```bash
INBOX="$WS/inbox"   # inbox is a helper ARG (a fixture dir here; the skill supplies docs/brain-inbox/)
C1=$'# Board Dispatcher\n\nPolls the board.'

# M7: inbox_stage writes the hjarne:meta fence with provenance + subdir
F=$(hjarne_inbox_stage "$INBOX" '#70:board-dispatcher' "$C1" research)
test -f "$F" || { echo "FAIL: stage did not write a file" >&2; exit 1; }
grep -qF '<!-- hjarne:meta provenance=#70:board-dispatcher subdir=research -->' "$F" \
  || { echo "FAIL: meta fence missing/wrong ($(head -1 "$F"))" >&2; exit 1; }
grep -qF 'Polls the board.' "$F" || { echo "FAIL: staged content missing" >&2; exit 1; }

echo "test_hjarne_inbox: PASS"
```

**Step 2: Run test to verify it fails** — Run: `bash tests/scripts/test_hjarne_inbox.sh`. Expected: FAIL — `hjarne_inbox_stage` undefined; `F=$(...)` aborts under `set -e` (no `PASS`).

**Step 3: Write minimal implementation** — append to `bin/hjarne-lib.sh`:
```bash
# Stage a note into an inbox dir with a hjarne:meta fence carrying provenance +
# subdir (drain parses this to reconstruct the integrate call). Resolver-free by
# design: this runs repo-side before a brain may exist. Filename is the same
# provenance-keyed slug+hash as raw_path, so a re-stage of one provenance
# overwrites its own file (idempotent). Echoes the staged path.
# hjarne_inbox_stage <inbox-dir> <provenance> <content> [subdir]
hjarne_inbox_stage() {
  local inbox="$1" provenance="$2" content="$3" subdir="${4:-}"
  local slug hash file
  slug=$(printf '%s' "$provenance" | tr '[:upper:]' '[:lower:]' \
         | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')
  hash=$(printf '%s' "$provenance" | shasum -a 256 | cut -c1-10)
  mkdir -p "$inbox"
  file="$inbox/${slug}-${hash}.md"
  {
    printf '<!-- hjarne:meta provenance=%s subdir=%s -->\n' "$provenance" "$subdir"
    printf '%s\n' "$content"
  } > "$file"
  echo "$file"
}
```

**Step 4: Run test to verify it passes** — Run: `bash tests/scripts/test_hjarne_inbox.sh`. Expected: PASS.

**Step 5: Commit** — `git add bin/hjarne-lib.sh tests/scripts/test_hjarne_inbox.sh && git commit -m "feat(hjarne): inbox_stage staged note + hjarne:meta fence (#70)"`

---

## Task 8: `hjarne_integrate` — orchestrator + dedup gate + no-brain inbox fallback (M5, M6, M9, M10)

**Depends on:** Tasks 1–7 — `{resolve_brain, raw_path, route, archive_raw, log_append, write_page, inbox_stage}` (per frozen §5). Calls all seven: the **brain-present** path uses `{raw_path, archive_raw, route, write_page, log_append}`; the **no-brain fallback** uses `hjarne_inbox_stage`. Signature is UNCHANGED — `hjarne_integrate <provenance> <system> <content> [subdir]` — so T3/T4 code against it verbatim; the inbox target is routed through the `HJARNE_INBOX_DIR` env default (`docs/brain-inbox/`), NOT a new positional param.

**Files:** Modify `bin/hjarne-lib.sh` (append `hjarne_integrate`); Test `tests/scripts/test_hjarne_integrate.sh`.

**Acceptance Criteria:**
- [ ] `Run: bash tests/scripts/test_hjarne_integrate.sh` → `Expected: exit 0` (prints `test_hjarne_integrate: PASS`; M5+M6+M9+M10)
- [ ] `Run: grep -qF 'hjarne_integrate()' bin/hjarne-lib.sh` → `Expected: exit 0`
- [ ] `Run: grep -qF 'HJARNE_INBOX_DIR' bin/hjarne-lib.sh` → `Expected: exit 0` (env-default inbox target — the no-brain fallback is wired; M10)

**Step 1: Write the failing test** — `tests/scripts/test_hjarne_integrate.sh` = STANDARD FIXTURE then:
```bash
LOG="$BRAIN/log.md"
entries() { grep -cE '^- [0-9]{4}-[0-9]{2}-[0-9]{2} ' "$LOG" || true; }
C1=$'# Board Dispatcher\n\nPolls the board.'

# M6: systems note → wiki/<system>.md + raw archived
hjarne_integrate '#70:board-dispatcher' board-dispatcher "$C1"
test -f "$BRAIN/wiki/board-dispatcher.md" || { echo "FAIL: M6 page not routed to wiki" >&2; exit 1; }
test -f "$(hjarne_raw_path '#70:board-dispatcher')" || { echo "FAIL: M6 raw not archived" >&2; exit 1; }

# M6: research subdir → raw/research/
hjarne_integrate '#71:nutrition-lit' nutrition "$C1" research
RAWR=$(hjarne_raw_path '#71:nutrition-lit' research)
case "$RAWR" in "$BRAIN/raw/research/"*) test -f "$RAWR" || { echo "FAIL: research raw missing" >&2; exit 1; } ;;
  *) echo "FAIL: research subdir not honored" >&2; exit 1 ;; esac

# M5: re-integrate SAME provenance → dedup short-circuit (no v-bump, no 2nd log)
PAGE="$BRAIN/wiki/board-dispatcher.md"
V_BEFORE=$(sed -n 2p "$PAGE"); E_BEFORE=$(entries)
hjarne_integrate '#70:board-dispatcher' board-dispatcher "$C1"
assert_eq "$V_BEFORE" "$(sed -n 2p "$PAGE")" "M5 dedup: page stamp unchanged"
assert_eq "$E_BEFORE" "$(entries)" "M5 dedup: no 2nd log entry"

# M9: two distinct notes, same issue #72, distinct provenance → BOTH land, ZERO short-circuit
E0=$(entries)
hjarne_integrate '#72:find-item'  find-item  "$C1"
hjarne_integrate '#72:move-issue' move-issue "$C1"
test -f "$BRAIN/wiki/find-item.md"  || { echo "FAIL: M9 find-item page missing" >&2; exit 1; }
test -f "$BRAIN/wiki/move-issue.md" || { echo "FAIL: M9 move-issue page missing" >&2; exit 1; }
test -f "$(hjarne_raw_path '#72:find-item')"  || { echo "FAIL: M9 find-item raw missing" >&2; exit 1; }
test -f "$(hjarne_raw_path '#72:move-issue')" || { echo "FAIL: M9 move-issue raw missing" >&2; exit 1; }
[[ "$(entries)" -eq "$((E0 + 2))" ]] || { echo "FAIL: M9 expected 2 new log entries" >&2; exit 1; }

# ---------------------------------------------------------------------------
# M10: NO brain resolves → integrate STAGES to the inbox — nothing dropped, the
# brain is NOT auto-created (optional, never a hard dependency), the note is not
# double-homed (skips the brain write path entirely), and a re-integrate stays
# idempotent (inbox_stage is provenance-keyed). Uses a SEPARATE workspace whose
# hjarne/ was never stamped, so hjarne_resolve_brain succeeds but the brain dir
# is absent — the `[[ ! -d "$brain" ]]` fallback branch.
# ---------------------------------------------------------------------------
WS2=$(cd "$(mktemp -d)" && pwd)              # a workspace whose hjarne/ is NOT stamped
trap 'rm -rf "$WS" "$WS2"' EXIT              # extend cleanup (fixture trap only had $WS)
mkdir -p "$WS2/.oskr"
export OSKR_WORKSPACE="$WS2"
export HJARNE_INBOX_DIR="$WS2/brain-inbox"   # override the repo-side default via env
C2=$'# Move Issue\n\nMoves a card between columns.'
inbox_files() { find "$HJARNE_INBOX_DIR" -maxdepth 1 -name '*.md' 2>/dev/null | grep -c . || true; }

# brain dir absent → integrate stages to the inbox and returns 0 (nothing dropped)
hjarne_integrate '#80:move-issue' move-issue "$C2"
[[ "$(inbox_files)" -eq 1 ]] || { echo "FAIL: M10 no-brain integrate did not stage exactly one inbox note" >&2; exit 1; }
STAGED=$(find "$HJARNE_INBOX_DIR" -maxdepth 1 -name '*.md')
grep -qF 'Moves a card between columns.' "$STAGED" || { echo "FAIL: M10 staged note missing content" >&2; exit 1; }
grep -qF '<!-- hjarne:meta provenance=#80:move-issue' "$STAGED" || { echo "FAIL: M10 staged note missing hjarne:meta fence" >&2; exit 1; }

# brain NOT auto-created, and nothing double-homed (no page under an absent brain)
! test -e "$WS2/hjarne" || { echo "FAIL: M10 integrate auto-created the brain" >&2; exit 1; }
! test -e "$WS2/hjarne/wiki/move-issue.md" || { echo "FAIL: M10 note double-homed into a brain page" >&2; exit 1; }

# idempotent: same provenance → same inbox filename → still exactly one note
hjarne_integrate '#80:move-issue' move-issue "$C2"
[[ "$(inbox_files)" -eq 1 ]] || { echo "FAIL: M10 re-integrate not idempotent (expected exactly one inbox note)" >&2; exit 1; }

echo "test_hjarne_integrate: PASS"
```

**Step 2: Run test to verify it fails** — Run: `bash tests/scripts/test_hjarne_integrate.sh`. Expected: FAIL — `hjarne_integrate` undefined; the first call aborts under `set -e` (no `PASS`). (M10 also requires the function; the whole file is RED until Step 3.)

**Step 3: Write minimal implementation** — append to `bin/hjarne-lib.sh`:
```bash
# Orchestrate an integrate. When NO brain resolves — hjarne_resolve_brain fails
# (no workspace) OR the resolved hjarne/ dir does not exist — stage the note to
# the inbox (HJARNE_INBOX_DIR, default docs/brain-inbox/) and return 0: nothing
# dropped, brain NEVER auto-created, nothing double-homed (the brain write path
# is skipped entirely). Otherwise dedup-gate on the raw path (§6A), else archive
# the raw note, route + version-stamp the wiki page, and log a dated entry. A
# same-provenance re-integrate short-circuits (return 0) before any write.
# Signature is fixed (T3/T4 code against it); the inbox target is an env default,
# NOT a positional arg.
# hjarne_integrate <provenance> <system-slug> <content> [subdir]
hjarne_integrate() {
  local provenance="$1" system="$2" content="$3" subdir="${4:-}"
  local brain raw page inbox="${HJARNE_INBOX_DIR:-docs/brain-inbox}"
  # No brain resolves (no workspace) OR brain dir absent → stage to inbox.
  if ! brain=$(hjarne_resolve_brain 2>/dev/null) || [[ ! -d "$brain" ]]; then
    hjarne_inbox_stage "$inbox" "$provenance" "$content" "$subdir" >/dev/null || return 1
    return 0
  fi
  raw=$(hjarne_raw_path "$provenance" "$subdir") || return 1
  [[ -e "$raw" ]] && return 0   # dedup: same provenance already filed
  hjarne_archive_raw "$provenance" "$content" "$subdir" >/dev/null || return 1
  page=$(hjarne_route "$system") || return 1
  hjarne_write_page "$page" "$content" || return 1
  hjarne_log_append "integrate $provenance → wiki/${system}.md" || return 1
}
```

**Step 4: Run test to verify it passes** — Run: `bash tests/scripts/test_hjarne_integrate.sh`. Expected: PASS.

**Step 5: Commit** — `git add bin/hjarne-lib.sh tests/scripts/test_hjarne_integrate.sh && git commit -m "feat(hjarne): integrate orchestrator + dedup gate + no-brain inbox fallback (#70)"`

---

## Task 9: `hjarne_inbox_drain` — parse fence → integrate → remove (§6E, M8)

**Depends on:** Task 8 (`integrate`) + Task 7 (the `hjarne:meta` fence format it parses; extends `test_hjarne_inbox.sh`).

**Files:** Modify `bin/hjarne-lib.sh` (append `hjarne_inbox_drain`); Modify `tests/scripts/test_hjarne_inbox.sh`.

**Acceptance Criteria:**
- [ ] `Run: bash tests/scripts/test_hjarne_inbox.sh` → `Expected: exit 0` (now also asserts M8 drain)
- [ ] `Run: grep -qF 'hjarne_inbox_drain()' bin/hjarne-lib.sh` → `Expected: exit 0`

**Step 1: Write the failing test** — in `tests/scripts/test_hjarne_inbox.sh`, insert **immediately before** the final `echo "test_hjarne_inbox: PASS"` line (`$F`/`$INBOX`/`$C1` are in scope from the M7 block above):
```bash
# M8: drain integrates each staged note (subdir honored) then removes its file
hjarne_inbox_drain "$INBOX"
test -f "$BRAIN/wiki/board-dispatcher.md" || { echo "FAIL: M8 drain did not integrate" >&2; exit 1; }
test -f "$(hjarne_raw_path '#70:board-dispatcher' research)" || { echo "FAIL: M8 drain ignored subdir" >&2; exit 1; }
! test -e "$F" || { echo "FAIL: M8 drain did not remove the staged file" >&2; exit 1; }

# M8: dup short-circuit STILL removes the file
F2=$(hjarne_inbox_stage "$INBOX" '#70:board-dispatcher' "$C1" research)
hjarne_inbox_drain "$INBOX"
! test -e "$F2" || { echo "FAIL: M8 dup drain did not remove the staged file" >&2; exit 1; }

# M8: 2nd drain on an empty inbox is a no-op (exit 0 under set -e)
hjarne_inbox_drain "$INBOX"
```

**Step 2: Run test to verify it fails** — Run: `bash tests/scripts/test_hjarne_inbox.sh`. Expected: FAIL — `hjarne_inbox_drain` undefined; the first `hjarne_inbox_drain "$INBOX"` aborts under `set -e` (no `PASS`).

**Step 3: Write minimal implementation** — append to `bin/hjarne-lib.sh`:
```bash
# Drain an inbox dir: for each staged note, parse the hjarne:meta fence, integrate,
# and remove the file on success. A dedup short-circuit counts as success (integrate
# returns 0) and STILL clears the file. System slug = the :<slug> suffix of the
# provenance. No nullglob (bash 3.2): the [[ -e ]] guard skips an unexpanded glob.
# hjarne_inbox_drain <inbox-dir>
hjarne_inbox_drain() {
  local inbox="$1" file meta provenance subdir system content
  [[ -d "$inbox" ]] || return 0
  for file in "$inbox"/*.md; do
    [[ -e "$file" ]] || continue
    meta=$(grep -m1 '^<!-- hjarne:meta ' "$file" 2>/dev/null || true)
    [[ -n "$meta" ]] || continue
    provenance=$(printf '%s' "$meta" | sed -nE 's/.*provenance=([^[:space:]]+).*/\1/p')
    subdir=$(printf '%s' "$meta" | sed -nE 's/.*subdir=([^[:space:]]*).*/\1/p')
    system="${provenance##*:}"
    content=$(tail -n +2 "$file")
    if hjarne_integrate "$provenance" "$system" "$content" "$subdir"; then
      rm -f "$file"
    fi
  done
  return 0
}
```

**Step 4: Run test to verify it passes** — Run: `bash tests/scripts/test_hjarne_inbox.sh`. Expected: PASS.

**Step 5: Commit** — `git add bin/hjarne-lib.sh tests/scripts/test_hjarne_inbox.sh && git commit -m "feat(hjarne): inbox_drain fence→integrate→remove (#70)"`

---

## Task 10: `harness-lib.sh` tail-wire (§6C) — TDD SUBSTITUTION

**Depends on:** Task 1 (`bin/hjarne-lib.sh` exists). **TDD substitution (harness-infra):** write-AC → structural check → implement. The §6C sourcing regression IS the test; it still runs RED→GREEN. It must NOT hard-depend on `hjarne-lib.sh` at source time.

**Files:** Modify `bin/harness-lib.sh` (append the tail block at EOF, after the final `}` ~line 1038); Test `tests/scripts/test_hjarne_lib_wire.sh`.

**Acceptance Criteria:**
- [ ] `Run: bash tests/scripts/test_hjarne_lib_wire.sh` → `Expected: exit 0` (present→exposes fn; absent→sources cleanly)
- [ ] `Run: bash -c 'set -e; source bin/harness-lib.sh; declare -F hjarne_resolve_brain'` → `Expected: exit 0` (present case, standalone)
- [ ] `Run: grep -qF '_HJARNE_LIB=' bin/harness-lib.sh` → `Expected: exit 0`

**Step 1: Write the failing test** — create `tests/scripts/test_hjarne_lib_wire.sh`:
```bash
#!/usr/bin/env bash
# §6C: harness-lib.sh tail-sources hjarne-lib.sh, exit-status-neutral.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB="$REPO_ROOT/bin/harness-lib.sh"

# present: sourcing harness-lib.sh tail-loads hjarne-lib.sh → hjarne_resolve_brain defined
bash -c "set -e; source '$LIB'; declare -F hjarne_resolve_brain >/dev/null" \
  || { echo "FAIL: hjarne_resolve_brain not exposed via harness-lib.sh tail-wire" >&2; exit 1; }

# absent: harness-lib.sh ALONE (no sibling hjarne-lib.sh) still sources cleanly, exit 0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cp "$LIB" "$TMP/harness-lib.sh"
OUT=$(bash -c "set -e; source '$TMP/harness-lib.sh'; echo ok")
[[ "$OUT" == "ok" ]] \
  || { echo "FAIL: harness-lib.sh did not source cleanly without sibling hjarne-lib.sh ('$OUT')" >&2; exit 1; }

echo "test_hjarne_lib_wire: PASS"
```

**Step 2: Run test to verify it fails** — Run: `bash tests/scripts/test_hjarne_lib_wire.sh`. Expected: FAIL — no tail block yet, so `declare -F hjarne_resolve_brain` returns non-zero → the present-case `bash -c ... || { … exit 1; }` fires (no `PASS`).

**Step 3: Write minimal implementation** — append the FROZEN §6C block to the END of `bin/harness-lib.sh` (self-locating via `BASH_SOURCE`, never alters sourcing exit status; the file must not end on a false statement — `if …; fi` returns 0):
```bash

# --- hjarne write seam (optional sibling; tail-sourced, exit-status-neutral) ---
_HJARNE_LIB="$(dirname "${BASH_SOURCE[0]}")/hjarne-lib.sh"
if [[ -r "$_HJARNE_LIB" ]]; then source "$_HJARNE_LIB"; fi
```

**Step 4: Run test to verify it passes** — Run: `bash tests/scripts/test_hjarne_lib_wire.sh`. Expected: PASS. Also `bash tests/scripts/test_backend_no_inline_gh.sh` → exit 0 (harness-lib.sh still parses; the block adds no `gh`/`curl`).

**Step 5: Commit** — `git add bin/harness-lib.sh tests/scripts/test_hjarne_lib_wire.sh && git commit -m "feat(hjarne): tail-wire hjarne-lib.sh into harness-lib.sh (#70)"`

---

## Task 11: `skills/hjarne/SKILL.md` (`/hjarne integrate` + drain) — TDD SUBSTITUTION

**Depends on:** Task 8 (`integrate`) + Task 9 (`drain`). **TDD substitution (harness-infra):** write grep ACs → implement; semantic quality is dogfooded, not hermetically tested. **Invocation decision (per `writing-skills`):** model-invoked ability (keep the description with triggers) — the agent should reach it autonomously after research/systems discovery, and `research`/`clean-up` reach it too; model-invocation still lets a human type `/hjarne`.

**Files:** Create `skills/hjarne/SKILL.md`.

**Acceptance Criteria (grep-based structural contract):**
- [ ] `Run: grep -qE '^name: hjarne$' skills/hjarne/SKILL.md` → `Expected: exit 0`
- [ ] `Run: grep -q '^description:' skills/hjarne/SKILL.md` → `Expected: exit 0`
- [ ] `Run: grep -qF 'hjarne_integrate' skills/hjarne/SKILL.md` → `Expected: exit 0`
- [ ] `Run: grep -qF 'hjarne_inbox_drain' skills/hjarne/SKILL.md` → `Expected: exit 0`
- [ ] `Run: grep -qF '<issue-or-pr-ref>:<system-slug>' skills/hjarne/SKILL.md` → `Expected: exit 0` (provenance contract)
- [ ] `Run: grep -qF '#70:board-dispatcher' skills/hjarne/SKILL.md` → `Expected: exit 0` (worked example, NOT a bare `#70`)
- [ ] `Run: grep -qF 'docs/brain-inbox' skills/hjarne/SKILL.md` → `Expected: exit 0` (inbox call site)
- [ ] `Run: grep -qiF 'never drop' skills/hjarne/SKILL.md` → `Expected: exit 0` (no-brain fallback stated: integrate stages to the inbox, never drops; M10 contract)
- [ ] `Run: grep -qiF 'clean-up' skills/hjarne/SKILL.md` → `Expected: exit 0` (states the contract T3 must honor)
- [ ] `Run: grep -qiF 'schema.md' skills/hjarne/SKILL.md` → `Expected: exit 0` (distill-per-schema)

**Step 1: Write the acceptance criteria (above) — the grep set is the contract.**

**Step 2: Run the checks to verify they FAIL** — Run: `grep -qF 'hjarne_integrate' skills/hjarne/SKILL.md`. Expected: FAIL (exit 2, file absent).

**Step 3: Write `skills/hjarne/SKILL.md`:**
````markdown
---
name: hjarne
description: File durable knowledge into the project brain — distill a note and integrate it (or drain the repo-side inbox) into hjarne's raw/wiki/log. Reach for it after research or a systems discovery, or when another skill needs to persist permanent tech/systems knowledge.
argument-hint: "integrate | drain"
allowed-tools: Bash Read Glob Grep
---

`hjarne` is the project brain (`<workspace>/hjarne`). This skill is its **write seam**:
distil a note into a schema-shaped page, then file it through the `hjarne_*` helpers in
`bin/hjarne-lib.sh`. The helpers are pure filesystem and forge-blind — this skill owns the
**judgement** (what to distil, where it routes, the note-unique provenance); the helpers own
the **bytes**.

## Provenance — the dedup key (contract)

Every note carries a **note-unique** provenance, supplied here at the call site, of the shape
`<issue-or-pr-ref>:<system-slug>` — e.g. `#70:board-dispatcher`, **never** a bare `#70`. Same
provenance → same raw path → a re-file is a no-op (dedup short-circuit). Two notes from one
issue MUST differ in their `:<system-slug>` suffix or the second silently dedups away.
**`clean-up` (T3) honours this exact contract** — it mints a distinct `<ref>:<system>` per note
rather than reusing the issue ref.

## Steps

1. **Distil, don't dump.** Shape the note as a `wiki/` page per `templates/hjarne/schema.md`:
   a `# <Title>` H1, BLUF first, inline citations, `[[wikilinks]]`. The helper files exactly
   the bytes you give it — hand it the page, not a raw transcript.

2. **Pick route + subdir.** `<system-slug>` is the wiki page name (`wiki/<system-slug>.md`).
   Pass `research` as the optional subdir for evidence bundles (lands under `raw/research/`);
   omit it for a plain systems note.

3. **Integrate now** — when you hold the note:
   ```bash
   source bin/harness-lib.sh   # tail-sources bin/hjarne-lib.sh
   hjarne_integrate '#70:board-dispatcher' board-dispatcher "$CONTENT"   # + optional: research
   ```
   Archives the raw note, writes/updates a version-stamped `wiki/<system-slug>.md`, appends a
   dated `log.md` entry — or no-ops if that provenance was already filed. **The brain is
   optional:** if no brain resolves (no workspace, or the `hjarne/` dir isn't stamped yet),
   integrate stages the note to `docs/brain-inbox/` instead and returns cleanly — the note is
   **never dropped** and the brain is **never auto-created**. Drain it later (step 4).

4. **Or drain the inbox** — when notes were staged repo-side before a brain existed. The inbox
   lives at **`docs/brain-inbox/`**. Stage with
   `hjarne_inbox_stage docs/brain-inbox '<issue-or-pr-ref>:<system-slug>' "$CONTENT"`; later:
   ```bash
   source bin/harness-lib.sh
   hjarne_inbox_drain docs/brain-inbox
   ```
   Drain integrates each staged note and removes its file — a dedup short-circuit still counts
   as filed and still clears the file.

**Done when:** the note resolves to a version-stamped `wiki/<system-slug>.md`, its raw bytes sit
under `raw/` (or `raw/research/`), and `log.md` has the dated entry — or, when no brain resolved,
it sits in `docs/brain-inbox/` awaiting a drain — or the call dedup-short-circuited because that
provenance was already filed.
````

**Step 4: Run all grep ACs to verify they pass** — Run (single line, repo root):
```
grep -qE '^name: hjarne$' skills/hjarne/SKILL.md && grep -q '^description:' skills/hjarne/SKILL.md && grep -qF 'hjarne_integrate' skills/hjarne/SKILL.md && grep -qF 'hjarne_inbox_drain' skills/hjarne/SKILL.md && grep -qF '<issue-or-pr-ref>:<system-slug>' skills/hjarne/SKILL.md && grep -qF '#70:board-dispatcher' skills/hjarne/SKILL.md && grep -qF 'docs/brain-inbox' skills/hjarne/SKILL.md && grep -qiF 'never drop' skills/hjarne/SKILL.md && grep -qiF 'clean-up' skills/hjarne/SKILL.md && grep -qiF 'schema.md' skills/hjarne/SKILL.md && echo SKILL_AC_PASS
```
Expected: prints `SKILL_AC_PASS` (exit 0).

**Step 5: Commit** — `git add skills/hjarne/SKILL.md && git commit -m "feat(hjarne): /hjarne integrate+drain skill wrapper (#70)"`

---

## Task 12: version bump + full-suite regression (CONTRACT_OK) — TDD SUBSTITUTION

**Depends on:** Tasks 1–11. **TDD substitution:** config + regression gate, no RED unit test.

**Files:** Modify `.claude-plugin/plugin.json` (`"version"`: `0.4.0` → `0.5.0`).

**Acceptance Criteria:**
- [ ] `Run: test "$(jq -r .version .claude-plugin/plugin.json)" != "0.3.7" && jq -r .version .claude-plugin/plugin.json | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'` → `Expected: exit 0` (!= main baseline AND valid semver)
- [ ] `Run: bash tests/scripts/test_backend_no_inline_gh.sh` → `Expected: exit 0` (hjarne-lib.sh forge-blind + every `bin/*.sh` parses)
- [ ] `Run: bash tests/scripts/run-tests.sh` → `Expected: exit 0` (final line `Results: N/N passed, 0 failed`)

**Step 1: Write the ACs (above).**

**Step 2: Confirm the suite is green pre-bump** — Run: `bash tests/scripts/run-tests.sh`. Expected: PASS (Tasks 1–11 landed; the 8 new `test_hjarne_*.sh` files are auto-discovered and green).

**Step 3: Bump the version** — edit `.claude-plugin/plugin.json`: `"version": "0.4.0"` → `"version": "0.5.0"` (minor — new skill + new bin capability). If `0.5.0` is taken on rebase, take the next free minor/patch (the AC only requires `!= 0.3.7` + valid semver).

**Step 4: Run the FULL CONTRACT chain** — Run (single line, repo root):
```
bash -n bin/hjarne-lib.sh && bash tests/scripts/test_hjarne_resolve_brain.sh && bash tests/scripts/test_hjarne_raw_path.sh && bash tests/scripts/test_hjarne_archive_raw.sh && bash tests/scripts/test_hjarne_log_append.sh && bash tests/scripts/test_hjarne_write_page.sh && bash tests/scripts/test_hjarne_integrate.sh && bash tests/scripts/test_hjarne_inbox.sh && bash tests/scripts/test_hjarne_lib_wire.sh && bash tests/scripts/test_backend_no_inline_gh.sh && bash tests/scripts/run-tests.sh && test "$(jq -r .version .claude-plugin/plugin.json)" != "0.3.7" && jq -r .version .claude-plugin/plugin.json | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' && echo CONTRACT_OK
```
Expected: `run-tests.sh` prints `Results: N/N passed, 0 failed` and the chain prints `CONTRACT_OK` (exit 0). This bundles the frozen §4 verification: `bash -n` → each `test_hjarne_*.sh` (integrate now includes the M10 no-brain inbox fallback) → wire regression (present + absent, inside `test_hjarne_lib_wire.sh`) → seam guard → full suite → version `!= baseline` + valid semver.

**Step 5: Commit** — `git add .claude-plugin/plugin.json && git commit -m "chore(release): bump plugin version to 0.5.0 for hjarne write seam (#70)"`

---

## Final contract verification (repo-root runnable — frozen §4)

Run the Task 12 Step 4 chain from the repo root after all tasks. Expected: prints `CONTRACT_OK` (exit 0). It is the single command the reviewer runs to confirm the whole frozen contract holds.
