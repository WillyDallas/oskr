#!/usr/bin/env bash
# harness-lib.sh workspace .env auto-load (#102). Sourcing the lib inside a
# workspace loads <ws>/.env into the environment (set + export), but only for
# keys currently UNSET — a pre-existing process value always wins. Values are
# assigned literally and never echoed. Quiet no-op outside a workspace; safe
# under set -euo pipefail; idempotent on double-source. OSKR_WORKSPACE pins the
# workspace so the fixtures never touch the real $HOME.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"
export LIB="$REPO_ROOT/bin/harness-lib.sh"

# Fixtures: WS (.env with a secret), WS2 (.env whose value must LOSE to process
# env), OUTSIDE (no .oskr ancestor). cd+pwd canonicalizes past /tmp symlinks.
WS=$(cd "$(mktemp -d)" && pwd)
WS2=$(cd "$(mktemp -d)" && pwd)
OUTSIDE=$(cd "$(mktemp -d)" && pwd)
trap 'rm -rf "$WS" "$WS2" "$OUTSIDE"' EXIT
mkdir -p "$WS/.oskr" "$WS2/.oskr"
printf 'OSKR_TEST_TOKEN=s3cr3t\n' > "$WS/.env"
printf 'OSKR_TEST_TOKEN=fromfile\n' > "$WS2/.env"

# Case 1: export reaches a NON-sourcing grandchild (proves export, not a shell var).
out=$(OSKR_WORKSPACE="$WS" bash -c 'source "$LIB"; exec bash -c '\''printf %s "${OSKR_TEST_TOKEN:-UNSET}"'\''')
assert_eq 's3cr3t' "$out" "export reaches a non-sourcing grandchild" || exit 1

# Case 2: verb-observed pinned probe in the sourcing shell.
out=$(OSKR_WORKSPACE="$WS" bash -c 'source "$LIB"; printf %s "${OSKR_TEST_TOKEN:-UNSET}"')
assert_eq 's3cr3t' "$out" "source-time load sets the var in the sourcing shell" || exit 1

# Case 3: pre-existing process env wins over .env.
out=$(OSKR_TEST_TOKEN=fromenv OSKR_WORKSPACE="$WS2" \
      bash -c 'source "$LIB"; printf %s "${OSKR_TEST_TOKEN:-UNSET}"')
assert_eq 'fromenv' "$out" "pre-existing process env wins over .env" || exit 1

# Case 4: the secret is never echoed to stdout or stderr at source time.
combined=$(OSKR_WORKSPACE="$WS" bash -c 'source "$LIB"' 2>&1 || true)
if grep -qF 's3cr3t' <<<"$combined"; then
  echo "FAIL: .env value leaked to source-time output" >&2; exit 1
fi

# Case 5: no workspace -> exit 0 and EMPTY stderr (quiet fallback probe).
set +e
err=$(cd "$OUTSIDE" && OSKR_WORKSPACE="" bash -c 'source "$LIB"' 2>&1 1>/dev/null)
rc=$?
set -e
assert_eq '0' "$rc" "no-workspace source exits 0" || exit 1
assert_eq ''  "$err" "no-workspace source emits no stderr" || exit 1

# Case 6: set -euo pipefail + idempotent double-source -> exit 0, value intact.
set +e
out=$(OSKR_WORKSPACE="$WS" bash -c \
  'set -euo pipefail; source "$LIB"; source "$LIB"; printf %s "${OSKR_TEST_TOKEN:-UNSET}"')
rc=$?
set -e
assert_eq '0' "$rc" "double-source under set -euo pipefail exits 0" || exit 1
assert_eq 's3cr3t' "$out" "value correct after idempotent double-source" || exit 1

echo "test_workspace_env: PASS"
