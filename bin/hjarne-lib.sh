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

# Echo the wiki page path for a system slug: <brain>/wiki/<system-slug>.md.
# hjarne_route <system-slug>
hjarne_route() {
  local system="$1" brain
  brain=$(hjarne_resolve_brain) || return 1
  echo "$brain/wiki/${system}.md"
}

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
