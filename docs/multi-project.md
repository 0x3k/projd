# Multi-Project Workspaces

For projects with sub-projects (monorepos, microservices, platform repos), create a `projects.json` at the root:

```json
{
  "projects": [
    {"path": "services/api", "name": "API Service", "description": "REST API"},
    {"path": "services/worker", "name": "Worker", "description": "Background jobs"},
    {"path": "packages/shared", "name": "Shared Lib", "description": "Common utilities"}
  ]
}
```

Each sub-project is a self-contained projd instance (its own `CLAUDE.md`, `.projd/progress/`, `.projd/scripts/`). Run `./setup.sh` in each one.

## How aggregation works

When `projects.json` exists, the root scripts automatically aggregate:

| Script | Behavior |
|--------|----------|
| `./.projd/scripts/status.sh` | Shows status for each sub-project, then root |
| `./.projd/scripts/smoke.sh` | Runs each sub-project's smoke checks, then root |
| `./.projd/scripts/init.sh` | Bootstraps each sub-project, then root |

## Root vs. sub-project features

- **Root `.projd/progress/`**: Cross-cutting features that span multiple sub-projects
- **Sub-project `.projd/progress/`**: Features scoped to that project

An agent working in a sub-project reads both the root and sub-project `CLAUDE.md` for full context.
