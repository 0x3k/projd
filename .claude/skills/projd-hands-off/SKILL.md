---
name: projd-hands-off
description: "Launch parallel agents on parallelizable features. Each agent gets an isolated worktree and works autonomously, with automated tests as the quality gate."
user-invocable: true
disable-model-invocation: true
argument-hint: "[--dry-run]"
---

You are a coordinator launching parallel agents to work on independent features autonomously.

## Context

agent.json:
!`./scripts/skill-context.sh agent-json`

Features:
!`./scripts/skill-context.sh features`

Current branch: !`./scripts/skill-context.sh branch`

CLAUDE.md overview:
!`./scripts/skill-context.sh claude-md`

## Arguments

`$ARGUMENTS`

## Instructions

### 1. Identify parallelizable features

From the feature summary above:
- Filter: `status == "pending"`
- Filter: `blocked_by` is empty, OR every ID in `blocked_by` has `status: "complete"`
- Group into parallelizable sets: features that have no mutual `blocked_by` relationships can run simultaneously

### 2. Dry run check

If `$ARGUMENTS` contains `--dry-run`:
- Present the dispatch plan as a table: feature id, name, priority, will be dispatched in parallel?
- Do NOT spawn any agents. Stop here.

### 3. Read full feature files

For each feature to dispatch, read the full `progress/{id}.json` to get acceptance criteria and description.

### 4. Spawn agents

For each feature (max 3 concurrent):

Spawn an Agent with:
- `isolation: "worktree"` -- gives each agent its own git working directory
- `run_in_background: true` -- agents work in parallel

Each agent prompt must include:
- The feature ID, name, and full description
- All acceptance criteria
- The branch prefix from agent.json (agent must create branch `{prefix}{feature-id}`)
- Instructions to:
  1. Create the feature branch: `git checkout -b {prefix}{feature-id}`
  2. Update `progress/{feature-id}.json` with `status: "in_progress"` and `branch`
  3. Implement all acceptance criteria
  4. Run `./scripts/smoke.sh` to verify
  5. Commit all changes with descriptive messages
  6. If smoke passes and all criteria met: set `status: "complete"`, push branch, create PR via `gh pr create`
  7. If incomplete: set notes with progress, write HANDOFF.md
- Key conventions from CLAUDE.md (code style, test patterns)

### 5. Collect results

Wait for all agents to complete. For each:
- Check if the feature was marked complete
- Note any failures or partial completions
- Collect PR URLs if created

### 6. Report

Present a summary table: feature id, status (complete/partial/failed), PR URL if any, notes.

## Guardrails

- Maximum 3 concurrent agents. If more features are eligible, dispatch in waves.
- Do NOT retry failed agents automatically. Report failures for the operator to decide.
- Each agent gets a focused, single-feature prompt. Do not include unrelated features or exploration instructions.

## Output

End with:

> Dispatched [N] agents. [M] completed, [K] need attention. Review PRs when ready.
