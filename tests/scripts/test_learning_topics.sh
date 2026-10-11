#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"
source "$REPO_ROOT/bin/harness-lib.sh"    # blacksmith_workspace_dir + hjarne_* helpers
source "$REPO_ROOT/bin/learning-lib.sh"   # unit under test

WS=$(cd "$(mktemp -d)" && pwd)
trap 'rm -rf "$WS"' EXIT
mkdir -p "$WS/.oskr"
export OSKR_WORKSPACE="$WS"

# fresh workspace: no brain wiki yet -> empty output, exit 0 (zero topics is legit)
GOT=$(learning_list_topics)
assert_eq "" "$GOT" "no topics in a fresh workspace"

# zsh leg: the brain exists but holds no mission pages, so the glob matches
# nothing. zsh's NOMATCH used to abort the function there; it must stay empty + exit 0.
HAVE_ZSH=0; command -v zsh >/dev/null 2>&1 && HAVE_ZSH=1
mkdir -p "$WS/hjarne/wiki"
if [[ $HAVE_ZSH == 1 ]]; then
  GOT=$(zsh -c "source '$REPO_ROOT/bin/harness-lib.sh'; learning_list_topics") \
    || { echo "FAIL: learning_list_topics failed under zsh with zero topics" >&2; exit 1; }
  assert_eq "" "$GOT" "no topics in an empty brain wiki (zsh)"
fi

# seed two mission pages THROUGH the seam, canonical name in each H1 (the pin)
hjarne_write_page "$(hjarne_route learning-rust-mission)" \
  $'# Mission: Rust\n\n## Why\nShip a CLI to my team.'
hjarne_write_page "$(hjarne_route learning-french-cooking-mission)" \
  $'# Mission: French Cooking\n\n## Why\nHost a dinner party.'

# enumeration: one "<slug>\t<canonical name>" line per topic, sorted for stability
GOT=$(learning_list_topics | sort)
EXPECT=$'french-cooking\tFrench Cooking\nrust\tRust'
assert_eq "$EXPECT" "$GOT" "lists both topics with canonical names from the mission H1"
if [[ $HAVE_ZSH == 1 ]]; then
  GOT=$(zsh -c "source '$REPO_ROOT/bin/harness-lib.sh'; learning_list_topics" | sort)
  assert_eq "$EXPECT" "$GOT" "lists both topics under zsh"
fi

# the name column is the H1 text (capitalized) — proves it is the pinned name, NOT the slug
learning_list_topics | grep -qF $'rust\tRust' \
  || { echo "FAIL: canonical name not read from the mission H1 (got the slug?)" >&2; exit 1; }

echo "test_learning_topics: PASS"
