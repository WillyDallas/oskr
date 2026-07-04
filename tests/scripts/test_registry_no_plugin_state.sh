#!/usr/bin/env bash
# Stateless-plugin guard: no executable oskr code path WRITES state into the plugin
# source tree. The legacy in-plugin registry path must not appear in skills/ at all,
# and in bin/ only inside registry.sh (the one-time migration SOURCE — it READS the
# legacy file to relocate it, never writes plugin state). init must register through
# bin/registry.sh and declare it in allowed-tools; no stale $REGISTRY may survive.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# (1a) skills/ must NEVER name the legacy in-plugin registry path. init used to WRITE
#      to it inline — that is the plugin-state leak this slice removes.
if grep -rn 'WillyDev/oskr/repos/projects.json' "$REPO_ROOT/skills" 2>/dev/null; then
  echo "FAIL: legacy in-plugin registry path referenced in skills/ (plugin-state write)" >&2
  exit 1
fi

# (1b) bin/ may name the legacy path ONLY in registry.sh (the migration source). Any
#      OTHER bin script naming it is an init-style write back into the plugin tree.
if grep -rn --exclude=registry.sh 'WillyDev/oskr/repos/projects.json' "$REPO_ROOT/bin" 2>/dev/null; then
  echo "FAIL: legacy in-plugin registry path referenced outside bin/registry.sh" >&2
  exit 1
fi

# (2) init registers through the CLI, not an inline jq write into the plugin.
grep -qF 'registry.sh add' "$REPO_ROOT/skills/init/SKILL.md" \
  || { echo "FAIL: init/SKILL.md does not register via bin/registry.sh" >&2; exit 1; }

# (3) init declares the CLI in allowed-tools.
grep -qF 'Bash(registry.sh' "$REPO_ROOT/skills/init/SKILL.md" \
  || { echo "FAIL: init/SKILL.md allowed-tools does not permit Bash(registry.sh*)" >&2; exit 1; }

# (4) the example schema documents the new shape (forge discriminator) and is valid JSON.
jq -e '.projects[0].forge' "$REPO_ROOT/repos/projects.example.json" >/dev/null \
  || { echo "FAIL: projects.example.json missing forge discriminator" >&2; exit 1; }

# (5) no stale $REGISTRY survives (Phase 6 defined it; Phase 11 echoed it).
if grep -qF '$REGISTRY' "$REPO_ROOT/skills/init/SKILL.md"; then
  echo "FAIL: stale \$REGISTRY reference survives in init/SKILL.md (Phase 11 summary?)" >&2
  exit 1
fi

echo "test_registry_no_plugin_state: PASS"
