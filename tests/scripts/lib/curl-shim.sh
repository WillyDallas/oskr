#!/usr/bin/env bash
# Drop-in `curl` replacement for tests of the Forgejo backend. Routes by URL
# content to a canned JSON fixture and logs each call to $CURL_SHIM_CALL_LOG.
# Auth header and flags (-fsS etc.) are accepted and ignored; the shim only
# inspects the URL. Mirrors lib/gh-shim.sh for the gitea-family REST transport.
#
# Fixture routing (first match wins):
#   .../dependencies   + $CURL_SHIM_DEPS_FIXTURE   -> that fixture
: "${CURL_SHIM_CALL_LOG:?CURL_SHIM_CALL_LOG not set}"
printf 'curl %s\n' "$*" >> "$CURL_SHIM_CALL_LOG"

args="$*"
if [[ "$args" == *"/dependencies"* && -n "${CURL_SHIM_DEPS_FIXTURE:-}" ]]; then
  cat "$CURL_SHIM_DEPS_FIXTURE"; exit 0
fi
echo "curl-shim: no route for: $args" >&2
exit 22
