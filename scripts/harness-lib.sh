#!/usr/bin/env bash
# harness-lib.sh — shared helpers for the oskr dispatcher scripts.
# Sourceable; not directly executable.
#
# Public functions (this section):
#   harness_config_path                  — absolute path to harness-config.json
#   harness_config_get <jq_path>         — scalar getter
#   harness_config_get_array <jq_path>   — array getter (one element per line)

# Each function uses `command jq` to avoid recursion into the test gh-shim.
# All functions either echo on stdout and return 0, or die with a message
# on stderr and return non-zero.

_harness_die() {
  echo "[harness] $1" >&2
  return 1
}

harness_config_path() {
  if [[ -n "${HARNESS_CONFIG:-}" ]]; then
    [[ -f "$HARNESS_CONFIG" ]] || { _harness_die "HARNESS_CONFIG set but file missing: $HARNESS_CONFIG"; return 1; }
    echo "$HARNESS_CONFIG"
    return 0
  fi
  if [[ -f "$PWD/harness-config.json" ]]; then
    echo "$PWD/harness-config.json"; return 0
  fi
  if [[ -f "$PWD/.claude/harness-config.json" ]]; then
    echo "$PWD/.claude/harness-config.json"; return 0
  fi
  _harness_die "not in an oskr project; expected harness-config.json at \$PWD or \$PWD/.claude/"
  return 1
}

harness_config_get() {
  local path="$1" cfg
  cfg=$(harness_config_path) || return 1
  jq -er "$path" "$cfg"
}

harness_config_get_array() {
  local path="$1" cfg
  cfg=$(harness_config_path) || return 1
  jq -er "${path}[]" "$cfg"
}
