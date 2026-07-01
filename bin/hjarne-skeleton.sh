#!/usr/bin/env bash
# Stamp the hjarne brain skeleton into a target directory.
# Usage: ./bin/hjarne-skeleton.sh <target-dir>
#
# Materializes templates/hjarne/ into <target-dir> (created if absent). Pure
# filesystem: touches no forge (no gh, no curl). Idempotent and non-clobbering
# — existing files are left untouched; only missing dirs/files are created.
# .gitkeep placeholders keep empty template dirs in git and are NOT copied; the
# directory they guard is created instead.
#
# Exits 0 on success, 2 on usage error.

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <target-dir>" >&2
  exit 2
fi

TARGET="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE_DIR="$(cd "$SCRIPT_DIR/../templates/hjarne" && pwd)"

# Walk the template tree and recreate its structure under TARGET.
while IFS= read -r src; do
  rel="${src#"$TEMPLATE_DIR"/}"
  if [[ "$(basename "$rel")" == ".gitkeep" ]]; then
    # Keep the dir; drop the git-only marker.
    mkdir -p "$TARGET/$(dirname "$rel")"
    continue
  fi
  dest="$TARGET/$rel"
  mkdir -p "$(dirname "$dest")"
  # Non-clobbering: only write a file that is not already there.
  if [[ ! -e "$dest" ]]; then
    cp "$src" "$dest"
  fi
done < <(find "$TEMPLATE_DIR" -type f)

echo "hjarne-skeleton: stamped templates/hjarne -> $TARGET"
