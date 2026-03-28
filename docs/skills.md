# Skills

projd includes a family of skills that automate the workflow. Some are invoked by the operator, others are triggered automatically by the agent.

## User-invocable skills

| Skill | Purpose |
|-------|---------|
| `/projd-plan <requirements>` | Break requirements into feature files. Optionally researches existing solutions for inspiration. Does not implement. |
| `/projd-hands-on [feature-id]` | Select a feature, create branch, present acceptance criteria. You stay in the loop. |
| `/projd-hands-off [--dry-run]` | Launch parallel agents on independent features. Optional auto-review merges passing PRs. |
| `/projd-create [name]` | Scaffold a new project from the template (user-level, install with `install-skill.sh`). |

## Agent-facing skills

| Skill | Purpose |
|-------|---------|
| `projd-start` | Agent orientation at session start. Reads status, handoff notes, runs smoke tests, identifies the current feature. |
| `projd-end` | Session wrap-up. Commits work, updates feature status, pushes branch, creates PR if complete, writes handoff if incomplete. |

These are triggered automatically -- you do not need to invoke them.
