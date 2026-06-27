#!/usr/bin/env bash
# Backend-seam guard: all forge operations must live in harness-lib.sh (the
# blacksmith). No other bin script may make inline `gh` board calls (GitHub) or
# raw `curl` to a forge REST API (Forgejo), and every board-touching script must
# source harness-lib.sh. Also bash -n every bin script.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BIN="$REPO_ROOT/bin"
fail=0

# 1. No inline forge calls outside harness-lib.sh — neither `gh` board ops (GitHub)
#    nor raw `curl` to a forge REST API (Forgejo /api/v1/...).
while IFS= read -r f; do
  [[ "$(basename "$f")" == "harness-lib.sh" ]] && continue
  if grep -nE '\bgh (api|issue|pr|label|project)\b' "$f" >/dev/null 2>&1; then
    echo "FAIL: inline gh board call in $(basename "$f"):" >&2
    grep -nE '\bgh (api|issue|pr|label|project)\b' "$f" >&2
    fail=1
  fi
  if grep -nE '\bcurl\b.*api/v1' "$f" >/dev/null 2>&1; then
    echo "FAIL: inline forge curl call in $(basename "$f"):" >&2
    grep -nE '\bcurl\b.*api/v1' "$f" >&2
    fail=1
  fi
done < <(find "$BIN" -name '*.sh' -type f)

# 2. Board-touching scripts source harness-lib.sh.
for s in find-item.sh move-issue.sh board-dispatcher.sh archive-item.sh dispatch-loop.sh; do
  grep -qF 'harness-lib.sh' "$BIN/$s" \
    || { echo "FAIL: $s does not source harness-lib.sh" >&2; fail=1; }
done

# 3. Every bin script parses.
while IFS= read -r f; do
  bash -n "$f" || { echo "FAIL: bash -n $(basename "$f")" >&2; fail=1; }
done < <(find "$BIN" -name '*.sh' -type f)

[[ "$fail" -eq 0 ]] || exit 1
echo "test_backend_no_inline_gh: PASS"
