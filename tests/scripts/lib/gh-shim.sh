#!/usr/bin/env bash
# Drop-in `gh` replacement for tests. Reads canned responses from
# $GH_SHIM_FIXTURE (a JSON file) and echoes them. Each call is logged
# to $GH_SHIM_CALL_LOG (one line per call, newlines flattened).
#
# Routing: if any arg contains 'updateProjectV2ItemFieldValue', the shim
# returns a success blob for the mutation. Otherwise it cats the fixture.
: "${GH_SHIM_FIXTURE:?GH_SHIM_FIXTURE not set}"
: "${GH_SHIM_CALL_LOG:?GH_SHIM_CALL_LOG not set}"
printf 'gh %s\n' "${*//$'\n'/ }" >> "$GH_SHIM_CALL_LOG"
for a in "$@"; do
  if [[ "$a" == *"updateProjectV2ItemFieldValue"* ]]; then
    echo '{"data":{"updateProjectV2ItemFieldValue":{"projectV2Item":{"id":"PVTI_test"}}}}'
    exit 0
  fi
done
cat "$GH_SHIM_FIXTURE"
