#!/usr/bin/env bash
# init-lib.sh — init-project helpers: forge inference, config emission and
# backfill, local import. Sourceable; NOT directly executable. Network-free by
# design — forge I/O belongs to the blacksmith (harness-lib.sh); the inference
# and emission helpers are additionally disk-free (subshell-testable), while the
# explicitly disk-touching arm helpers sit below the "execution arms" marker.
# See docs/design/platform-reframe.md and the Area #29 PRD.

_init_die() {
  echo "[init] $1" >&2
  return 1
}

# init_infer_forge <remote_url> — pure mapping of a git remote / clone URL to
# the forge the interview should PRE-FILL. Echoes exactly one of:
#   github               — host is github.com
#   forgejo <base_url>   — any other resolvable host (candidate instance)
#   unknown <input>      — no host could be parsed
#   none                 — empty input (no remote)
# https, ssh:// and scp-style (git@host:o/r.git) forms all parse; the echoed
# base_url is always https://<host>. Infer-and-CONFIRM: a non-github host is
# only a *candidate* Forgejo (a GitLab remote parses identically) — the caller
# must confirm with the developer, never classify from this alone.
init_infer_forge() {
  local url="${1:-}" host=""
  [[ -n "$url" ]] || { echo "none"; return 0; }
  case "$url" in
    ssh://*)            host="${url#ssh://}"; host="${host#*@}"; host="${host%%[:/]*}" ;;
    http://*|https://*) host="${url#*://}";   host="${host#*@}"; host="${host%%[:/]*}" ;;
    *@*:*)              host="${url#*@}";     host="${host%%:*}" ;;
  esac
  [[ -n "$host" ]] || { echo "unknown $url"; return 0; }
  if [[ "$host" == "github.com" ]]; then
    echo "github"
  else
    echo "forgejo https://${host}"
  fi
}

# init_emit_config <forge> <name> <tech_stack> <base_branch> <a> <b> <c>
#   forge=github  : a=owner    b=repo  c=project_number
#   forge=forgejo : a=base_url b=owner c=repo
# Echoes a complete harness-config.json on stdout, carrying the `forge`
# discriminator and EXACTLY the matching per-backend block. Pure jq; no network.
# NOTE: workflow.actionable_columns carries the live 8-column dispatcher set
# (scoping/planning/ready) — the T5/#60 reshape landed here, the one place that
# feeds every freshly-init'd config. workflow.kind is "delivery-8col" (#52; no
# code reads its value — it labels the 8-state delivery pipeline for humans and
# future pluggable shapes, seed issue #10). project_number defaults to 0
# pre-provisioning.
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
            kind: "delivery-8col",
            column_names: {},
            actionable_columns: ["scoping", "planning", "ready"]
          },
          paths: {plans: "docs/plans", research: "docs/research", plan_archive: "docs/_local_archive"},
          agent_context: {project_name: $name, tech_stack: $tech},
          base_branch: $base
        }
    '
}

# init_config_set_project_number <config_file> <number> — backfill the real
# board number after provisioning (closes the project_number:0 hole between
# adopt-detect and re-emit, #103). Atomic: temp + validate + mv, so a failed
# write never leaves a poisoned config.
init_config_set_project_number() {
  local cfg="$1" n="$2" tmp
  [[ -f "$cfg" ]] || { _init_die "set_project_number: no config at $cfg"; return 1; }
  [[ "$n" =~ ^[0-9]+$ ]] || { _init_die "set_project_number: '$n' is not a number"; return 1; }
  tmp="$cfg.tmp.$$"
  jq --argjson n "$n" '.github.project_number = $n' "$cfg" > "$tmp" 2>/dev/null \
    || { rm -f "$tmp"; _init_die "set_project_number: rewrite failed"; return 1; }
  jq . "$tmp" >/dev/null 2>&1 \
    || { rm -f "$tmp"; _init_die "set_project_number: malformed result"; return 1; }
  mv "$tmp" "$cfg"
}

# --- execution arms (disk-touching) -----------------------------------------

# init_import_local <src_dir> <dest_dir> — relocate an existing local repo into
# the workspace. A MOVE, not a copy: .git travels wholesale, so uncommitted
# changes, untracked files, stashes and unpushed branches are preserved by
# construction, and no divergence-prone twin is left behind. Guards: src must
# be a git work tree; dest must not exist (refuse — never merge or overwrite).
# The developer confirmed the move at the interview's confirm-plan gate.
init_import_local() {
  local src="$1" dest="$2" top
  [[ -d "$src" ]] || { _init_die "import: source is not a directory: $src"; return 1; }
  top=$(git -C "$src" rev-parse --show-toplevel 2>/dev/null) \
    || { _init_die "import: source is not a git repository: $src"; return 1; }
  [[ "$top" == "$(cd "$src" && pwd -P)" ]] \
    || { _init_die "import: source is inside a repo rooted at $top — give the repo root, not a subdirectory"; return 1; }
  if [[ -e "$dest" ]]; then
    _init_die "import: destination already exists: $dest (refusing to merge or overwrite)"
    return 1
  fi
  mkdir -p "$(dirname "$dest")" \
    || { _init_die "import: cannot create parent of $dest"; return 1; }
  mv "$src" "$dest" \
    || { _init_die "import: move failed; source left at $src"; return 1; }
}
