# Orca terminal multiplexing — research notes

**Date:** 2026-06-10
**Status:** Reference (no issue yet — created ahead of a planned fix issue)
**Question:** How does Orca do terminal multiplexing? What can we change, how can output be routed between panes, and what is the base library?

## TL;DR

Orca's multiplexing is **not tmux**. It is an Electron app with its own pane-tree
implementation built on the VS Code terminal stack: **xterm.js** for rendering,
**node-pty** for shell processes, and a **headless xterm + serialize addon**
server-side, which is what powers the CLI's clean cursor-paginated `read`.
There is **no native pipe between panes** — routing is done with a
read-then-send loop via the CLI, or ordinary shell plumbing (FIFOs).

## Base library

Confirmed from the open-source repo ([stablyai/orca](https://github.com/stablyai/orca), `package.json`):

| Package | Role |
|---|---|
| `@xterm/xterm` 6.1.0-beta | rendering (plus webgl, fit, search, unicode11, web-links, ligatures addons) |
| `node-pty` ^1.1.0 | spawns the actual shell processes |
| `@xterm/headless` + `@xterm/addon-serialize` | server-side screen state; backs `orca terminal read` |

The [terminal docs](https://www.onorca.dev/docs/terminal) confirm: "the same
xterm.js-based terminal VS Code uses, with a few additions tuned for AI-agent
workflows."

Key mechanism: instead of streaming raw PTY bytes (full of ANSI escapes), Orca
replays the PTY into an invisible headless xterm instance and serializes the
*rendered screen*. That's why the CLI can hand an agent clean, paginated text
from a TUI (vim, Claude Code) — something tmux `capture-pane` does crudely and
raw PTY logs can't do at all.

## What can be changed

**Via the CLI** (`orca terminal ...`):

- `create --worktree <w> --title <t> --command <cmd>`
- `split --terminal <handle> --direction horizontal|vertical --command <cmd>`
- `rename --title`, `switch`, `close`
- `read --cursor <c> --limit <n>` — save `nextCursor` from each read to fetch only new output
- `send --text "..." --enter`
- `wait --for tui-idle --timeout-ms <n>` — coordination primitive
- Omit `--terminal` to target the active terminal in the current worktree

**Via UI/settings:**

- Color themes (Settings → Terminal), one-time Ghostty theme/font/cursor import
- Shell choice on Windows (PowerShell/CMD/WSL); tab-bar dropdown for one-off shells
- Floating-terminal working directory (defaults to home)
- Splits: `Cmd-\` (right), `Cmd-Shift-\` (down); splits nest recursively
- Layouts persist per worktree — switching worktrees swaps the whole pane tree
- Find-in-scrollback (`Cmd-F`, regex + case-sensitivity), kitty keyboard protocol

## Routing output between panes

No native pipe exists (checked CLI reference, terminal docs, and panes docs).
Two workable patterns:

1. **Read-then-send loop** (Orca-native, designed for agents driving terminals):

   ```bash
   orca terminal read --terminal A --cursor "$CURSOR" --json   # grab new output
   orca terminal send --terminal B --text "..." --enter --json # inject it
   ```

   Save `nextCursor` from each read so only new output is forwarded.
   Use `orca terminal wait --for tui-idle` to coordinate timing.

2. **Shell-level plumbing** — panes are ordinary shells, so a named pipe works
   with Orca uninvolved:

   ```bash
   mkfifo /tmp/p && cmd > /tmp/p     # pane A
   cat /tmp/p                        # pane B
   ```

## Sources

- [Orca CLI reference](https://www.onorca.dev/docs/cli/reference)
- [Terminal docs](https://www.onorca.dev/docs/terminal)
- [Tabs, panes & splits](https://www.onorca.dev/docs/model/tabs-panes-splits)
- [stablyai/orca on GitHub](https://github.com/stablyai/orca) (package.json dependency audit)
