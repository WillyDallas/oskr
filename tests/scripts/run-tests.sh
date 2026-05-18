#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PASS=0; FAIL=0; TOTAL=0
shopt -s nullglob
for test_file in "$SCRIPT_DIR"/test_*.sh; do
  TOTAL=$((TOTAL + 1))
  echo "==> $(basename "$test_file")"
  if bash "$test_file"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
  fi
done
echo "Results: $PASS/$TOTAL passed, $FAIL failed ($TOTAL tests)"
[[ "$FAIL" -eq 0 ]]
