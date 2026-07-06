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
