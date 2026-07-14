#!/usr/bin/env bash
# init_infer_forge (#103): pure mapping of a remote/clone URL to the interview's
# backend PRE-FILL. github.com -> github; any other parseable host -> candidate
# forgejo + https base_url (infer-and-CONFIRM — a GitLab remote parses the same,
# the developer's confirmation is what classifies); unparseable -> unknown;
# empty -> none. Straight subshell, no shims.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"
LIB="$REPO_ROOT/bin/init-lib.sh"

infer() { bash -c "source '$LIB'; init_infer_forge \"\$@\"" _ "$@"; }

# github.com in every URL form.
assert_eq "github" "$(infer https://github.com/o/r.git)"    "https github"     || exit 1
assert_eq "github" "$(infer git@github.com:o/r.git)"        "scp-style github" || exit 1
assert_eq "github" "$(infer ssh://git@github.com/o/r.git)"  "ssh github"       || exit 1

# Any other host -> candidate forgejo, base_url always https://<host>.
assert_eq "forgejo https://git.squirrlylabs.xyz" "$(infer https://git.squirrlylabs.xyz/sq/sluice.git)" \
  "https forgejo candidate" || exit 1
assert_eq "forgejo https://git.example.org" "$(infer git@git.example.org:o/r.git)" \
  "scp-style forgejo candidate" || exit 1
assert_eq "forgejo https://git.example.org" "$(infer ssh://git@git.example.org:2222/o/r)" \
  "ssh + port forgejo candidate" || exit 1

# No remote / no parseable host.
assert_eq "none" "$(infer)"                          "empty -> none"        || exit 1
assert_eq "unknown ../some/local/path" "$(infer ../some/local/path)" "pathish -> unknown" || exit 1

echo "test_init_infer_forge: PASS"
