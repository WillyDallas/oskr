# Join a Workspace From a New Machine (selective rehydrate + ssh clones + travelling memory) Implementation Plan

**Goal:** Let a second machine join an existing oskr workspace: clone the workspace repo, run `/oskr-setup`, pick which projects to clone, and get them over ssh — with each project's Claude Code auto-memory travelling in the workspace repo instead of staying in `~/.claude` on one machine.
**Architecture:** Four additions to `bin/oskr-setup.sh`, all pure local git + jq (no forge API, so they stay outside the backend seam, like `git-init`/`rehydrate`/`save`): `rehydrate --only <name>` + present/missing dry-run, an optional `forgejo.ssh_base` clone preference, a `memory-link` verb, and a `pull` verb. `/oskr-setup` gains a **Join** branch where Phase 0 currently stops on an existing config.
**Tech Stack:** Bash (`set -euo pipefail`), `git`, `jq`, `tests/scripts/lib/assert.sh`, auto-discovered by `run-tests.sh`.
**Issue:** #122 — relates to #35 (clean-machine test) and #38 (install path).

---

## Decisions (settled in session 2026-09-30)

- **The plugin comes from GitHub, the workspace from Forgejo.** `claude plugin marketplace add WillyDallas/oskr` + `claude plugin install oskr@oskr-marketplace` works today (public repo). No plugin-install work here.
- **Join is a branch of `/oskr-setup`, not a new skill.** The Phase 0 guard fires on exactly the state a fresh clone produces (`.oskr/config.json` exists) — so it offers to join instead of stopping. One entry point.
- **Forgejo clones go over ssh when `forgejo.ssh_base` is set.** https only works on the current Mac because Keychain holds a credential nothing records.
- **Memory lives in the workspace repo at `<ws>/memory/<project>/`.** The workspace is private and personal; project repos can be shared (booby-trappin), so personal feedback memories don't belong there. Claude Code's `autoMemoryDirectory` setting points each project at it.
- **The pointer goes in the project's tracked `.claude/settings.json`**, as a `~/`-relative path. Tracked (not `settings.local.json`) so every worktree and every machine picks it up with no per-machine step. Cost: it assumes the workspace sits at the same `~/` path on every machine — the Join flow checks this and warns.

## Tradeoffs accepted

- **Memory in the workspace makes sync mandatory.** Every session can dirty the workspace repo. Two machines writing the same project's memory between syncs will conflict (most likely on `MEMORY.md`). Mitigation: the `pull` verb (T4) and a "pull at start, save + push at end" habit. No auto-sync.
- **`autoMemoryDirectory` from project settings waits for folder trust**, and is ignored if `permissions.blockReadsOutsideWorkingDirectories` is on. Neither is set today.
- **The migration's default source path relies on Claude Code's slug format** (`/` and `.` → `-`), which is undocumented. `--from` overrides it, and the verb copies (never moves), so a wrong guess loses nothing.

## Exemptions

- **No Playwright AC** — shell verbs + SKILL.md prose, no UI.
- **No live-forge AC** — every clone/pull targets a LOCAL `git init --bare` fixture. The live run is the M1 setup itself (#35).
- **T5 is prose** (SKILL.md) — harness-infra substitution: write AC → grep check → implement, not red/green.

## Cross-task dependencies

- T1 ⊥ T3 ⊥ T4 ⊥ T6 — independent.
- T2 → T1 — shares the refactored clone-URL helper.
- T5 → T1, T2, T3, T4 — the Join branch calls every new verb/flag; names frozen below.

## Frozen contracts

- `rehydrate <ws> [--dry-run] [--only <name>]...` — `--only` is repeatable; an unknown name dies **before any clone** with `rehydrate: no project '<name>' in registry`. Dry-run prints one line per selected entry: `rehydrate: projects/<name> present` or `rehydrate: would clone <url> -> projects/<name>` (existing "would clone" format kept).
- `forgejo.ssh_base` in `.oskr/config.json` — optional, e.g. `ssh://git@git.squirrlylabs.xyz:2222`. Used for a forgejo registry entry **only when** that entry's `base_url` equals config `forgejo.base_url` (trailing `/` ignored). Clone URL: `<ssh_base without trailing />/<owner>/<repo>.git`. Otherwise the existing https composition.
- `memory-link <ws> <name> [--from <dir>]` — creates `<ws>/memory/<name>/`; copies `--from` (default `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/<slug>/memory`, slug = absolute checkout path with `/` and `.` → `-`) into it **only if the target is empty**; merges `autoMemoryDirectory` into `projects/<name>/.claude/settings.json` (other keys preserved), `~/`-prefixed when under `$HOME`, else absolute. Commits nothing.
- `pull <ws>` — `git pull --rebase --autostash`; on a stopped rebase dies with `pull: rebase stopped — resolve in <ws>, then git -C <ws> rebase --continue`. Never pushes.
- Push-free grep AC from the #113 plan still holds for `bin/oskr-setup.sh`.
- zsh rule: no variable named `path`, `options`, `status`, `argv`, `fpath`, `cdpath`.

---

## Task 1: `rehydrate --only` + present/missing dry-run

**Files:** Modify `bin/oskr-setup.sh` (`oskr_setup_rehydrate`, extract `_oskr_setup_clone_url <ws> <i>`), `tests/scripts/test_workspace_gitinit.sh` (new T7 section).

**Acceptance Criteria:**
- [ ] Two-entry registry, `rehydrate "$WS" --only b` clones only `projects/b` — `Run: test -d "$WS/projects/b/.git" && ! test -e "$WS/projects/a"` → exit 0.
- [ ] `--only nope` exits non-zero, stderr contains `no project 'nope' in registry`, and `projects/` is empty.
- [ ] After cloning `b`, `rehydrate "$WS" --dry-run` prints `projects/b present` and `would clone` for `a`.
- [ ] Existing T3 rehydrate assertions still pass — `Run: bash tests/scripts/test_workspace_gitinit.sh` → exit 0.

**Step 1: Failing test** — append to `test_workspace_gitinit.sh`: two bare fixtures `acme/a.git`, `acme/b.git` under `$TMPROOT/forge7`, a registry with both as forgejo entries (`base_url` = `$TMPROOT/forge7`), then the three assertions above. Run → FAIL (`unknown flag '--only'`).

**Step 2: Implement.**
- Parse `--only <name>` into a space-joined list; die on a missing value.
- Before the loop, validate each `--only` name with `jq -e --arg n "$n" '.projects[] | select(.name == $n)'`.
- In the loop, skip entries not in the list (`case " $only " in *" $name "*) ;; *) continue ;; esac` — increment `i` first).
- Move the URL `case` into `_oskr_setup_clone_url` (T2 extends it).
- Dry-run checks `"$dest/.git"` first: `present` line, else the existing `would clone` line.

**Step 3:** Run the file → PASS. `bash -n bin/oskr-setup.sh` → exit 0.

## Task 2: ssh clone preference (`forgejo.ssh_base`)

**Files:** Modify `bin/oskr-setup.sh` (`_oskr_setup_clone_url`), `tests/scripts/test_workspace_gitinit.sh` (T8).

**Acceptance Criteria:**
- [ ] Config `forgejo.base_url = "https://forge.test"`, `forgejo.ssh_base = "$TMPROOT/ssh8"`; a registry entry on `https://forge.test/` (trailing slash) with a bare at `$TMPROOT/ssh8/acme/w.git` → `rehydrate` clones it (proves the ssh_base URL was used; the https URL is unreachable).
- [ ] A second entry on a DIFFERENT `base_url` → `--dry-run` shows its https URL, not ssh_base.
- [ ] No `ssh_base` in config → dry-run output identical to today's composition.

**Step 1: Failing test** as above. Run → FAIL (clone of `https://forge.test/...` errors).

**Step 2: Implement** in the forgejo arm:
```bash
cfg_base="$(jq -r '.forgejo.base_url // ""' "$ws/.oskr/config.json" 2>/dev/null || true)"
ssh_base="$(jq -r '.forgejo.ssh_base // ""' "$ws/.oskr/config.json" 2>/dev/null || true)"
if [[ -n "$ssh_base" && "${base%/}" == "${cfg_base%/}" ]]; then
  printf '%s/%s/%s.git' "${ssh_base%/}" "$owner" "$repo"
else
  printf '%s/%s/%s.git' "${base%/}" "$owner" "$repo"
fi
```
Update the "Clone URLs" header comment.

**Step 3:** Run → PASS.

## Task 3: `memory-link` verb

**Files:** Modify `bin/oskr-setup.sh` (new verb + dispatcher + usage), `tests/scripts/test_workspace_gitinit.sh` (T9).

**Acceptance Criteria** (fixture: `HOME="$TMPROOT/home9"`, a ws at `$HOME/ws`, `projects/p` as a git repo with an existing `.claude/settings.json` = `{"permissions":{"allow":["Bash(ls)"]}}`, a `--from` dir holding `MEMORY.md` + `a.md`):
- [ ] `memory-link "$WS" p --from "$SRC"` → `$WS/memory/p/MEMORY.md` and `a.md` exist.
- [ ] `jq -r .autoMemoryDirectory projects/p/.claude/settings.json` = `~/ws/memory/p`, and `.permissions.allow[0]` is still `Bash(ls)`.
- [ ] Re-run after editing `$WS/memory/p/a.md` → edit survives (no clobber on non-empty target).
- [ ] `memory-link "$WS" missing` exits non-zero with `not cloned`.
- [ ] Workspace outside `$HOME` → absolute path written.

**Step 1: Failing test.** Run → FAIL (unknown verb).

**Step 2: Implement:**
```bash
# memory-link <workspace_dir> <name> [--from <dir>] — move a project's Claude Code
# auto-memory into the workspace repo (<ws>/memory/<name>/) so it travels with
# save + push. Points the project at it via autoMemoryDirectory in its TRACKED
# .claude/settings.json (worktrees and other machines pick it up). Copies the old
# memory only into an empty target — never clobbers. Commits nothing.
oskr_setup_memory_link() {
  local ws="${1:-}" name="${2:-}"; [[ $# -ge 2 ]] && shift 2
  local from=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --from) [[ $# -ge 2 ]] || _setup_die "memory-link: --from requires a dir"; from="$2"; shift 2 ;;
      *) _setup_die "memory-link: unknown flag '$1'" ;;
    esac
  done
  [[ -n "$ws" && -n "$name" ]] || _setup_die "usage: memory-link <workspace_dir> <name> [--from <dir>]"
  ws="$(cd "$ws" && pwd)"
  local proj="$ws/projects/$name" mem="$ws/memory/$name" settings dir_ref
  [[ -d "$proj/.git" ]] || _setup_die "memory-link: projects/$name is not cloned"
  mkdir -p "$mem"
  [[ -n "$from" ]] || from="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/$(printf '%s' "$proj" | tr '/.' '--')/memory"
  if [[ -d "$from" && -z "$(ls -A "$mem")" ]]; then cp -R "$from/." "$mem/"; fi
  case "$mem" in "$HOME"/*) dir_ref="~/${mem#"$HOME"/}" ;; *) dir_ref="$mem" ;; esac
  settings="$proj/.claude/settings.json"
  mkdir -p "$proj/.claude"; [[ -f "$settings" ]] || printf '{}\n' > "$settings"
  jq --arg d "$dir_ref" '.autoMemoryDirectory = $d' "$settings" > "$settings.tmp" \
    && mv "$settings.tmp" "$settings"
}
```
Add `memory-link) oskr_setup_memory_link "$@" ;;` and extend the usage string.

**Step 3:** Run → PASS.

## Task 4: `pull` verb

**Files:** Modify `bin/oskr-setup.sh`, `tests/scripts/test_workspace_gitinit.sh` (T10).

**Acceptance Criteria** (fixture: a bare `ws.git`, clones `A` and `B`, identity injected via `-c`):
- [ ] Commit + push in `A`; `pull "$B"` → `B` has the commit.
- [ ] With an uncommitted edit in `B`, `pull` succeeds and the edit remains (autostash).
- [ ] Conflicting commits to the same line in `A` (pushed) and `B` → `pull` exits non-zero, stderr contains `rebase stopped`.
- [ ] Non-repo dir → dies with `run git-init first`.
- [ ] Push-free grep AC on `bin/oskr-setup.sh` still passes.

**Step 1: Failing test.** Run → FAIL.

**Step 2: Implement:**
```bash
# pull <workspace_dir> — bring the control plane (registry, brain, memory) up to
# date before working on this machine. Rebase + autostash so local memory edits
# ride along. Local-only apart from the fetch; never pushes.
oskr_setup_pull() {
  local ws="${1:-$PWD}"
  git -C "$ws" rev-parse --git-dir >/dev/null 2>&1 \
    || _setup_die "pull: $ws is not a git repo — run git-init first"
  git -C "$ws" -c user.email="${OSKR_GIT_EMAIL:-oskr@squirrlylabs.local}" \
    -c user.name="${OSKR_GIT_NAME:-oskr}" pull -q --rebase --autostash \
    || _setup_die "pull: rebase stopped — resolve in $ws, then git -C $ws rebase --continue"
}
```

**Step 3:** Run → PASS. Full suite: `bash tests/scripts/run-tests.sh` → all green.

## Task 5: `/oskr-setup` Join branch (prose)

**Files:** Modify `skills/oskr-setup/SKILL.md` (Phase 0 guard → Join branch; new `## Join: set up this machine` section; update the Phase 3b "Reconstructing on a new machine" paragraph to point at it; add `Bash(git -C *)` to `allowed-tools` if not covered by `Bash(git *)`).

**Acceptance Criteria** (grep `-qF` on SKILL.md):
- [ ] Contains `set up this machine` and `new machine` in the Phase 0 guard.
- [ ] Contains `oskr-setup.sh" pull`, `rehydrate "$WS" --dry-run`, `--only`, `memory-link`.
- [ ] Contains `forgejo.ssh_base`.
- [ ] Contains the rule `never read or write .env` (existence check only).

**Step 1:** Write the checks. Run → FAIL.

**Step 2:** Replace the guard with: "This directory is already an oskr workspace. Is this a **new machine** joining it? → Join. Otherwise stop (unchanged message)." Join steps, one question at a time:
1. **Prerequisites.** `command -v git jq` (plus `gh` only if the registry has a github entry). `test -f "$WS/.env"`, existence only — never read or write `.env`. If missing, tell the developer to create it with `FORGEJO_TOKEN=<pat>`, and suggest a separate limited token for this machine.
2. **Sync.** `"${CLAUDE_PLUGIN_ROOT}/bin/oskr-setup.sh" pull "$WS"`.
3. **Clone protocol.** If `forge` is forgejo and `forgejo.ssh_base` is empty, ask for it (default: derive from `git -C "$WS" remote get-url origin` when that is `ssh://`), write it with jq, then `save`.
4. **Choose.** Show `rehydrate "$WS" --dry-run`. Ask which missing projects to clone (names). Then `rehydrate "$WS" --only <a> --only <b>`.
5. **Per project, report what's still manual.** `.env.example` present → copy to `.env` and fill in by hand. Project `CLAUDE.md` names the toolchain. Memory: if `.claude/settings.json` has `autoMemoryDirectory`, check it resolves to `$WS/memory/<name>`, and warn if the workspace is at a different path. If it's absent, offer `memory-link` (then the developer commits the project's `.claude/settings.json`).
6. **Close** with the sync habit: "pull at the start of a session, `save` + push at the end — memory now lives here."

**Step 3:** Run checks → PASS.

## Task 6: `.gitignore` template drift (`hjarne/raw/`)

**Files:** Modify `bin/oskr-setup.sh` (`_oskr_setup_gitignore_body`), `tests/scripts/test_workspace_gitinit.sh` (T1 ignored matrix).

**Acceptance Criteria:**
- [ ] `git check-ignore -q hjarne/raw/x.md` → exit 0 on a fresh git-init'd workspace.
- [ ] `! git check-ignore -q hjarne/wiki/x.md` and `! git check-ignore -q memory/p/MEMORY.md` → exit 0 (brain wiki and memory stay tracked).

**Steps:** Add the assertions (FAIL), add the two template lines matching the live workspace (`# Brain raw sources stay machine-local; only the distilled wiki is tracked.` / `hjarne/raw/`), then PASS.

---

## Rollout (manual, on the current Mac — before touching the M1)

1. `jq '.forgejo.ssh_base = "ssh://git@git.squirrlylabs.xyz:2222"'` into `squirrlylabs/.oskr/config.json`.
2. `oskr-setup.sh memory-link ~/WillyDev/squirrlylabs nas-map` → commit `projects/nas-map/.claude/settings.json` in NasMap. Repeat for other projects you want on both machines.
3. Open a nas-map session; `/memory` shows the auto-memory folder under `squirrlylabs/memory/nas-map`.
4. `oskr-setup.sh save` + push the workspace.

Then on the M1: install Claude Code, git (Xcode CLT), jq → ssh key to Forgejo → install the plugin (two commands) → clone the workspace → create `.env` by hand → `/oskr:oskr-setup` → Join. Log every friction point on #35.

## Release

A new capability (Join flow + three verbs), so **minor**: `0.10.0 → 0.11.0` in `.claude-plugin/plugin.json` on the PR.
