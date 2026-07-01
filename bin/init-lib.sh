#!/usr/bin/env bash
# init-lib.sh — init v2 helpers: mode detection + config emission.
# Sourceable; NOT directly executable. Pure (network-free, disk-free) by design —
# the one forge-coupled detection input (does the repo exist on the forge?) is
# supplied by the caller via blacksmith_remote_exists (harness-lib.sh), keeping
# these functions subshell-testable. See docs/design/platform-reframe.md and the
# Area #27 PRD.

_init_die() {
  echo "[init] $1" >&2
  return 1
}

# init_detect_mode <is_git> <has_origin> <remote_exists> <config_present>
# Each arg is "yes" or "no" (anything not "yes" is treated as "no"). Echoes
# exactly one of:
#   already-init  — harness-config.json present; the caller refuses re-init
#   adopt         — local git repo already wired to an origin remote
#   clone         — repo exists on the forge but not here
#   create-new    — nothing exists locally or on the forge
# Precedence: config > origin > forge-remote > nothing. Pure; no network, no disk.
init_detect_mode() {
  local is_git="${1:-no}" has_origin="${2:-no}" remote_exists="${3:-no}" config_present="${4:-no}"
  if [[ "$config_present" == "yes" ]]; then echo "already-init"; return 0; fi
  if [[ "$is_git" == "yes" && "$has_origin" == "yes" ]]; then echo "adopt"; return 0; fi
  if [[ "$remote_exists" == "yes" ]]; then echo "clone"; return 0; fi
  echo "create-new"
}

# init_emit_config <forge> <name> <tech_stack> <base_branch> <a> <b> <c>
#   forge=github  : a=owner    b=repo  c=project_number
#   forge=forgejo : a=base_url b=owner c=repo
# Echoes a complete harness-config.json on stdout, carrying the `forge`
# discriminator and EXACTLY the matching per-backend block. Pure jq; no network.
# NOTE: workflow.actionable_columns carries the live 8-column dispatcher set
# (scoping/planning/ready) — the T5/#60 reshape landed here, the one place that
# feeds every freshly-init'd config. workflow.kind stays "gen-eval-9col" (no code
# reads its value; renaming it is deferred per #60's deliberate non-change).
# project_number defaults to 0 pre-provisioning.
init_emit_config() {
  local forge="${1:-github}" name="$2" tech="${3:-}" base="${4:-main}"
  local a="${5:-}" b="${6:-}" c="${7:-}" backend
  [[ -n "$forge" ]] || forge=github
  case "$forge" in
    github)
      backend=$(jq -nc --arg o "$a" --arg r "$b" --argjson pn "${c:-0}" \
        '{github: {owner: $o, repo: $r, project_number: $pn}}') || return 1 ;;
    forgejo)
      backend=$(jq -nc --arg u "$a" --arg o "$b" --arg r "$c" \
        '{forgejo: {base_url: $u, owner: $o, repo: $r}}') || return 1 ;;
    *)
      _init_die "unknown forge '$forge' (expected github|forgejo)"; return 1 ;;
  esac
  jq -n \
    --arg forge "$forge" --arg name "$name" --arg tech "$tech" --arg base "$base" \
    --argjson backend "$backend" '
      {name: $name, forge: $forge}
      + $backend
      + {
          workflow: {
            kind: "gen-eval-9col",
            column_names: {},
            actionable_columns: ["scoping", "planning", "ready"]
          },
          paths: {plans: "docs/plans", research: "docs/research", plan_archive: "docs/_local_archive"},
          agent_context: {project_name: $name, tech_stack: $tech},
          base_branch: $base
        }
    '
}
