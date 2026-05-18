#!/usr/bin/env bash
# Drop-in `gh` replacement for tests. Reads canned responses from
# $GH_SHIM_FIXTURE (a JSON file) and echoes them. Each call increments
# a counter for cache-hit assertions.
: "${GH_SHIM_FIXTURE:?GH_SHIM_FIXTURE not set}"
: "${GH_SHIM_CALL_LOG:?GH_SHIM_CALL_LOG not set}"
printf 'gh %s\n' "${*//$'\n'/ }" >> "$GH_SHIM_CALL_LOG"
cat "$GH_SHIM_FIXTURE"
