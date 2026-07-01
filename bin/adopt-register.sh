#!/usr/bin/env bash
# Register-only adopt (#27 T6): bring an existing repo under oskr management
# WITHOUT touching its board/columns/issues. Writes harness-config.json
# (no-clobber — preserves a config init's emission already wrote). Makes ZERO
# forge calls — that no-touch guarantee is what lets oskr manage a project that
# keeps its own board/workflow. The heavy harvest->reconcile->re-emit migration
# is the OTHER consent-gate branch (#27 T7), never this path.
#
# Usage:
#   adopt-register.sh --name N --forge github  --owner O --repo R --path DIR [--project-number P]
#   adopt-register.sh --name N --forge forgejo --owner O --repo R --path DIR --base-url URL
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

NAME="" FORGE="github" OWNER="" REPO="" TARGET="" PROJECT_NUMBER="" BASE_URL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)           NAME="$2";           shift 2;;
    --forge)          FORGE="$2";          shift 2;;
    --owner)          OWNER="$2";          shift 2;;
    --repo)           REPO="$2";           shift 2;;
    --path)           TARGET="$2";         shift 2;;
    --project-number) PROJECT_NUMBER="$2"; shift 2;;
    --base-url)       BASE_URL="$2";       shift 2;;
    *) echo "adopt-register: unknown arg: $1" >&2; exit 2;;
  esac
done
[[ -n "$NAME" && -n "$OWNER" && -n "$REPO" && -n "$TARGET" ]] \
  || { echo "adopt-register: --name --owner --repo --path are required" >&2; exit 2; }

CFG="$TARGET/harness-config.json"
# No-clobber: if init's config emission (#27 T4) already wrote it, preserve it.
if [[ ! -f "$CFG" ]]; then
  if [[ "$FORGE" == "forgejo" ]]; then
    [[ -n "$BASE_URL" ]] || { echo "adopt-register: --base-url required for forgejo" >&2; exit 2; }
    forge_block=$(jq -nc --arg u "$BASE_URL" --arg o "$OWNER" --arg r "$REPO" \
      '{forgejo: {base_url:$u, owner:$o, repo:$r}}')
  else
    forge_block=$(jq -nc --arg o "$OWNER" --arg r "$REPO" \
      --argjson pn "${PROJECT_NUMBER:-null}" '{github: {owner:$o, repo:$r, project_number:$pn}}')
  fi
  # 8-column scheme (#27 T5/#52 reshape) — NOT the retired gen-eval-9col block.
  # T5 owns the canonical scheme; this default mirrors the PRD-declared columns and
  # fires ONLY on the fresh-config path (no-clobber means T4/T5 emission wins when present).
  jq -n --arg name "$NAME" --arg forge "$FORGE" --argjson fb "$forge_block" '
    { name: $name, forge: $forge }
    + $fb
    + { workflow: { kind: "gen-eval-8col", column_names: {}, actionable_columns: ["plan_approval","ready","in_review"] } }
  ' > "$CFG"
  jq . "$CFG" >/dev/null || { echo "adopt-register: wrote malformed config" >&2; exit 1; }
fi

# Registry entry — delegated to the canonical registry CLI (#27 T2). No inline
# registry jq here (PRD: registry.sh owns the registry shape). Board untouched.
extra=()
[[ -n "$PROJECT_NUMBER" ]] && extra+=(--project-number "$PROJECT_NUMBER")
[[ -n "$BASE_URL"       ]] && extra+=(--base-url "$BASE_URL")
"$SCRIPT_DIR/registry.sh" add \
  --name "$NAME" --path "$TARGET" --forge "$FORGE" --owner "$OWNER" --repo "$REPO" \
  "${extra[@]+"${extra[@]}"}"

echo "adopt-register: $NAME config written (register-only; board untouched)"
