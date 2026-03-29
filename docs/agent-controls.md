# Agent Controls

`.projd/agent.json` defines what agents are allowed to do:

```json
{
  "git": {
    "branch_prefix": "agent/",
    "protected_branches": ["main", "master"],
    "allow_push": "feature",
    "allow_force_push": false,
    "auto_commit": true
  },
  "dispatch": {
    "max_agents": 20,
    "auto_review": false
  }
}
```

## Configuration reference

| Field | Default | Effect |
|-------|---------|--------|
| `git.branch_prefix` | `"agent/"` | All agent-created branches must start with this prefix |
| `git.protected_branches` | `["main", "master"]` | Agent must never commit directly to these branches |
| `git.allow_push` | `"feature"` | `false`: no pushing. `"feature"`: push only branches with the configured prefix. `true`: push anything. |
| `git.allow_force_push` | `false` | If false, `--force` push is blocked |
| `git.auto_commit` | `true` | If true, agent commits incrementally. If false, agent stages changes but the operator commits. |
| `dispatch.max_agents` | `20` | Maximum parallel agents spawned by `/projd-hands-off`. Dispatches in waves if more features are eligible. |
| `dispatch.auto_review` | `false` | If true, a reviewer agent auto-reviews each PR: runs smoke tests, verifies acceptance criteria, fixes issues, and merges passing PRs. |

## Enforcement

These rules are enforced at two layers. The primary enforcement is a Claude Code **PreToolUse hook** (`.claude/hooks/check-git-policy.sh`) that intercepts every bash command and blocks violations before they execute. A secondary **pre-push hook** via Lefthook guards against direct `git push` usage outside of Claude Code. See [hooks.md](hooks.md) for details.
