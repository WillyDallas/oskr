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

# Echo one line per existing topic — "<slug><TAB><canonical name>" — the name read
# from the topic's mission page H1 (`# Mission: {Topic}`, the pinned canonical name).
# Enumerates the brain wiki (learning-*-mission.md). READ-ONLY: never creates the
# brain, never mutates a page. Empty output + exit 0 when no brain/topics exist yet
# (a fresh workspace legitimately has zero topics). The /teach reconcile step matches
# a normalized argument against this list to continue an existing topic rather than
# fork a duplicate.
learning_list_topics() {
  local brain wiki page slug name
  # zsh aborts on a glob with no matches (NOMATCH) before the [[ -e ]] guard
  # below can run; null_glob, scoped to this function, expands it to nothing.
  if [[ -n "${ZSH_VERSION:-}" ]]; then setopt local_options null_glob; fi
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
# The match is ANCHORED to the full HTML comment (the <!-- … --> wrapper), so a
# bare `learning:resource id=… status=…` token appearing in page prose (e.g. a
# code fence documenting the marker) is never mistaken for a real marker.
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
  line=$(grep -m1 -E "<!-- learning:resource id=${resource} status=(queued|ingested) -->" "$page" || true)
  if [[ -z "$line" ]]; then
    echo "learning: unknown resource '$resource' in topic '$topic' — no marker in $page" >&2
    return 1
  fi
  printf '%s\n' "$line" | sed -nE "s/.*<!-- learning:resource id=${resource} status=(queued|ingested) -->.*/\1/p"
}

# Flip a resource's queue status. Rejects malformed ids up front, reads the page,
# transforms it IN MEMORY (drops the line-2 version stamp — hjarne_write_page
# re-mints it — and rewrites the marker), then persists EXCLUSIVELY via
# hjarne_write_page, inheriting version stamping — no in-place sed, no direct
# file writes, no heredocs: this is the lib's only mutation path. The rewrite is
# ANCHORED to the full <!-- … --> comment, so a bare token quoted in page prose is
# left untouched (no silent corruption). Idempotent for a same-status re-mark
# (still a stamped rewrite).
# learning_resource_mark <topic> <resource> <queued|ingested>
learning_resource_mark() {
  # new_status, not status: zsh's $status is a read-only alias of $? and a
  # `local status=…` aborts the function there.
  local topic="$1" resource="$2" new_status="$3"
  local page content
  _learning_check_id "$resource" || return 1
  case "$new_status" in
    queued|ingested) ;;
    *) echo "learning: invalid status '$new_status' (expected queued|ingested)" >&2; return 1 ;;
  esac
  page=$(learning_resources_page "$topic") || return 1
  if [[ ! -f "$page" ]]; then
    echo "learning: no resources page for topic '$topic' (expected $page) — seed the topic first" >&2
    return 1
  fi
  if ! grep -qE "<!-- learning:resource id=${resource} status=(queued|ingested) -->" "$page"; then
    echo "learning: unknown resource '$resource' in topic '$topic' — no marker in $page" >&2
    return 1
  fi
  content=$(awk -v id="$resource" -v st="$new_status" '
    NR == 2 && /^> Written / { next }
    {
      sub("<!-- learning:resource id=" id " status=(queued|ingested) -->",
          "<!-- learning:resource id=" id " status=" st " -->")
      print
    }
  ' "$page")
  hjarne_write_page "$page" "$content"
}

# Whole days from <from> to <to> (both YYYY-MM-DD), computed at UTC midnight so DST
# never shaves a day. BSD date (macOS) first, GNU date as the fallback. Private.
# _learning_days_between <from> <to>
_learning_days_between() {
  local from="$1" to="$2" a b
  a=$(TZ=UTC date -j -f '%Y-%m-%d %H:%M:%S' "$from 00:00:00" +%s 2>/dev/null) \
    || a=$(TZ=UTC date -d "$from" +%s 2>/dev/null) || return 1
  b=$(TZ=UTC date -j -f '%Y-%m-%d %H:%M:%S' "$to 00:00:00" +%s 2>/dev/null) \
    || b=$(TZ=UTC date -d "$to" +%s 2>/dev/null) || return 1
  echo $(( (b - a) / 86400 ))
}

# Echo one line per topic for the /teach status view:
#   "<slug>\t<name>\t<last>\t<pace>\t<days>\t<state>"
# <last> is the newest version-stamp date (line 2, `> Written YYYY-MM-DD`) across the
# topic's own pages — mission, resources, glossary, records. Every seam write
# (record, glossary, resource mark) refreshes a stamp, so it dates the last session.
# Pages are matched by exact suffix, so a topic whose slug extends another's
# (french vs french-cooking) never lends it a date. <pace> is N from the mission's
# `Pace: N sessions a week` line. <state> is overdue (days since <last> exceed 7/N,
# rounded up), ok, no-pace (no Pace line; <pace> is "-"), or unknown (no stamp).
# LEARNING_TODAY=YYYY-MM-DD overrides today, for tests. READ-ONLY; empty output +
# exit 0 when there are no topics.
# learning_status
learning_status() {
  # state, not status: zsh's $status is read-only (see learning_resource_mark).
  local wiki today slug name page stamp last pace days limit state
  if [[ -n "${ZSH_VERSION:-}" ]]; then setopt local_options null_glob; fi
  wiki="$(hjarne_resolve_brain 2>/dev/null)/wiki" || return 0
  [[ -d "$wiki" ]] || return 0
  today=${LEARNING_TODAY:-$(date +%F)}
  learning_list_topics | while IFS=$'\t' read -r slug name; do
    last=""
    for page in "$wiki/learning-${slug}-mission.md" "$wiki/learning-${slug}-resources.md" \
                "$wiki/learning-${slug}-glossary.md" "$wiki/learning-${slug}-record-"[0-9][0-9][0-9][0-9]-*.md; do
      [[ -e "$page" ]] || continue        # bash 3.2: skip an unexpanded glob
      stamp=$(sed -nE '2s/^> Written ([0-9]{4}-[0-9]{2}-[0-9]{2}) .*/\1/p' "$page")
      if [[ "$stamp" > "$last" ]]; then last="$stamp"; fi
    done
    pace=$(awk '/^[-*[:space:]]*Pace:/ && match($0, /Pace:[[:space:]]*[0-9]+/) {
      s = substr($0, RSTART, RLENGTH); gsub(/[^0-9]/, "", s); print s; exit
    }' "$wiki/learning-${slug}-mission.md")
    [[ "$pace" =~ ^[1-9][0-9]*$ ]] || pace="-"
    days="-"
    [[ -n "$last" ]] && days=$(_learning_days_between "$last" "$today") || days="-"
    if [[ -z "$last" || "$days" == "-" ]]; then
      last="-"; days="-"; state="unknown"
    elif [[ "$pace" == "-" ]]; then
      state="no-pace"
    else
      limit=$(( (7 + pace - 1) / pace ))
      if (( days > limit )); then state="overdue"; else state="ok"; fi
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$slug" "$name" "$last" "$pace" "$days" "$state"
  done
}
