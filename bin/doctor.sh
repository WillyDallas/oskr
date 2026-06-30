#!/usr/bin/env bash
# doctor.sh — report which oskr copy is active and flag a dev/installed double-enable.
#
# oskr lives at projects/oskr inside the workspace AND is the plugin Claude Code loads.
# A `--plugin-dir` dev checkout and a marketplace-cached copy can BOTH be enabled at once,
# yielding duplicate /oskr:* skills and two oskr bin/ dirs on PATH with ambiguous precedence.
# This verb does PURE env reads — $CLAUDE_PLUGIN_ROOT + $PATH, no forge, no network — and reports:
#   - the active copy: a dev checkout vs the marketplace cache (~/.claude/plugins/cache)
#   - a double-enable collision when >1 oskr bin/ dir is on PATH
#
# Sourceable (pure functions, hermetically testable) + standalone (`main` prints a report
# and exits non-zero on collision). See docs/design/platform-reframe.md
# "Dev-vs-installed plugin toggle".
set -euo pipefail

# The marketplace cache prefix Claude Code copies installed plugins under
# (`~/.claude/plugins/cache` per the plugins-reference). OSKR_DOCTOR_CACHE_ROOT
# overrides it for hermetic tests; CLAUDE_CONFIG_DIR relocates ~/.claude if set.
oskr_doctor_cache_root() {
  printf '%s' "${OSKR_DOCTOR_CACHE_ROOT:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache}"
}

# Classify a plugin-root path. Echo "installed" if it sits under the cache prefix,
# else "dev". Pure over its two args.
# Usage: oskr_doctor_classify <plugin_root> <cache_prefix>
oskr_doctor_classify() {
  local root="$1" cache="$2"
  case "$root" in
    "$cache"/*) printf 'installed' ;;
    *)          printf 'dev' ;;
  esac
}

# Print, one per line, each distinct PATH dir that contains <marker> (an oskr bin/
# signature file, e.g. harness-lib.sh). Pure over its two args.
# Usage: oskr_doctor_oskr_bins <path_value> <marker>
oskr_doctor_oskr_bins() {
  local path_value="$1" marker="$2"
  local seen="" dir
  while IFS= read -r dir; do
    [[ -n "$dir" ]] || continue
    [[ -f "$dir/$marker" ]] || continue
    case ":$seen:" in *":$dir:"*) continue ;; esac
    seen="${seen:+$seen:}$dir"
    printf '%s\n' "$dir"
  done < <(printf '%s' "$path_value" | tr ':' '\n')
}

# Count of distinct oskr bin/ dirs on PATH. >1 ⇒ double-enable collision.
# Usage: oskr_doctor_path_copies <path_value> <marker>
oskr_doctor_path_copies() {
  local n
  n=$(oskr_doctor_oskr_bins "$1" "$2" | grep -c . || true)
  printf '%s' "$n"
}
