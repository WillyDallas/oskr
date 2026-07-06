#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"
source "$REPO_ROOT/bin/harness-lib.sh"
source "$REPO_ROOT/bin/learning-lib.sh"   # units under test

WS=$(cd "$(mktemp -d)" && pwd)
trap 'rm -rf "$WS"' EXIT
mkdir -p "$WS/.oskr"
export OSKR_WORKSPACE="$WS"

TOPIC="Rust Macros"
PAGE=$(learning_resources_page "$TOPIC")

# Seed the resources page THROUGH the seam (v1) — the same way /teach seeds it.
SEED=$'# Rust Macros Resources\n\n## Knowledge\n\n- [Book: The Little Book of Rust Macros](https://example.com/lbrm) <!-- learning:resource id=little-book status=queued -->\n  Covers declarative macros end to end. How to use: read one chapter before each macro_rules! lesson.\n- [Article: Rust Reference — Macros](https://example.com/ref) <!-- learning:resource id=rust-reference status=queued -->\n  Normative grammar. How to use: consult for exact token-tree rules when a lesson hits edge cases.'
hjarne_write_page "$PAGE" "$SEED"

# initial status: queued
assert_eq queued "$(learning_resource_status "$TOPIC" little-book)" "seeded resource starts queued"

# queued -> ingested; sibling resource untouched
learning_resource_mark "$TOPIC" little-book ingested
assert_eq ingested "$(learning_resource_status "$TOPIC" little-book)" "mark flips to ingested"
assert_eq queued "$(learning_resource_status "$TOPIC" rust-reference)" "other resources untouched"

# persisted via hjarne_write_page: line-2 stamp, bumped to v2, today, EXACTLY one stamp,
# title preserved. This is the functional proof the mark did not raw-write the file.
TODAY=$(date +%F)
L2=$(sed -n 2p "$PAGE")
grep -qE '^> Written [0-9]{4}-[0-9]{2}-[0-9]{2} .* v[0-9]+' <<<"$L2" \
  || { echo "FAIL: no version stamp on line 2 ($L2)" >&2; exit 1; }
grep -qF 'v2' <<<"$L2" || { echo "FAIL: mark did not bump to v2 ($L2)" >&2; exit 1; }
grep -qF "$TODAY" <<<"$L2" || { echo "FAIL: stamp date not refreshed ($L2)" >&2; exit 1; }
[[ "$(grep -cE '^> Written ' "$PAGE")" -eq 1 ]] \
  || { echo "FAIL: duplicated stamp lines — mark did not strip the old stamp" >&2; exit 1; }
[[ "$(sed -n 1p "$PAGE")" == '# Rust Macros Resources' ]] \
  || { echo "FAIL: title line clobbered" >&2; exit 1; }

# idempotent re-mark: exit 0, still ingested
learning_resource_mark "$TOPIC" little-book ingested
assert_eq ingested "$(learning_resource_status "$TOPIC" little-book)" "re-mark is idempotent"

# unknown resource -> non-zero from both verbs; invalid status -> non-zero
assert_exit 1 learning_resource_status "$TOPIC" no-such-resource
assert_exit 1 learning_resource_mark "$TOPIC" no-such-resource ingested
assert_exit 1 learning_resource_mark "$TOPIC" little-book done

# malformed ids refused up front (marker contract pins ids to [a-z0-9-])
assert_exit 1 learning_resource_status "$TOPIC" 'Not_A_Slug'
assert_exit 1 learning_resource_mark "$TOPIC" 'Not_A_Slug' ingested

# seam purity (structural): hjarne_write_page is the ONLY mutation path
grep -qF 'hjarne_write_page' "$REPO_ROOT/bin/learning-lib.sh" \
  || { echo "FAIL: learning-lib does not call hjarne_write_page" >&2; exit 1; }
! grep -qF 'sed -i' "$REPO_ROOT/bin/learning-lib.sh" \
  || { echo "FAIL: sed -i found in learning-lib" >&2; exit 1; }
! grep -qE '(printf|echo|cat)[^|]*>>? ' "$REPO_ROOT/bin/learning-lib.sh" \
  || { echo "FAIL: raw file redirection found in learning-lib" >&2; exit 1; }

echo "test_learning_queue: PASS"
