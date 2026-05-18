#!/usr/bin/env bash
assert_eq() {
  local expected="$1" actual="$2" msg="${3:-}"
  if [[ "$expected" != "$actual" ]]; then
    echo "FAIL${msg:+ ($msg)}: expected '$expected', got '$actual'" >&2
    return 1
  fi
}
assert_exit() {
  local expected="$1"; shift
  local actual=0
  "$@" >/dev/null 2>&1 || actual=$?
  if [[ "$expected" != "$actual" ]]; then
    echo "FAIL: expected exit $expected from '$*', got $actual" >&2
    return 1
  fi
}
assert_stdout_contains() {
  local needle="$1"; shift
  local out
  out=$("$@" 2>&1) || true
  if ! grep -qF "$needle" <<<"$out"; then
    echo "FAIL: '$*' stdout did not contain '$needle'" >&2
    echo "--- actual ---" >&2
    echo "$out" >&2
    return 1
  fi
}
