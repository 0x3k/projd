# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## Template Guard

**If the Project Name below is still `my-project`, this is the uninitialized projd template -- not a real project.** Do NOT follow the session conventions, feature workflow, or agent controls below. They are meant for initialized projects and will not work here.

Instead, help the user get started. There are two paths:

1. **Create a new project from this template** (recommended): The user should copy this directory to a new location and run setup there. Walk them through it:
   ```
   cp -r <this-directory> ~/repos/<project-name>
   cd ~/repos/<project-name>
   rm -rf .git && git init
   ./setup.sh
   ```
   Or, if the `/projd-create` skill is installed, they can run that from any session and it handles everything.

2. **Use this directory as the project**: If the user wants to turn this copy into their project directly, run `./setup.sh` here. It will prompt for a name, language, and description, then configure everything.

After setup completes, this guard no longer applies -- the project name will have been replaced and the rest of this file becomes active.

**Stop here and help the user. Do not read further until the project is initialized.**

---

## Project Overview

**Name**: my-project
**Language**: <!-- e.g., TypeScript, Go, Python, Swift -->
**Purpose**: <!-- One-line description -->

## Build & Dev Commands

```bash
# Install dependencies
# npm install / pip install -r requirements.txt / go mod download

# Development
# npm run dev / python main.py / go run ./cmd/server

# Build
# npm run build / go build -o server ./cmd/server

# Lint
# npm run lint / ruff check . / go vet ./...

# Type check
# npm run type-check / tsc --noEmit / mypy .

# Test
# npm test / pytest / go test ./...
```

## Architecture

## Environment Variables

| Variable | Required | Default | Purpose |
|----------|----------|---------|---------|
| `EXAMPLE_VAR` | yes | - | Example description |

## Key Patterns

## Agent Controls

Read `agent.json` before any git operation. It defines what you are allowed to do:

```json
{
  "git": {
    "branch_prefix": "agent/",
    "protected_branches": ["main", "master"],
    "allow_push": "feature",
    "allow_force_push": false,
    "auto_commit": true
  }
}
```

Rules:
- **Branch prefix**: Always create branches with the configured prefix (e.g., `agent/feature-name`)
- **Protected branches**: Never commit directly to these branches. Always work on a feature branch.
- **Push**: `"feature"` allows pushing branches that start with the configured prefix. `false` blocks all pushes. `true` allows all pushes.
- **Force push**: If `allow_force_push` is false, never force-push under any circumstances.
- **Auto commit**: If true, commit after each meaningful unit of work. If false, stage changes but let the operator commit.

These rules are enforced by a PreToolUse hook in `.claude/hooks/check-git-policy.sh`. The hook blocks violations before commands execute.

## Session Conventions

### Skills (projd)

This project includes a skill family called `projd` (project daemon) that automates the workflow:

**Human-facing** (invoked by the operator):
- `/projd-plan` -- Create feature files from requirements. Does not implement.
- `/projd-hands-on` -- Select a feature, create its branch, present acceptance criteria. You stay in the loop.
- `/projd-hands-off` -- Launch parallel agents on parallelizable features. Tests are the quality gate.

**Agent-facing** (auto-triggered by Claude):
- `projd-start` -- Orient at session start: read state, handoff, smoke test, identify feature.
- `projd-end` -- Wrap up: commit, update feature, push branch, create PR if complete.

### Session Start

The `projd-start` skill handles orientation automatically. It:

1. Runs `./scripts/status.sh` to see git state, progress, and handoff context
2. Reads `HANDOFF.md` for context from the previous session (if it exists)
3. Runs `./scripts/smoke.sh` to verify nothing is currently broken
4. Identifies the current feature from the branch, or finds the highest-priority pending unblocked feature

### Session End

The `projd-end` skill handles wrap-up automatically. It:

1. Commits completed work with descriptive messages (if `auto_commit` is true)
2. Updates the feature file in `progress/`:
   - Sets `"status": "complete"` if all acceptance criteria are met and smoke passes
   - Keeps `"status": "in_progress"` if partially done, with notes
3. Pushes the feature branch and creates a PR (if `allow_push` permits)
4. Writes `HANDOFF.md` if work is incomplete, or deletes it if complete
5. Runs `./scripts/smoke.sh` as a final gate

### Feature Workflow

Each feature is a JSON file in `progress/`. The lifecycle:

```
pending --> in_progress --> complete --> PR merged
```

Use `/projd-hands-on` to start a feature:
1. Checks that its `blocked_by` list is resolved (all blockers are `complete`)
2. Creates a branch: `git checkout -b {branch_prefix}{feature-id}`
3. Sets `"status": "in_progress"` and `"branch"` in the feature file
4. Presents acceptance criteria as the work plan

Implementation:
5. Implement against the acceptance criteria
6. Verify with `./scripts/smoke.sh` and tests
7. `projd-end` marks complete and creates a PR when all criteria pass

### Parallel Sessions

Use `/projd-hands-off` to run multiple agents in parallel:

1. Scans `progress/` for pending unblocked features
2. Groups features that can run simultaneously (no mutual `blocked_by`)
3. Spawns isolated subagents, each in its own git worktree
4. Each agent works on one feature: creates branch, implements, commits, PRs

Rules:
- Each agent works in its **own worktree** on its **own branch**
- Feature files in `progress/` are per-feature, so there are no write conflicts
- Never pick a feature whose `blocked_by` dependencies are not yet `complete`
- Never pick a feature that already has `"status": "in_progress"` (another agent owns it)

Use `--dry-run` to preview the dispatch plan without spawning agents.

### Planning Sessions

Use `/projd-plan` for planning:

1. Provide requirements (description or file path)
2. The skill breaks them into discrete features with acceptance criteria
3. Sets `blocked_by` to express dependencies
4. Identifies which features can be parallelized
5. Does NOT start implementation -- the plan is the deliverable

### Session Discipline

- **One feature per session**: Pick one item, implement it, test it, commit it. Resist the urge to refactor adjacent code or start additional features.
- **Verify before marking complete**: Run `./scripts/smoke.sh` and any relevant tests. Do not mark a feature as `complete` until all acceptance criteria pass.
- **Incremental commits**: Commit after each meaningful unit of work. Descriptive commit messages enable rollback and make the next session's context-gathering faster.
- **Leave the codebase clean**: Every commit should be mergeable to main. No half-implemented features, no commented-out code, no TODO breadcrumbs without corresponding feature files.

## Sub-Projects

If `projects.json` exists at the root, this is a multi-project workspace. Each sub-project is a self-contained directory with its own `CLAUDE.md`, `progress/`, and scripts.

When working in a sub-project:
1. Read both the root `CLAUDE.md` (this file) and the sub-project's `CLAUDE.md`
2. Use the sub-project's `progress/` for project-specific features
3. Use the root `progress/` for cross-cutting features that span sub-projects
4. Run the sub-project's `./scripts/smoke.sh` for local checks; run the root `./scripts/smoke.sh` for the full suite

## Pre-Commit Quality Gates

This project uses [Lefthook](https://github.com/evilmartians/lefthook) for pre-commit hooks. Install with:

```bash
./scripts/init.sh
```

Git policies from `agent.json` are enforced by a Claude Code PreToolUse hook (`.claude/hooks/check-git-policy.sh`). The Lefthook pre-push hook provides a secondary guard for direct git usage outside Claude Code.

## Code Conventions

- Never use emojis in code or comments
