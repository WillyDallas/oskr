#!/usr/bin/env bash
# init_emit_config (init v2, #27 / #57): emits harness-config.json carrying the
# `forge` discriminator + the matching per-backend block. Round-trips both the
# GitHub and Forgejo shapes against the canonical fixtures, AND back through the
# real config reader. Pure jq; no network, no shims.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FIX="$REPO_ROOT/tests/scripts/fixtures"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"
LIB="$REPO_ROOT/bin/init-lib.sh"
HLIB="$REPO_ROOT/bin/harness-lib.sh"
emit() { bash -c "source '$LIB'; init_emit_config \"\$@\"" _ "$@"; }

TMP=$(mktemp); trap 'rm -f "$TMP"' EXIT

# --- GitHub shape: forge=github, .github block round-trips the sample fixture ---
gh_out=$(emit github oskr-test "bash + gh CLI" main WillyDallas oskr 1)
echo "$gh_out" | jq -e . >/dev/null || { echo "FAIL: github emit is not valid JSON" >&2; exit 1; }
assert_eq "github" "$(jq -r '.forge' <<<"$gh_out")" "github: forge discriminator" || exit 1
assert_eq "$(jq -cS '.github' "$FIX/harness-config.sample.json")" \
          "$(jq -cS '.github' <<<"$gh_out")" "github: backend block matches fixture" || exit 1
assert_eq "false" "$(jq 'has("forgejo")' <<<"$gh_out")" "github: no forgejo block" || exit 1

# --- emitted config carries the live 8-column actionable_columns (T5/#60) ---
assert_eq '["scoping","planning","ready"]' \
          "$(jq -c '.workflow.actionable_columns' <<<"$gh_out")" \
          "emitted config: actionable_columns are the live 8-column slugs" || exit 1
assert_eq "false" \
          "$(jq '[.workflow.actionable_columns[] | . == "needs_input" or . == "approval" or . == "research"] | any' <<<"$gh_out")" \
          "emitted config: no retired slugs in actionable_columns" || exit 1

# --- Forgejo shape: forge=forgejo, .forgejo block round-trips the forgejo fixture ---
fj_out=$(emit forgejo sluice "" main https://git.squirrlylabs.dev squirrlylabs sluice)
echo "$fj_out" | jq -e . >/dev/null || { echo "FAIL: forgejo emit is not valid JSON" >&2; exit 1; }
assert_eq "forgejo" "$(jq -r '.forge' <<<"$fj_out")" "forgejo: forge discriminator" || exit 1
assert_eq "$(jq -cS '.forgejo' "$FIX/harness-config.forgejo.json")" \
          "$(jq -cS '.forgejo' <<<"$fj_out")" "forgejo: backend block matches fixture" || exit 1
assert_eq "false" "$(jq 'has("github")' <<<"$fj_out")" "forgejo: no github block" || exit 1

# --- default forge is github when omitted/empty ---
def_out=$(emit "" def-proj "" main owner repo 3)
assert_eq "github" "$(jq -r '.forge' <<<"$def_out")" "empty forge defaults to github" || exit 1

# --- unknown forge fails loudly (non-zero) ---
if emit frobgit x y main a b c >/dev/null 2>&1; then
  echo "FAIL: unknown forge should be rejected" >&2; exit 1
fi

# --- round-trip through the ACTUAL config reader: emitted file is consumable ---
emit github oskr-test "bash + gh CLI" main WillyDallas oskr 1 > "$TMP"
assert_eq "github" "$(HARNESS_CONFIG="$TMP" bash -c "source '$HLIB'; _blacksmith_forge")" \
          "emitted github config reads back as forge=github" || exit 1
assert_eq "WillyDallas" "$(HARNESS_CONFIG="$TMP" bash -c "source '$HLIB'; blacksmith_config_get '.github.owner'")" \
          "emitted github config: owner reads back" || exit 1

emit forgejo sluice "" main https://git.squirrlylabs.dev squirrlylabs sluice > "$TMP"
assert_eq "forgejo" "$(HARNESS_CONFIG="$TMP" bash -c "source '$HLIB'; _blacksmith_forge")" \
          "emitted forgejo config reads back as forge=forgejo" || exit 1
assert_eq "squirrlylabs" "$(HARNESS_CONFIG="$TMP" bash -c "source '$HLIB'; blacksmith_config_get '.forgejo.owner'")" \
          "emitted forgejo config: owner reads back" || exit 1

echo "test_init_emit_config: PASS"
