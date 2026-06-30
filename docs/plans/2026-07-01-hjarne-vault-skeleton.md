# hjarne Vault Skeleton (T1) Implementation Plan

**Goal:** Ship a committed `templates/hjarne/` brain template tree plus a pure-FS `bin/hjarne-skeleton.sh` stamp helper (with a hermetic seam test) that materializes the brain into a caller-supplied directory.
**Architecture:** The template tree is the canonical brain shape, committed under `templates/hjarne/` (empty dirs held by `.gitkeep`). `bin/hjarne-skeleton.sh` walks that tree and recreates it under a target dir — idempotent, non-clobbering, touching no forge. A `mktemp`-fixtured test stamps into a throwaway dir and pins the full surface (the 6b seam T2 inherits). No live `hjarne/` ever lands at the repo root.
**Tech Stack:** Pure bash (`set -euo pipefail`, `find`, `cp`, `mkdir -p`) + Markdown. No external libraries. Test harness is the repo's existing `tests/scripts/run-tests.sh` auto-discovery.
**Issue:** #69

---

## Frozen DoD — what this plan implements

Settled architecture (do not deviate): committed `templates/hjarne/` + `bin/hjarne-skeleton.sh` + `tests/scripts/test_hjarne_skeleton.sh`; NO live `hjarne/` at repo root; NO within-brain inbox dir at T1; NO `profile/`.

TDD substitution (flagged per DoD item 9): the stamp helper (`bin/hjarne-skeleton.sh`) gets a real RED -> GREEN unit test (Task 2). The template **content files** (`log.md`, `schema.md`, `todo.md`) and the **README boundary prose** are prose deliverables — they follow the harness-infra form *write-AC -> grep/structural check -> implement*, not RED unit tests (Tasks 1 and 3). This substitution is deliberate.

Playwright exemption (DoD item 7): CLI/plugin harness, no web surface — no Playwright AC applies.
Design-rule ACs (DoD item 8): no-op — there is no `.claude/rules/` in this repo.

---

## Dependencies & Seams (DoD item 5)

**Task ordering (sequential, each `Depends on` declared in its header):**

- **Task 1 (template tree)** — no deps. **Blocks** Task 2 (the stamp helper reads `templates/hjarne/`) and Task 3 (authors the README that lives in the tree).
- **Task 2 (stamp verb + test)** — Depends on Task 1. The stamp test asserts `test -f "$WS/README.md"`, satisfied by the Task 1 placeholder README; it does not inspect README *content*, so Task 2 and Task 3 are order-independent after Task 1.
- **Task 3 (README boundary prose)** — Depends on Task 1 (overwrites the placeholder README created there).
- **Task 4 (version bump + full-suite regression)** — Depends on Tasks 1–3 (the suite includes `test_hjarne_skeleton.sh` and `test_backend_no_inline_gh.sh`, both of which exercise Task 2's deliverables).

**W1 integration seam (FROZEN):** `bin/hjarne-skeleton.sh` IS the canonical populator that `docs/plans/2026-06-30-oskr-setup-bootstrap.md` Phase 4 (lines 385–391, "populate `hjarne/`") resolves to. `oskr-setup` today creates an EMPTY `hjarne/` (`mkdir -p "$ws/hjarne"`, lines 83/121/383) and leaves it empty when no brain skill is present. The two are INDEPENDENT-AT-RUNTIME for now. Reconciliation (wiring Phase 4 to call this helper) is owned by a LATER Area #28 brain-setup-skill task — **NOT #69**. Do not modify `oskr-setup` here.

**Shared-file hazard:** `.claude-plugin/plugin.json` `version`. Use a collision-tolerant AC (must differ from the main baseline `0.3.7` AND be valid semver). Target `0.4.0` (minor — new bin capability + template); if `0.4.0` is already taken on rebase, take the next free patch/minor value.

**Downstream:** T2 inherits Task 2's 6b fixture surface (the full set of dir/file assertions in `test_hjarne_skeleton.sh`) as its test contract. Do not narrow that surface.

---

## Task 1: Commit the `templates/hjarne/` template tree

**Depends on:** nothing.

**Files:**
- Create: `templates/hjarne/wiki/.gitkeep`
- Create: `templates/hjarne/raw/.gitkeep`
- Create: `templates/hjarne/raw/research/.gitkeep`
- Create: `templates/hjarne/projects/.gitkeep`
- Create: `templates/hjarne/log.md`
- Create: `templates/hjarne/schema.md`
- Create: `templates/hjarne/todo.md`
- Create: `templates/hjarne/README.md` (placeholder; Task 3 authors the full boundary prose)

**Acceptance Criteria:**
- [ ] `Run: test -f templates/hjarne/wiki/.gitkeep` -> `Expected: exit 0`
- [ ] `Run: test -f templates/hjarne/raw/.gitkeep` -> `Expected: exit 0`
- [ ] `Run: test -f templates/hjarne/raw/research/.gitkeep` -> `Expected: exit 0`
- [ ] `Run: test -f templates/hjarne/projects/.gitkeep` -> `Expected: exit 0`
- [ ] `Run: test -f templates/hjarne/log.md` -> `Expected: exit 0`
- [ ] `Run: test -f templates/hjarne/schema.md` -> `Expected: exit 0`
- [ ] `Run: test -f templates/hjarne/todo.md` -> `Expected: exit 0`
- [ ] `Run: test -f templates/hjarne/README.md` -> `Expected: exit 0`
- [ ] `Run: ! test -e templates/hjarne/profile` -> `Expected: exit 0` (no `profile/`)
- [ ] `Run: ! test -e hjarne` -> `Expected: exit 0` (6a — repo gains NO live brain at root)
- [ ] `Run: grep -qF 'BLUF' templates/hjarne/schema.md` -> `Expected: exit 0` (page contract: BLUF)
- [ ] `Run: grep -qF '[[wikilinks]]' templates/hjarne/schema.md` -> `Expected: exit 0` (page contract: wikilinks)
- [ ] `Run: grep -qiF 'inline citation' templates/hjarne/schema.md` -> `Expected: exit 0` (page contract: citations)
- [ ] `Run: grep -qiF 'version stamp' templates/hjarne/schema.md` -> `Expected: exit 0` (page contract: version-stamp field)

**Step 1: Write the acceptance criteria (above) — these are the structural checks.**
This is a prose/structure deliverable (DoD item 9), so the "test" is the grep/`test -f` AC set, not a RED unit test.

**Step 2: Run the checks to verify they FAIL**
Run: `test -f templates/hjarne/schema.md`
Expected: FAIL (exit 1) — `templates/hjarne/` does not exist yet.

**Step 3: Create the tree.**

Create the four empty-dir placeholders. Each `.gitkeep` is an empty file (its only job is to keep the otherwise-empty dir in git):

```bash
# Each of these is a zero-byte file:
templates/hjarne/wiki/.gitkeep
templates/hjarne/raw/.gitkeep
templates/hjarne/raw/research/.gitkeep
templates/hjarne/projects/.gitkeep
```

`templates/hjarne/log.md` (append-only timeline):

```markdown
# Log

Append-only timeline of ingests, research digests, and maintenance passes.
Newest entry at the bottom. The brain agent writes here; humans rarely do.

---

<!-- New entries below. Each entry: an H2 date header, then bullets of what
     changed. For example:

## 2026-07-01

- Brain skeleton stamped. Scaffolded raw/, raw/research/, wiki/, projects/,
  and the log.md / schema.md / todo.md pages.
-->
```

`templates/hjarne/todo.md`:

```markdown
# Todo

Open threads the brain still owes work on — questions to chase, raw sources
awaiting an ingest pass, pages to distill. Keep it short. Close an item by
moving its result into `wiki/` and recording the pass in `log.md`.

---

- [ ] (none yet)
```

`templates/hjarne/schema.md` (the layer-3 wiki page contract — defines BLUF, inline citations, `[[wikilinks]]`, and a version-stamp field):

````markdown
# Schema — the wiki page contract

Every page under `wiki/` follows the same shape so the brain — and you — can
read it, link it, and trust it. This is the layer-3 page contract.

## Required shape

1. **Title** — a single `# <Topic>` H1.
2. **Version stamp** — a blockquote directly under the title recording when the
   page was last written and in which mode, plus a version number:
   `> Written 2026-07-01 · Mode: deep · v1`.
   Bump the version and the date on every material rewrite.
3. **BLUF** — Bottom Line Up Front. The first paragraph states the answer or
   claim in 1–3 sentences, before any supporting detail. A reader who stops
   after the BLUF should still walk away with the takeaway.
4. **Body** — the supporting detail: prose, tables, steps.
5. **Sources** — a trailing `## Sources` section resolving every citation.

## Conventions

- **Inline citations.** Every non-obvious claim carries a bracketed marker —
  `[1]`, `[2]` — resolved in the `## Sources` section. No uncited assertions.
- **`[[wikilinks]]`.** Link related pages with `[[wikilinks]]` (Obsidian-style),
  not bare relative paths, so backlinks and the graph stay intact.
- **Distill, don't dump.** `raw/` holds sources verbatim; `wiki/` holds the
  distilled, linked version you actually read. The brain reads `raw/`, never
  rewrites it.

## Page skeleton

```markdown
# <Topic>

> Written <YYYY-MM-DD> · Mode: <deep|quick> · v<N>

<BLUF: the answer in 1–3 sentences.>

## <Section>

<Detail, with an inline citation where it matters [1].> Related: [[other-page]].

## Sources

[1] <author / outlet, title, URL, date accessed>
```
````

`templates/hjarne/README.md` (placeholder only — Task 3 authors the full boundary prose):

```markdown
# hjarne — the project brain

<!-- Layout table + artifact-home boundary map authored in Task 3. -->
```

**Step 4: Run the checks to verify they PASS**
Run (single line, repo root):
```
test -f templates/hjarne/wiki/.gitkeep && test -f templates/hjarne/raw/.gitkeep && test -f templates/hjarne/raw/research/.gitkeep && test -f templates/hjarne/projects/.gitkeep && test -f templates/hjarne/log.md && test -f templates/hjarne/schema.md && test -f templates/hjarne/todo.md && test -f templates/hjarne/README.md && ! test -e templates/hjarne/profile && ! test -e hjarne && grep -qF 'BLUF' templates/hjarne/schema.md && grep -qF '[[wikilinks]]' templates/hjarne/schema.md && grep -qiF 'inline citation' templates/hjarne/schema.md && grep -qiF 'version stamp' templates/hjarne/schema.md && echo ALL_AC_PASS
```
Expected: prints `ALL_AC_PASS` (exit 0).

**Step 5: Commit**
`feat(hjarne): commit templates/hjarne brain skeleton tree (#69)`

---

## Task 2: `bin/hjarne-skeleton.sh` stamp verb + hermetic seam test

**Depends on:** Task 1 (the helper reads `templates/hjarne/`).

**Files:**
- Create: `bin/hjarne-skeleton.sh`
- Test: `tests/scripts/test_hjarne_skeleton.sh`

**Acceptance Criteria:**
- [ ] `Run: bash -n bin/hjarne-skeleton.sh` -> `Expected: exit 0`
- [ ] `Run: bash tests/scripts/test_hjarne_skeleton.sh` -> `Expected: exit 0` (prints `test_hjarne_skeleton: PASS`; asserts the full 6b surface AND the 6c idempotent non-clobber)
- [ ] `Run: bash tests/scripts/test_backend_no_inline_gh.sh` -> `Expected: exit 0` (stamp helper issues no `gh`/`curl`; every `bin/*.sh` parses)

**Step 1: Write the failing test.**

Create `tests/scripts/test_hjarne_skeleton.sh`. It is hermetic (`mktemp -d` fixture, `trap` cleanup), uses NO shim, and is auto-discovered by `run-tests.sh` (matches `test_*.sh`). It mirrors the `mktemp`/no-shim exemplar `tests/scripts/test_harness_config.sh`. The asserted surface is the FROZEN 6b set plus the 6c idempotency check.

```bash
#!/usr/bin/env bash
# Hermetic seam test for the hjarne brain skeleton stamp helper.
# Stamps templates/hjarne/ into a throwaway mktemp dir and asserts the FULL
# brain surface (the 6b seam-pin contract T2 inherits), then re-stamps to
# prove it is idempotent and non-clobbering (6c). No forge, no shim.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STAMP="$REPO_ROOT/bin/hjarne-skeleton.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
WS="$TMP/brain"

# --- First stamp: full surface (6b) ---
bash "$STAMP" "$WS"

test -d "$WS/projects"     || { echo "FAIL: missing dir projects" >&2; exit 1; }
test -d "$WS/wiki"         || { echo "FAIL: missing dir wiki" >&2; exit 1; }
test -d "$WS/raw"          || { echo "FAIL: missing dir raw" >&2; exit 1; }
test -d "$WS/raw/research" || { echo "FAIL: missing dir raw/research" >&2; exit 1; }
test -f "$WS/log.md"       || { echo "FAIL: missing file log.md" >&2; exit 1; }
test -f "$WS/schema.md"    || { echo "FAIL: missing file schema.md" >&2; exit 1; }
test -f "$WS/todo.md"      || { echo "FAIL: missing file todo.md" >&2; exit 1; }
test -f "$WS/README.md"    || { echo "FAIL: missing file README.md" >&2; exit 1; }
! test -e "$WS/profile"    || { echo "FAIL: profile/ must not be stamped" >&2; exit 1; }

# --- Idempotent + non-clobbering re-stamp (6c) ---
SENTINEL="hjarne-sentinel-$$"
printf '\n%s\n' "$SENTINEL" >> "$WS/log.md"
bash "$STAMP" "$WS"   # second run must exit 0
grep -qF "$SENTINEL" "$WS/log.md" \
  || { echo "FAIL: re-stamp clobbered log.md (sentinel lost)" >&2; exit 1; }

echo "test_hjarne_skeleton: PASS"
```

**Step 2: Run test to verify it fails**
Run: `bash tests/scripts/test_hjarne_skeleton.sh`
Expected: FAIL — `bin/hjarne-skeleton.sh` does not exist yet, so `bash "$STAMP" "$WS"` exits non-zero (127, "No such file or directory") and `set -e` aborts the test (exit != 0, no `PASS` line).

**Step 3: Write minimal implementation.**

Create `bin/hjarne-skeleton.sh`. It mirrors the sibling `bin/*.sh` style (header comment with usage + exit codes, `set -euo pipefail`, `SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"`; see `bin/find-item.sh`). It is pure filesystem — it touches NO forge (no `gh`, no `curl`), so it does NOT source `harness-lib.sh`. It walks `templates/hjarne/` with `find -type f`: directories are recreated with `mkdir -p` (idempotent), content files are copied only when absent (non-clobbering), and `.gitkeep` markers are skipped after their parent dir is created.

```bash
#!/usr/bin/env bash
# Stamp the hjarne brain skeleton into a target directory.
# Usage: ./bin/hjarne-skeleton.sh <target-dir>
#
# Materializes templates/hjarne/ into <target-dir> (created if absent). Pure
# filesystem: touches no forge (no gh, no curl). Idempotent and non-clobbering
# — existing files are left untouched; only missing dirs/files are created.
# .gitkeep placeholders keep empty template dirs in git and are NOT copied; the
# directory they guard is created instead.
#
# Exits 0 on success, 2 on usage error.

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <target-dir>" >&2
  exit 2
fi

TARGET="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE_DIR="$(cd "$SCRIPT_DIR/../templates/hjarne" && pwd)"

# Walk the template tree and recreate its structure under TARGET.
while IFS= read -r src; do
  rel="${src#"$TEMPLATE_DIR"/}"
  if [[ "$(basename "$rel")" == ".gitkeep" ]]; then
    # Keep the dir; drop the git-only marker.
    mkdir -p "$TARGET/$(dirname "$rel")"
    continue
  fi
  dest="$TARGET/$rel"
  mkdir -p "$(dirname "$dest")"
  # Non-clobbering: only write a file that is not already there.
  if [[ ! -e "$dest" ]]; then
    cp "$src" "$dest"
  fi
done < <(find "$TEMPLATE_DIR" -type f)

echo "hjarne-skeleton: stamped templates/hjarne -> $TARGET"
```

**Step 4: Run test to verify it passes**
Run: `bash tests/scripts/test_hjarne_skeleton.sh`
Expected: PASS (prints `test_hjarne_skeleton: PASS`, exit 0).
Also Run: `bash -n bin/hjarne-skeleton.sh` -> exit 0, and `bash tests/scripts/test_backend_no_inline_gh.sh` -> exit 0 (the new script has no `gh (api|issue|pr|label|project)`, no bare `curl` + `api/v1`, and parses under `bash -n`).

**Step 5: Commit**
`feat(hjarne): add hjarne-skeleton.sh pure-FS stamp helper + seam test (#69)`

---

## Task 3: Author the `templates/hjarne/README.md` boundary prose

**Depends on:** Task 1 (overwrites the placeholder README created there).

**Files:**
- Modify: `templates/hjarne/README.md` (replace the Task 1 placeholder with the full content below)

**Acceptance Criteria:**
- [ ] `Run: grep -qF 'docs/brain-inbox' templates/hjarne/README.md` -> `Expected: exit 0` (6d row 4 fallback)
- [ ] `Run: grep -qF 'the brain owns the write' templates/hjarne/README.md` -> `Expected: exit 0` (6d row 4 ownership, exact literal)
- [ ] `Run: grep -qF 'docs/plans' templates/hjarne/README.md && ! grep -qiE 'plan.*(in|to) the brain' templates/hjarne/README.md` -> `Expected: exit 0` (6d row 2 — plans live in `docs/plans`, never the brain)
- [ ] `Run: grep -qiF 'conceptual' templates/hjarne/README.md` -> `Expected: exit 0` (6e — structure is conceptual)
- [ ] `Run: grep -qiF 'cross-cutting' templates/hjarne/README.md` -> `Expected: exit 0` (6e — `wiki/` is cross-cutting)
- [ ] `Run: grep -qiF 'project-named' templates/hjarne/README.md` -> `Expected: exit 0` (6e — per-project subtree is project-named)

This is a prose deliverable (DoD item 9): write-AC -> grep check -> implement. No RED unit test.

**Step 1: Write the acceptance criteria (above) — the grep checks are the contract.**

**Step 2: Run the checks to verify they FAIL**
Run: `grep -qF 'the brain owns the write' templates/hjarne/README.md`
Expected: FAIL (exit 1) — the placeholder README has no boundary prose yet.

**Step 3: Author the README.**

Replace the placeholder. Write this exact content to `templates/hjarne/README.md`:

```markdown
# hjarne — the project brain

`hjarne` is the durable knowledge base for an oskr workspace: where permanent
systems and tech knowledge lives, distilled and linked, so future work reads it
instead of relearning it. It follows Andrej Karpathy's LLM-wiki pattern — drop
sources into `raw/`, let the brain agent distill them into a clean, linked `wiki/`.

> This directory is a **template**. `bin/hjarne-skeleton.sh` stamps it into a
> workspace's `hjarne/` directory. The skeleton ships empty; the brain fills it.

## Layout

| Path | What lives here | Who maintains it |
|---|---|---|
| `raw/` | Sources, verbatim — articles, transcripts, digests, notes | Dropped in; never rewritten |
| `raw/research/` | Research evidence bundles, one folder per digest | Brain agent |
| `wiki/` | Distilled, linked Markdown — the pages you actually read | Brain agent, from `raw/` |
| `projects/` | Per-project knowledge subtrees | Brain agent |
| `log.md` | Append-only timeline of ingests and maintenance passes | Brain agent |
| `schema.md` | The wiki page contract (BLUF, citations, `[[wikilinks]]`, version stamp) | — |
| `todo.md` | Open threads the brain still owes work on | Brain agent |

The structure is **conceptual, not literal**. Each project's knowledge lives in
its own **project-named** subtree under `projects/` (for example
`projects/<project-name>/`), while `wiki/` holds **cross-cutting** knowledge that
spans projects. The paths above are the concrete skeleton the stamp helper
writes; grow them as each project needs.

## Where each artifact lives (the boundary)

Not everything belongs in the brain. The workspace separates durable knowledge
from time-bound delivery tracking:

| Artifact | Home |
|---|---|
| **Area PRD** | The umbrella **issue body** — not the brain. |
| **Per-task plan** | The repo's `docs/plans/` tree — **never the brain**. |
| **Research digest** | An **issue comment**, with an optional pointer back into the brain. |
| **Permanent systems / tech knowledge** | the brain owns the write. When no brain exists yet, it lands repo-side at `docs/brain-inbox/<date>-<system>.md` (pending #28). |

Rule of thumb: time-bound delivery state (PRDs, per-task plans, research
digests) stays on the board and under `docs/`; permanent, reusable knowledge is
what hjarne keeps for the long run.
```

**Step 4: Run the checks to verify they PASS**
Run (single line, repo root):
```
grep -qF 'docs/brain-inbox' templates/hjarne/README.md && grep -qF 'the brain owns the write' templates/hjarne/README.md && grep -qF 'docs/plans' templates/hjarne/README.md && ! grep -qiE 'plan.*(in|to) the brain' templates/hjarne/README.md && grep -qiF 'conceptual' templates/hjarne/README.md && grep -qiF 'cross-cutting' templates/hjarne/README.md && grep -qiF 'project-named' templates/hjarne/README.md && echo ALL_AC_PASS
```
Expected: prints `ALL_AC_PASS` (exit 0).

**Step 5: Commit**
`docs(hjarne): author brain README layout + artifact-home boundary map (#69)`

---

## Task 4: Version bump + full-suite regression

**Depends on:** Tasks 1–3.

**Files:**
- Modify: `.claude-plugin/plugin.json` (`"version"`: `0.3.7` -> `0.4.0`)

**Acceptance Criteria:**
- [ ] `Run: test "$(jq -r .version .claude-plugin/plugin.json)" != "0.3.7" && jq -r .version .claude-plugin/plugin.json | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'` -> `Expected: exit 0` (collision-tolerant: differs from main baseline AND valid semver)
- [ ] `Run: bash tests/scripts/run-tests.sh` -> `Expected: exit 0` (final line `Results: N/N passed, 0 failed`)
- [ ] `Run: ! test -e hjarne` -> `Expected: exit 0` (invariant re-check: still no live brain at repo root)

This is a config/regression task — no RED unit test (harness-infra form).

**Step 1: Write the acceptance criteria (above).**

**Step 2: Run the regression to confirm current state**
Run: `bash tests/scripts/run-tests.sh`
Expected: PASS already (Tasks 1–3 landed; `test_hjarne_skeleton.sh` and `test_backend_no_inline_gh.sh` both pass). Confirms the suite is green before the version bump.

**Step 3: Bump the version.**

Edit `.claude-plugin/plugin.json` line 4: change `"version": "0.3.7"` to `"version": "0.4.0"` (minor — new `bin` capability + template, pre-1.0 convention from `CLAUDE.md`). If `0.4.0` is already present on `main` after a rebase, take the next free minor/patch value (the AC only requires `!= 0.3.7` + valid semver).

**Step 4: Run all ACs to verify they pass**
Run (single line, repo root):
```
test "$(jq -r .version .claude-plugin/plugin.json)" != "0.3.7" && jq -r .version .claude-plugin/plugin.json | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' && ! test -e hjarne && bash tests/scripts/run-tests.sh
```
Expected: `run-tests.sh` prints `Results: N/N passed, 0 failed` and the whole line exits 0.

**Step 5: Commit**
`chore(release): bump plugin version to 0.4.0 for hjarne skeleton (#69)`

---

## Full contract verification (repo-root runnable — DoD)

Run all from the repo root after Task 4:

```
bash -n bin/hjarne-skeleton.sh \
  && bash tests/scripts/test_backend_no_inline_gh.sh \
  && bash tests/scripts/test_hjarne_skeleton.sh \
  && bash tests/scripts/run-tests.sh \
  && test "$(jq -r .version .claude-plugin/plugin.json)" != "0.3.7" \
  && jq -r .version .claude-plugin/plugin.json | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' \
  && ! test -e hjarne \
  && echo CONTRACT_OK
```

Expected: prints `CONTRACT_OK` (exit 0). This bundles every FROZEN DoD verification command:
- `bash -n bin/hjarne-skeleton.sh` -> exit 0
- `bash tests/scripts/test_backend_no_inline_gh.sh` -> exit 0 (stamp helper issues no `gh`/`curl`)
- `bash tests/scripts/test_hjarne_skeleton.sh` -> exit 0 (full 6b surface + 6c idempotent non-clobber)
- `bash tests/scripts/run-tests.sh` -> exit 0 (`Results: N/N passed, 0 failed`)
- version differs from main baseline `0.3.7` + valid semver
- `! test -e hjarne` -> exit 0 (no live brain at root)
