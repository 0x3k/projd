---
name: projd-start
description: "Agent orientation: read project state, handoff context, smoke test, and identify the current feature. Run this at the start of every work session before implementing anything."
user-invocable: false
---

You are an agent starting a work session. Orient yourself before doing any implementation.

## Context

Project status:
!`./scripts/status.sh 2>&1 || echo "status.sh failed"`

Handoff from previous session:
!`cat HANDOFF.md 2>/dev/null || echo "No HANDOFF.md -- clean start."`

Smoke test:
!`./scripts/smoke.sh 2>&1; echo "EXIT_CODE=$?"`

Features:
!`for f in progress/*.json; do [ -f "$f" ] && jq -c '{id, name, status, priority, blocked_by, branch}' "$f" 2>/dev/null; done || echo "none"`

Current branch: !`git branch --show-current 2>/dev/null || echo "detached"`

## Instructions

### 1. Assess project state

Summarize:
- Git state (branch, clean/dirty)
- Whether a handoff exists and what it says
- Whether smoke tests pass

### 2. Handle smoke failures

If smoke.sh exited non-zero, list the failures. These MUST be fixed before starting feature work. Do not proceed to implementation until smoke passes.

### 3. Identify current feature

Check if the current branch matches an in-progress feature (compare branch name to `branch` field in feature files).

If matched: this is a resumed session. Read the full `progress/{id}.json` file and present the acceptance criteria.

If not matched: scan for pending unblocked features (same logic as projd-hands-on). Read the full feature file for the top candidate and present it. Note that you need to create a branch first -- follow the projd-hands-on workflow.

### 4. Present work plan

Show the feature name, description, and acceptance criteria as a checklist.

## Output

End with:

> Oriented. Working on `{feature-name}`. Implement the acceptance criteria above. When done, run the projd-end skill.

If smoke failed:

> Smoke test failed. Fix the issues above before starting feature work.
