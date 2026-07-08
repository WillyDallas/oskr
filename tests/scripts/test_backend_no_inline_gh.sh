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
  # File-level (not per-line): a multiline curl invocation — the natural form,
  # where the URL is on a continuation line — would evade a single-line regex.
  if grep -qE '\bcurl\b' "$f" && grep -qF 'api/v1' "$f"; then
    echo "FAIL: forge curl call in $(basename "$f") (bare curl + api/v1 both present)" >&2
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

# 4. Delivery-path skills perform issue/PR operations only through blacksmith
#    verbs (#101). Scans the 9 delivery SKILL.md files for raw `gh issue` /
#    `gh pr` — code AND prose (a documented raw call regresses the same way).
#    Allowlist: EMPTY — every gh issue/pr operation in these skills has a verb
#    (issue_view/close/remove_label + pr_create/list_merged/open_exists new in
#    #101; issue_comment/issue_add_label pre-existing). `gh api` is deliberately
#    NOT scanned: planning-session's parent lookup has no verb yet (follow-up).
#    init/oskr-setup are the provisioning path (#26/#27) and are NOT scanned.
DELIVERY_SKILLS="scope research decompose planning-session plan-approval execute-plan land-area clean-up hjarne"
for s in $DELIVERY_SKILLS; do
  f="$REPO_ROOT/skills/$s/SKILL.md"
  [[ -f "$f" ]] || { echo "FAIL: missing delivery skill skills/$s/SKILL.md" >&2; fail=1; continue; }
  if grep -nE '\bgh (issue|pr)\b' "$f" >/dev/null 2>&1; then
    echo "FAIL: raw gh issue/pr call in skills/$s/SKILL.md — use a blacksmith verb:" >&2
    grep -nE '\bgh (issue|pr)\b' "$f" >&2
    fail=1
  fi
done

[[ "$fail" -eq 0 ]] || exit 1
echo "test_backend_no_inline_gh: PASS"
