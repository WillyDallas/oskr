#!/usr/bin/env bash
# Onboarding probes (#103): forge_reachable / deps_unit_ok / board_schema_ok,
# both forges, PATH-boundary shim replay. The reachable and deps probes are hard
# interview gates (loud non-zero); board_schema_ok echoes ok|none|mismatch and
# NEVER gates — adopt reads it as context at the translation question.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FIX="$REPO_ROOT/tests/scripts/fixtures"
LIB="$REPO_ROOT/bin/harness-lib.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"

SHIM_DIR=$(mktemp -d); trap 'rm -rf "$SHIM_DIR"' EXIT
LOG="$SHIM_DIR/calls.log"; : > "$LOG"
cp "$SCRIPT_DIR/lib/gh-shim.sh"   "$SHIM_DIR/gh";   chmod +x "$SHIM_DIR/gh"
cp "$SCRIPT_DIR/lib/curl-shim.sh" "$SHIM_DIR/curl"; chmod +x "$SHIM_DIR/curl"

gh_env() {  # gh_env <extra env...> -- <verb + args>
  local -a env=()
  while [[ "$1" != "--" ]]; do env+=("$1"); shift; done; shift
  env PATH="$SHIM_DIR:$PATH" HARNESS_CONFIG="$FIX/harness-config.sample.json" \
    GH_SHIM_CALL_LOG="$LOG" GH_SHIM_FIXTURE="$FIX/gh-user.json" "${env[@]+"${env[@]}"}" \
    bash -c "source '$LIB'; $*"
}
fj_env() {
  local -a env=()
  while [[ "$1" != "--" ]]; do env+=("$1"); shift; done; shift
  env PATH="$SHIM_DIR:$PATH" HARNESS_CONFIG="$FIX/harness-config.forgejo.json" \
    CURL_SHIM_CALL_LOG="$LOG" FORGEJO_TOKEN="test-token" "${env[@]+"${env[@]}"}" \
    bash -c "source '$LIB'; $*"
}

# --- forge_reachable ---------------------------------------------------------
assert_eq "octo-test" "$(gh_env -- blacksmith_forge_reachable)" \
  "github reachable echoes login" || exit 1
assert_eq "test-user" "$(fj_env -- blacksmith_forge_reachable)" \
  "forgejo reachable echoes login" || exit 1
# Missing token is a loud gate, and the probe never even hits the instance.
if env PATH="$SHIM_DIR:$PATH" HARNESS_CONFIG="$FIX/harness-config.forgejo.json" \
    CURL_SHIM_CALL_LOG="$LOG" FORGEJO_TOKEN="" \
    bash -c "source '$LIB'; blacksmith_forge_reachable" >/dev/null 2>&1; then
  echo "FAIL: forgejo forge_reachable succeeded with empty FORGEJO_TOKEN" >&2; exit 1
fi

# --- deps_unit_ok -------------------------------------------------------------
assert_eq "ok" "$(gh_env -- blacksmith_deps_unit_ok)" \
  "github deps unit is native -> ok" || exit 1
assert_eq "ok" "$(fj_env CURL_SHIM_REPO_FIXTURE="$FIX/forgejo-repo-deps-on.json" -- blacksmith_deps_unit_ok)" \
  "forgejo deps unit enabled -> ok" || exit 1
if fj_env CURL_SHIM_REPO_FIXTURE="$FIX/forgejo-repo-deps-off.json" -- blacksmith_deps_unit_ok >/dev/null 2>&1; then
  echo "FAIL: forgejo deps_unit_ok passed with the unit disabled" >&2; exit 1
fi

# --- board_schema_ok (github) -------------------------------------------------
assert_eq "ok" "$(gh_env GH_SHIM_FIXTURE="$FIX/gh-project-discovery.json" -- blacksmith_board_schema_ok)" \
  "github 8-column board -> ok" || exit 1
out=$(gh_env GH_SHIM_FIXTURE="$FIX/gh-status-3col.json" -- blacksmith_board_schema_ok)
[[ "$out" == mismatch:* ]] || { echo "FAIL: 3-column board -> '$out' (want mismatch:*)" >&2; exit 1; }
grep -qF "Backlog" <<<"$out" || { echo "FAIL: mismatch verdict does not name missing 'Backlog'" >&2; exit 1; }
# project_number 0 = no board yet -> none (the adopt/new pre-provision state).
cfg0=$(mktemp)
env bash -c "source '$REPO_ROOT/bin/init-lib.sh'; init_emit_config github t '' main o r 0" > "$cfg0"
assert_eq "none" "$(env PATH="$SHIM_DIR:$PATH" HARNESS_CONFIG="$cfg0" GH_SHIM_CALL_LOG="$LOG" \
    GH_SHIM_FIXTURE="$FIX/gh-project-discovery.json" bash -c "source '$LIB'; blacksmith_board_schema_ok")" \
  "github project_number 0 -> none" || exit 1
rm -f "$cfg0"

# --- board_schema_ok (forgejo) --------------------------------------------------
assert_eq "ok" "$(fj_env CURL_SHIM_REPO_LABELS_FIXTURE="$FIX/forgejo-labels-8col.json" -- blacksmith_board_schema_ok)" \
  "forgejo full status label set -> ok" || exit 1
out=$(fj_env CURL_SHIM_REPO_LABELS_FIXTURE="$FIX/forgejo-labels-partial.json" -- blacksmith_board_schema_ok)
[[ "$out" == mismatch:* ]] || { echo "FAIL: partial labels -> '$out' (want mismatch:*)" >&2; exit 1; }
grep -qF "status/scoping" <<<"$out" || { echo "FAIL: mismatch verdict does not name status/scoping" >&2; exit 1; }
assert_eq "none" "$(fj_env CURL_SHIM_REPO_LABELS_FIXTURE="$FIX/forgejo-labels-none.json" -- blacksmith_board_schema_ok)" \
  "forgejo no status/* labels -> none" || exit 1

echo "test_blacksmith_onboarding_probes: PASS"
