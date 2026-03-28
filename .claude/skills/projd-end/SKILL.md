---
name: projd-end
description: "Session wrap-up: commit work, update feature status, push feature branch, create PR if complete, write handoff if incomplete. Run this when all acceptance criteria are met or the session is ending."
user-invocable: false
---

You are wrapping up a work session. Commit, verify, deliver.

## Context

Current branch: !`git branch --show-current 2>/dev/null || echo "detached"`

Working tree:
!`git status --short 2>/dev/null || echo "not a git repo"`

Changes:
!`git diff --stat 2>/dev/null`

agent.json:
!`cat agent.json 2>/dev/null || echo "not found"`

Features:
!`for f in progress/*.json; do [ -f "$f" ] && jq -c '{id, name, status, priority, blocked_by, branch}' "$f" 2>/dev/null; done || echo "none"`

## Instructions

### Step 1: Commit

Check `agent.json` for `auto_commit`.

If there are uncommitted changes (staged or unstaged):
- If `auto_commit` is `true`: stage relevant files and commit with a descriptive message. Make incremental commits if there are logically separate changes.
- If `auto_commit` is `false`: stage files but do NOT commit. Note that changes are staged for the operator.

### Step 2: Identify and update feature

Match the current branch to a feature file (compare to `branch` field in progress/*.json).

If matched, read the full feature file and verify EACH acceptance criterion:
- For each criterion, check the codebase to confirm it is met.
- If ALL criteria pass, mark for completion.
- If any fail, keep status as `in_progress` and add notes about what was done and what remains.

### Step 3: Smoke test

Run `./scripts/smoke.sh`. If it fails:
- Do NOT mark the feature as `complete`, even if acceptance criteria pass.
- Document failures in the feature notes.

### Step 4: Update feature file

If all criteria pass AND smoke passes:
- Set `"status": "complete"` in the feature file.

Otherwise:
- Keep `"status": "in_progress"`.
- Update `"notes"` with what was accomplished and what remains.

### Step 5: Push and PR

Read `allow_push` from `agent.json`.

If feature is `complete` AND (`allow_push` is `"feature"` or `true`):
1. Push the branch: `git push -u origin {branch}`
2. Create a PR using `gh pr create`:
   - Title: the feature name
   - Body: include a summary of changes and the acceptance criteria as a checked checklist
   - Base branch: `main`
3. Record the PR URL in the feature file `notes` field.

If `allow_push` is `false`: skip push and PR. Note in output that the operator should handle pushing.

If `gh` is not available: push the branch only, skip PR creation, warn about missing `gh` CLI.

### Step 6: Handoff

If feature is incomplete:
- Create or overwrite `HANDOFF.md` with:
  - What was done this session
  - Current state (what works, what is broken)
  - Prioritized next steps

If feature is complete:
- Delete `HANDOFF.md` if it exists.

## Edge Cases

- **No matching feature** (ad-hoc work): Skip step 2 and step 4. Still commit (step 1), smoke test (step 3), and write handoff (step 6).
- **Detached HEAD**: Warn and skip push/PR. Still commit and write handoff.

## Output

If complete:

> Feature `{id}` complete. PR created: {url}. Merge when ready.

If incomplete:

> Session wrapped. HANDOFF.md written for next session.
