#!/usr/bin/env bash
# adopt-register.sh (#27 T6): register-only adopt. Writes config (no-clobber,
# 8-column default) and (added in Task 5) delegates the registry entry to
# registry.sh, making ZERO forge calls. registry.sh (#27 T2) and the forge
# binaries are stubbed; the stubs pre-stage Task 5's delegation + no-touch asserts.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/lib/assert.sh"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bin"; mkdir -p "$BIN"
cp "$REPO_ROOT/bin/adopt-register.sh" "$BIN/adopt-register.sh"
# adopt-register.sh delegates config emission to its sibling init-lib.sh (the
# canonical emitter) — copy it alongside so $SCRIPT_DIR resolution finds it.
cp "$REPO_ROOT/bin/init-lib.sh" "$BIN/init-lib.sh"

# registry.sh stub (#27 T2's CLI) — logs its argv, succeeds. (Used by Task 5.)
REGLOG="$TMP/registry.log"; : > "$REGLOG"
cat > "$BIN/registry.sh" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$REGLOG"
EOF
chmod +x "$BIN/registry.sh"

# Logging gh/curl stubs — ANY invocation is a no-touch violation (asserted in Task 5).
GHLOG="$TMP/gh.log";     : > "$GHLOG"
CURLLOG="$TMP/curl.log"; : > "$CURLLOG"
cat > "$BIN/gh"   <<EOF
#!/usr/bin/env bash
echo "gh \$*" >> "$GHLOG"
EOF
cat > "$BIN/curl" <<EOF
#!/usr/bin/env bash
echo "curl \$*" >> "$CURLLOG"
EOF
chmod +x "$BIN/gh" "$BIN/curl"

# --- Case A: fresh adopt (no config yet) -----------------------------------
TARGET="$TMP/proj"; mkdir -p "$TARGET"
PATH="$BIN:$PATH" "$BIN/adopt-register.sh" \
  --name story-spark --forge github --owner acme --repo story-spark \
  --path "$TARGET" --project-number 7

CFG="$TARGET/harness-config.json"
assert_eq "github"      "$(jq -r '.forge' "$CFG")"          "register-only writes forge"  || exit 1
assert_eq "acme"        "$(jq -r '.github.owner' "$CFG")"   "register-only writes owner"  || exit 1
assert_eq "story-spark" "$(jq -r '.github.repo' "$CFG")"    "register-only writes repo"   || exit 1
assert_eq "7"           "$(jq -r '.github.project_number' "$CFG")" "register-only writes project_number" || exit 1

# Canonical workflow block (delegated to init_emit_config, T5's source of truth):
# kind stays the stable "gen-eval-9col" token while actionable_columns carries the
# live 8-column dispatcher set. Register-only must match a fresh init exactly.
assert_eq "gen-eval-9col" "$(jq -r '.workflow.kind' "$CFG")" "register-only writes canonical workflow kind" || exit 1
jq -e '.workflow.actionable_columns | any(. == "research" or . == "needs_input" or . == "approval")' "$CFG" >/dev/null \
  && { echo "FAIL: retired 9-col slug in actionable_columns" >&2; exit 1; } || true

# --- Case B: no-clobber (config already emitted by T4) ---------------------
SENT="$TMP/proj2"; mkdir -p "$SENT"
printf '%s' '{"name":"pre","forge":"github","github":{"owner":"x","repo":"y"},"_sentinel":true}' > "$SENT/harness-config.json"
BEFORE=$(cat "$SENT/harness-config.json")
PATH="$BIN:$PATH" "$BIN/adopt-register.sh" \
  --name pre --forge github --owner x --repo y --path "$SENT"
assert_eq "$BEFORE" "$(cat "$SENT/harness-config.json")" "no-clobber preserves emitted config" || exit 1

# --- Case A delegation + no-touch (script now calls registry.sh add) --------
# registry delegated to registry.sh add with the EXACT outgoing argv this script
# emits (pins the contract #27 T2 must satisfy; see plan cross-task note).
grep -qF 'add'              "$REGLOG" || { echo "FAIL: registry.sh 'add' not invoked" >&2; exit 1; }
grep -qF -- '--name story-spark' "$REGLOG" || { echo "FAIL: registry missing --name" >&2; exit 1; }
grep -qF -- '--forge github'     "$REGLOG" || { echo "FAIL: registry missing --forge" >&2; exit 1; }
grep -qF -- '--owner acme'       "$REGLOG" || { echo "FAIL: registry missing --owner" >&2; exit 1; }
grep -qF -- '--repo story-spark' "$REGLOG" || { echo "FAIL: registry missing --repo" >&2; exit 1; }
grep -qF -- '--path'             "$REGLOG" || { echo "FAIL: registry missing --path" >&2; exit 1; }

# NO-TOUCH: zero forge calls across every case above.
[[ ! -s "$GHLOG"   ]] || { echo "FAIL: register-only invoked gh (board touched)" >&2;   cat "$GHLOG"   >&2; exit 1; }
[[ ! -s "$CURLLOG" ]] || { echo "FAIL: register-only invoked curl (board touched)" >&2; cat "$CURLLOG" >&2; exit 1; }

# --- Case C: forgejo coords ------------------------------------------------
FJ="$TMP/proj3"; mkdir -p "$FJ"
PATH="$BIN:$PATH" "$BIN/adopt-register.sh" \
  --name sluice --forge forgejo --owner squirrlylabs --repo sluice \
  --path "$FJ" --base-url https://git.squirrlylabs.dev
assert_eq "forgejo"                       "$(jq -r '.forge' "$FJ/harness-config.json")"            "forgejo forge"   || exit 1
assert_eq "https://git.squirrlylabs.dev"  "$(jq -r '.forgejo.base_url' "$FJ/harness-config.json")" "forgejo base_url" || exit 1
assert_eq "gen-eval-9col"                 "$(jq -r '.workflow.kind' "$FJ/harness-config.json")"    "forgejo canonical kind" || exit 1

echo "test_adopt_register: PASS"
