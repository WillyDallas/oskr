# `harness-config.json` schema (v1)

Each project consumed by Oskr has a `harness-config.json` at its root
(or under `.claude/`, per the install layout). The harness reads this
file to discover the GitHub board, paths, and per-project context.

```jsonc
{
  "name": "wonderloom",
  "github": {
    "owner": "Wonderloom-books",
    "repo": "wonderloom",
    "project_number": 5
  },
  "workflow": {
    "kind": "gen-eval-9col",
    "column_names": {
    },
    "actionable_columns": [
      "needs_input",
      "approval",
      "ready",
      "in_review"
    ]
  },
  "paths": {
    "plans": "docs/plans",
    "research": "docs/research",
    "plan_archive": "docs/_local_archive"
  },
  "agent_context": {
    "project_name": "Wonderloom",
    "tech_stack": "React + TypeScript + Vite frontend, Supabase Edge Functions + Deno backend"
  },
  "e2e_gate": {
    "enabled": true,
    "script": "scripts/check-e2e-prereqs.sh"
  }
}
```

## Field reference

| Field | Purpose |
|-------|---------|
| `name` | Short slug for logs and dispatcher output |
| `github.owner` / `github.repo` / `github.project_number` | Target board identifiers |
| `workflow.kind` | Only `gen-eval-9col` in v1 — see seed issue #10 for pluggable shapes |
| `workflow.column_names` | Optional aliases when display names diverge from the canonical 9 |
| `workflow.actionable_columns` | Columns the dispatcher should poll |
| `paths.plans` / `paths.research` / `paths.plan_archive` | Per-project doc layout |
| `agent_context` | Substituted into agent prompts as `{{PROJECT_NAME}}` and `{{TECH_STACK}}` |
| `e2e_gate` | Optional pre-PR gate script |

## Notes

- `board-constants.sh` (option-ID hardcoding) is eliminated. A new
  `harness-lib.sh` resolves column NAMES to GitHub Project v2 option
  UUIDs at runtime via a per-session in-memory cache.
- The harness is opinionated about the 9-phase workflow shape and the
  two human gates; it is flexible about display names and which
  columns the dispatcher polls.
