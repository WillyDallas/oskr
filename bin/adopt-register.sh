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
# The canonical config emitter (init-lib.sh) is the ONE source of truth for the
# harness-config.json shape — register-only reuses it verbatim so an adopted repo
# gets exactly the config a fresh init would write. init-lib.sh is pure (no gh/curl),
# so sourcing it preserves the no-touch guarantee.
# shellcheck disable=SC1091
source "$SCRIPT_DIR/init-lib.sh"

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
# Otherwise delegate to init_emit_config (the canonical emitter) so register-only
# writes the SAME shape as a fresh init — kind, actionable_columns, paths, etc.
# all sourced from T5's one source of truth (no second copy to drift).
if [[ ! -f "$CFG" ]]; then
  if [[ "$FORGE" == "forgejo" ]]; then
    [[ -n "$BASE_URL" ]] || { echo "adopt-register: --base-url required for forgejo" >&2; exit 2; }
    init_emit_config forgejo "$NAME" "" main "$BASE_URL" "$OWNER" "$REPO" > "$CFG" \
      || { echo "adopt-register: config emit failed" >&2; exit 1; }
  else
    init_emit_config github "$NAME" "" main "$OWNER" "$REPO" "${PROJECT_NUMBER:-0}" > "$CFG" \
      || { echo "adopt-register: config emit failed" >&2; exit 1; }
  fi
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
