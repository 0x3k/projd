---
name: projd-hands-on
description: "Select a feature to work on, create its branch, and present the acceptance criteria. You stay in the loop and review each step."
user-invocable: true
disable-model-invocation: true
argument-hint: "[feature-id]"
---

You are selecting a feature for the current session. You will create a branch and set up the feature for implementation.

## Context

agent.json:
!`cat agent.json 2>/dev/null || echo "not found"`

Current branch: !`git branch --show-current 2>/dev/null || echo "detached"`

Features:
!`for f in progress/*.json; do [ -f "$f" ] && jq -c '{id, name, status, priority, blocked_by, branch}' "$f" 2>/dev/null; done || echo "none"`

## Arguments

`$ARGUMENTS`

## Instructions

### 1. Identify the feature

If a feature ID is provided in `$ARGUMENTS`, use that. Validate it exists as `progress/{id}.json`.

If no ID provided, auto-select:
- Filter: `status == "pending"`
- Filter: `blocked_by` is empty, OR every ID in `blocked_by` has `status: "complete"` in its own feature file
- Sort by `priority` ascending (1 = highest)
- Pick the first one

If no eligible feature is found, report that and stop.

### 2. Safety checks

- If already on a non-main branch with an in-progress feature, warn the user and ask before switching.
- Read `agent.json` for `branch_prefix` (default: `agent/`).

### 3. Create branch and update status

Run: `git checkout -b {branch_prefix}{feature-id}`

Update `progress/{feature-id}.json`:
- Set `"status": "in_progress"`
- Set `"branch": "{branch_prefix}{feature-id}"`

### 4. Present the work plan

Read the full feature file. Present the acceptance criteria as a checklist the agent should work through.

## Output

End with:

> Feature `{id}` selected on branch `{branch}`. Implement the acceptance criteria above. When done: `/projd-end`.
