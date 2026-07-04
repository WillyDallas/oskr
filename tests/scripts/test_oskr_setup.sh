#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"
SETUP="$REPO_ROOT/bin/oskr-setup.sh"

TMPROOT=$(mktemp -d); trap 'rm -rf "$TMPROOT"' EXIT

# ---- skeleton: dirs + empty registry, asserted against a clean fixture dir ----
WS="$TMPROOT/ws-skel"
"$SETUP" skeleton "$WS"
for d in .oskr projects hjarne learning; do
  test -d "$WS/$d" || { echo "FAIL: skeleton missing dir $d" >&2; exit 1; }
done
test -f "$WS/.oskr/registry.json" || { echo "FAIL: registry.json missing" >&2; exit 1; }
assert_eq "[]" "$(jq -c '.projects' "$WS/.oskr/registry.json")" "registry empty" || exit 1

# idempotent: a second skeleton run must not error or clobber an empty registry
"$SETUP" skeleton "$WS"
assert_eq "[]" "$(jq -c '.projects' "$WS/.oskr/registry.json")" "registry survives re-skeleton" || exit 1

# ---- write-config: populate config.json from env (non-secret) ----
WS2="$TMPROOT/ws-cfg"
"$SETUP" skeleton "$WS2"
OSKR_FORGE=forgejo OSKR_BASE_BRANCH=develop OSKR_FORGEJO_BASE_URL=https://sluice.example \
  "$SETUP" write-config "$WS2"
CFG="$WS2/.oskr/config.json"
jq . "$CFG" >/dev/null || { echo "FAIL: config.json malformed" >&2; exit 1; }
assert_eq "forgejo" "$(jq -r .forge "$CFG")"              "forge"        || exit 1
assert_eq "develop" "$(jq -r .base_branch "$CFG")"        "base_branch"  || exit 1
assert_eq "https://sluice.example" "$(jq -r .forgejo.base_url "$CFG")" "base_url" || exit 1
# secret-hygiene: no token/password keys anywhere in the emitted config
if jq -e '.. | objects | (has("token") or has("password"))' "$CFG" >/dev/null 2>&1; then
  echo "FAIL: secret key written into config.json" >&2; exit 1
fi

# default forge=github when OSKR_FORGE unset
WS3="$TMPROOT/ws-default"
"$SETUP" skeleton "$WS3"; "$SETUP" write-config "$WS3"
assert_eq "github" "$(jq -r .forge "$WS3/.oskr/config.json")" "default forge" || exit 1

# ---- no-clobber guard: re-config refuses + leaves bytes untouched ----
BEFORE=$(cat "$WS3/.oskr/config.json")
if OSKR_FORGE=forgejo "$SETUP" write-config "$WS3" 2>/dev/null; then
  echo "FAIL: re-config did not refuse" >&2; exit 1
fi
assert_eq "$BEFORE" "$(cat "$WS3/.oskr/config.json")" "config not clobbered" || exit 1

# ---- write-config without skeleton errors clearly ----
GUARD_OUT=$("$SETUP" write-config "$TMPROOT/ws-none" 2>&1 || true)
grep -qF "run 'skeleton' first" <<<"$GUARD_OUT" || { echo "FAIL: missing skeleton-first guard" >&2; exit 1; }

# ---- bootstrap: one command yields dirs + registry + config (AC a) ----
WS4="$TMPROOT/ws-boot"
OSKR_FORGE=github OSKR_GITHUB_OWNER=WillyDallas OSKR_BASE_BRANCH=main \
  "$SETUP" bootstrap "$WS4"
for d in .oskr projects hjarne learning; do
  test -d "$WS4/$d" || { echo "FAIL: bootstrap missing dir $d" >&2; exit 1; }
done
assert_eq "[]"         "$(jq -c '.projects' "$WS4/.oskr/registry.json")" "bootstrap registry" || exit 1
assert_eq "WillyDallas" "$(jq -r .github.owner "$WS4/.oskr/config.json")" "bootstrap owner"    || exit 1
assert_eq "github"     "$(jq -r .forge "$WS4/.oskr/config.json")"        "bootstrap forge"     || exit 1

# re-bootstrap on a configured workspace refuses (guard inherited from write-config)
if "$SETUP" bootstrap "$WS4" 2>/dev/null; then echo "FAIL: re-bootstrap did not refuse" >&2; exit 1; fi

echo "test_oskr_setup skeleton: PASS"
