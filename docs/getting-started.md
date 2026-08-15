# Getting started — zero to an oskr-managed project

**Date:** 2026-08-15

Three steps: install the plugin, create the workspace (`/oskr:oskr-setup`), onboard a
project (`/oskr:init-project`). Written from the real squirrlylabs run — the notes
inline below are the things that actually bit, placed where you would hit them.

The **workspace** is the control plane: one directory holding global config
(`.oskr/`), the project registry, the brain (`hjarne/`), the learning domain
(`learning/`), and every managed project under `projects/`. You create it once.
You onboard projects into it many times.

## 1. Install the plugin

```
/plugin marketplace add WillyDallas/oskr
/plugin install oskr@oskr-marketplace
/reload-plugins
```

> **How changes reach you.** The marketplace is a git clone of the GitHub repo;
> the *installed* plugin is a version-keyed snapshot at
> `~/.claude/plugins/cache/oskr-marketplace/oskr/<version>/`. Nothing is ever
> copied into your workspace — the workspace holds state, the cache holds code.
> A merged change reaches a session only after the whole chain:
> `/plugin marketplace update oskr-marketplace` → `/plugin update
> oskr@oskr-marketplace` → `/reload-plugins`. And the update only materializes a
> *new* snapshot directory when `version` in `.claude-plugin/plugin.json` moved;
> merge without a bump and you stay on the old directory, running old code with
> a current git log. This is why every Area→main PR bumps the manifest.

To develop against a checkout instead of the cache, launch with
`claude --plugin-dir <path-to-repo>`.

## 2. Create the workspace — `/oskr:oskr-setup`

Run it from inside the directory that should become the workspace:

```bash
mkdir -p ~/WillyDev/squirrlylabs && cd ~/WillyDev/squirrlylabs
```

Then `/oskr:oskr-setup`. It interviews you for the backend (`github` or
`forgejo`), the default base branch, and the GitHub owner or Forgejo base URL —
everything else is inferred. It then writes the skeleton (`.oskr/config.json`,
an empty `.oskr/registry.json`, `projects/`, `learning/`, a stamped `hjarne/`,
and a workspace-root `CLAUDE.md`), puts the workspace under git with a
`.gitignore` contract that keeps secrets and cloned projects out, and finally
asks — never assumes — whether to publish it.

> **Secrets live in the workspace `.env`, never in the plugin.** Setup does not
> write credentials into `.oskr/config.json`; it instructs and verifies. For
> Forgejo, put `FORGEJO_TOKEN=<pat>` in `<workspace>/.env`. `harness-lib.sh`
> auto-loads that file at **source time** by walking up from `$PWD`, so the rule
> for every shell block you write by hand is **`cd` into the project first, then
> source** — sourcing from elsewhere silently skips the token, once per shell.
> The plugin cache stays stateless; a fresh install inherits nothing.

> **Pushing to a self-hosted forge over SSH.** `git-init` composes an https
> origin from the configured forge (`<base_url>/<owner>/workspace.git`). If your
> Forgejo takes SSH on a non-standard port, https will not do — set the full URL
> before setup publishes:
> `export OSKR_WORKSPACE_REMOTE=ssh://git@<host>:<port>/<owner>/workspace.git`.
> `OSKR_WORKSPACE_SLUG` overrides just the `owner/repo` half of the composed
> form; `OSKR_WORKSPACE_REMOTE` wins over both.

You end up with:

```
squirrlylabs/
├── .env                 # FORGEJO_TOKEN — gitignored, never leaves this machine
├── .oskr/
│   ├── config.json      # forge, base branch, owner / base URL
│   └── registry.json    # every managed project — the rehydration artifact
├── CLAUDE.md            # ambient context for free-form sessions (below)
├── hjarne/              # the brain
├── learning/
└── projects/            # gitignored; rebuilt by `rehydrate`, not vendored
```

## 3. Onboard project #1 — `/oskr:init-project`

Run it from anywhere inside the workspace. One interview gathers every input
(location → backend → secrets → shape → adopt choice) and writes nothing; then a
single confirmation gate releases execution. Three arms: **new** repo, **import**
an existing local folder (a move), or **clone** from the forge.

Execution creates the repo if needed, provisions the eight-column board, writes
`harness-config.json`, registers the project in `.oskr/registry.json`, and runs a
four-verb smoke test against the fresh board. It closes by checking the registry
entry into the workspace repo — an unregistered project is one a new machine
cannot reconstruct.

> **A Forgejo 404 is usually an auth failure, not a missing issue.** Forgejo
> answers unauthenticated reads of a *private* repo with 404 and the message
> "The target couldn't be found". It looks exactly like a typo'd issue number.
> If something you know exists 404s, check the token before you check the number:
> is `FORGEJO_TOKEN` in the workspace `.env`, and did you `cd` into the project
> before sourcing `harness-lib.sh`?

> **Forgejo needs issue dependencies enabled** on the repo (Settings → Units)
> before onboarding an existing repo — the harness uses them for blocker
> tracking, and `init-project` gates on it.

From here, work flows across eight board states with one skill at each — see
[board-flow.md](board-flow.md).

## The workspace `CLAUDE.md`

Setup stamps a `CLAUDE.md` at the workspace root, and it is load-bearing. Skills
carry their own plugin-rooted paths, so any session that *invokes a skill* is
fine. Free-form sessions are not: asked to "pull up issue #21", a session with no
ambient context improvises raw `curl` against the forge, sources `.env` from the
wrong directory, hits the 404-that-means-auth, and then trips the permission
classifier while hunting parent directories for env files.

The provisioned file heads that off with four things: resolve the newest plugin
bin (`ls -d ~/.claude/plugins/cache/oskr-marketplace/oskr/*/bin | sort -V | tail -1`,
because the cache path is version-keyed), `cd` before sourcing, the
404-means-auth note, and a pointer to the skills for full workflows.

It is yours to extend — add workspace-specific conventions freely. Setup never
overwrites it on a re-run.

## Reconstructing on a new machine

The workspace repo tracks the control plane; `projects/` is gitignored. So:

```bash
git clone <workspace remote> squirrlylabs && cd squirrlylabs
OSKR_BIN=$(ls -d ~/.claude/plugins/cache/oskr-marketplace/oskr/*/bin | sort -V | tail -1)
"$OSKR_BIN/oskr-setup.sh" rehydrate .          # --dry-run to preview
```

`rehydrate` re-clones every registry entry from **that entry's own** coordinates,
so projects on different forges coexist in one workspace. Then restore `.env` by
hand — secrets were never in the repo.
