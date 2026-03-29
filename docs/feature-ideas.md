# Feature Ideas for projd

> Last updated: 2026-03-28
> Based on review of: full source code (scripts, hooks, skills, CLI, docs), README, CLAUDE.md, .projd/agent.json, test suites, landing page

## Overview

projd orchestrates long-running and parallel AI agent sessions for Claude Code. These feature ideas aim to improve two dimensions: (1) making the operator experience smoother and more transparent, and (2) making agent work more reliable and efficient. Ideas are grounded in the current bash/skill/hook architecture and the data already flowing through `.projd/progress/*.json`, `.projd/agent.json`, and the session lifecycle.

## Existing Features

Verified against source code:

- Feature planning with dependency tracking (`/projd-plan`, `.projd/progress/*.json`, `blocked_by`)
- Branch-per-feature isolation via git worktrees (`/projd-hands-off`)
- Git policy enforcement via PreToolUse hook (`check-git-policy.sh`)
- Path escape prevention via PreToolUse hook (`check-path-guard.sh`, vibes mode only)
- Parallel dispatch with wave scheduling (`/projd-hands-off`, up to `max_agents`)
- Auto-review / vibes mode (`auto_review: true` in `.projd/agent.json`)
- Interactive single-feature workflow (`/projd-hands-on`)
- Session continuity via `.projd/HANDOFF.md` (`projd-start` / `projd-end`)
- Smoke-test quality gates (`.projd/scripts/smoke.sh`)
- Configuration validation (`.projd/scripts/validate.sh`)
- Live terminal monitor dashboard (`.projd/scripts/monitor.sh`)
- Status line integration (`.projd/scripts/statusline.sh`)
- Non-destructive project adoption (`/projd-adopt`)
- Template scaffolding (`/projd-create`)
- Template upgrade with conflict detection (`.projd/scripts/upgrade.sh`)
- npm/curl installer (`bin/projd.js`, `.projd/scripts/remote-install.sh`)
- Multi-project / monorepo support (`projects.json`)
- Per-session token usage display (statusline)

## Proposed Features

### Feature Lifecycle

#### Feature Splitting

**Impact**: High | **Feasibility**: Easy | **Dimension**: Effectiveness

A `/projd-split` skill that decomposes a feature that turned out to be too large into two or more sub-features. This is the most common mid-session need: you start implementing and realize the feature is a multi-session effort. Currently the operator must manually create new feature files, adjust `blocked_by` relationships, and update the original feature's status.

The skill should read the original feature file, ask the operator how to split (or suggest a split based on the acceptance criteria), create new feature files with the original's ID as a prefix (e.g., `auth-flow` becomes `auth-flow-backend` and `auth-flow-frontend`), wire up `blocked_by` so sub-features depend on each other correctly, and mark the original as superseded. Any existing progress notes or partial implementation context should carry forward into the appropriate sub-feature.

Connects to: `.projd/progress/*.json` schema, `/projd-plan` (same output format), `projd-end` (which may trigger the split when criteria aren't met).

#### Feature Rollback

**Impact**: High | **Feasibility**: Easy | **Dimension**: UI/UX

A `/projd-rollback <feature-id>` skill that cleanly undoes a feature: resets its status to `pending`, clears the `branch` field, removes the git worktree if one exists, and optionally deletes the branch. Currently rolling back a stuck or failed feature requires multiple manual git and file operations.

This is especially valuable after a failed `/projd-hands-off` run where one or more features are left in `in_progress` with no active agent. The operator needs a quick way to reset those features so they can be re-dispatched.

Connects to: `.projd/progress/*.json` (status and branch fields), git worktree management, `check-git-policy.sh` (branch deletion must respect policy).

#### Feature File Linting

**Impact**: Medium | **Feasibility**: Easy | **Dimension**: UI/UX

Extend `.projd/scripts/validate.sh` (or create a dedicated linter) to check feature files for quality issues beyond schema validity: vague acceptance criteria (e.g., "it should work well"), circular `blocked_by` dependencies, orphaned blockers (referencing feature IDs that don't exist), features with no acceptance criteria, and duplicate feature IDs.

Currently `validate.sh` checks that feature files exist and have required fields, but doesn't assess the quality of the content. Bad criteria lead to agent confusion and wasted tokens. Catching these at planning time is much cheaper than discovering them during implementation.

Connects to: `.projd/scripts/validate.sh` (extend or complement), `.projd/progress/*.json` (all feature files), `/projd-plan` (could run linter as a post-planning gate).

#### Feature Templates

**Impact**: Low | **Feasibility**: Easy | **Dimension**: UI/UX

Provide optional feature templates for common shapes: API endpoint, UI component/page, database migration, CLI command, configuration change, refactoring. Each template pre-fills acceptance criteria patterns relevant to that shape (e.g., an API endpoint template includes "responds with correct status codes", "input validation rejects malformed requests", "endpoint is documented in OpenAPI spec").

These would live in a `templates/` directory or be embedded in `/projd-plan`. The operator selects a template when creating a feature, then customizes the pre-filled criteria. Reduces the cognitive load of writing good acceptance criteria from scratch every time.

Connects to: `/projd-plan` (template selection during planning), `.projd/progress/*.json` (output format unchanged).

---

### Parallel Dispatch

#### Conflict Pre-Check

**Impact**: High | **Feasibility**: Medium | **Dimension**: Effectiveness

Before `/projd-hands-off` dispatches agents, analyze the acceptance criteria and feature descriptions of all features in the current wave to predict file overlap. If two features are likely to touch the same files (e.g., both mention "update the user model" or "modify the API router"), warn the operator and suggest sequencing them instead of parallelizing.

This prevents the most common failure mode in parallel dispatch: two agents modify the same file, creating merge conflicts that require manual resolution. The analysis doesn't need to be perfect -- even keyword-based heuristic matching on file paths and module names mentioned in criteria would catch the obvious cases.

Connects to: `/projd-hands-off` (pre-dispatch phase), `.projd/progress/*.json` (reads descriptions and criteria), could optionally use `git log --name-only` to check which files were touched by related past features.

#### Retry with Failure Context

**Impact**: High | **Feasibility**: Medium | **Dimension**: Effectiveness

When a feature fails (agent gives up, smoke tests fail, or the session crashes), capture structured failure context: which acceptance criteria were met, which failed, what errors occurred, what approach was tried. Store this in the feature's `notes` field or a companion file. On retry, feed this context to the next agent so it doesn't repeat the same failed approach.

Currently, retrying a failed feature means starting from scratch. The new agent has no knowledge of what was tried before, so it often repeats the same mistake. Even a simple "previous attempt failed because: X" note would significantly improve retry success rates.

Connects to: `projd-end` (captures failure state), `projd-start` (reads failure context), `.projd/progress/*.json` (notes field or new `attempts` array field), `/projd-hands-off` (retry orchestration).

#### Dispatch Summary Report

**Impact**: Medium | **Feasibility**: Easy | **Dimension**: UI/UX

After `/projd-hands-off` completes all waves, generate a structured markdown report: features attempted, success/failure status per feature, PRs created (with links), token usage per agent, total wall-clock time, and any features that need manual attention. Write it to `reports/dispatch-YYYY-MM-DD.md` or print to the console.

Currently the operator gets real-time output from `monitor.sh` and a final summary in the console, but nothing persistent. For large dispatches (10+ features), having a written record makes it easier to review what happened and prioritize follow-up work.

Connects to: `/projd-hands-off` (generates report after all agents complete), `.projd/progress/*.json` (reads final states), `.projd/scripts/statusline.sh` (token usage data).

#### Smart Re-dispatch

**Impact**: Medium | **Feasibility**: Medium | **Dimension**: Effectiveness

Enhance `/projd-hands-off` to detect features stuck in `in_progress` with no active agent (stale sessions) and offer to reset and re-dispatch them. Also detect features that were previously attempted but failed, and present them separately with their failure context.

Currently, the operator must manually identify stuck features, reset their status, and run `/projd-hands-off` again. This enhancement makes the retry loop more automated while keeping the operator in control (showing what will be retried and why, rather than silently re-dispatching).

Connects to: `/projd-hands-off` (enhanced pre-dispatch analysis), `.projd/progress/*.json` (status and notes fields), git worktree state (detect orphaned worktrees).

---

### Observability

#### Dependency Graph Visualization

**Impact**: High | **Feasibility**: Medium | **Dimension**: UI/UX

Generate an ASCII or mermaid-syntax dependency graph showing all features, their statuses, and `blocked_by` relationships. Display it in `/projd-plan` output, `.projd/scripts/status.sh`, or as a standalone command. Color-code by status: pending (gray), in-progress (yellow), complete (green), blocked (red).

Currently, understanding the dependency structure requires reading each feature file individually or parsing the `/projd-hands-off --dry-run` wave output. A visual graph makes the project's shape immediately obvious -- especially valuable when there are 10+ features with complex dependency chains.

A mermaid output option would also render in GitHub PR descriptions and README files, making the project plan shareable.

Connects to: `.projd/progress/*.json` (reads all features), `.projd/scripts/status.sh` (could embed graph), `/projd-plan` (show graph after planning), `/projd-hands-off --dry-run` (show graph in dispatch preview).

#### Token and Cost Economy

**Impact**: Medium | **Feasibility**: Medium | **Dimension**: Effectiveness

Track cumulative token usage (input and output) per feature across sessions. Store running totals in the feature file or a companion `economy.json`. Show aggregate stats: total tokens consumed by the project, average tokens per feature, tokens remaining in budget (if operator sets a budget), and cost estimates based on current model pricing.

The statusline already shows per-session token usage, and `skill-context.sh token-usage` reads Claude session logs. This feature aggregates that data at the feature and project level, persisting it across sessions. Useful for operators managing API budgets or estimating costs for future projects based on past data.

Connects to: `.projd/scripts/statusline.sh` (current token tracking), `.projd/scripts/skill-context.sh token-usage` (session log parsing), `.projd/progress/*.json` (per-feature storage), `projd-end` (records token usage at session end).

#### Projd Status Skill

**Impact**: Medium | **Feasibility**: Easy | **Dimension**: UI/UX

A `/projd-status` skill that provides a richer overview than `.projd/scripts/status.sh` but doesn't require the interactive `monitor.sh` TUI. Shows: feature progress table (id, status, branch, PR link), dependency graph (ASCII), active worktrees with their agent status, smoke test results, recent git activity across all feature branches, and any features needing attention (stuck, failed, unblocked-and-ready).

This fills the gap between the raw `status.sh` output (which is terse and script-oriented) and `monitor.sh` (which requires a dedicated terminal). Most operators just want a quick "where are we?" answer without launching a TUI.

Connects to: `.projd/scripts/status.sh` (extends), `.projd/progress/*.json`, git worktree and branch state, `.projd/scripts/smoke.sh`.

---

### Developer Experience

#### Branch and Worktree Cleanup

**Impact**: Medium | **Feasibility**: Easy | **Dimension**: UI/UX

A `/projd-cleanup` skill (or script) that removes merged feature branches and orphaned worktrees. After a batch of PRs are merged, the operator is left with stale local branches and worktree directories. Currently, cleanup requires running `git branch -d` and `git worktree remove` manually for each feature.

The skill should: list all branches matching the configured prefix, identify which have been merged to main, remove merged branches and their worktrees, and report what was cleaned up. Optionally remove worktrees for features in `complete` status even if the branch hasn't been merged yet (with confirmation).

Connects to: `.projd/agent.json` (branch prefix), `.projd/progress/*.json` (feature status), git branch and worktree state.

#### Adopt Dry-Run

**Impact**: Medium | **Feasibility**: Easy | **Dimension**: UI/UX

Add a `--dry-run` flag to `/projd-adopt` that shows exactly what files would be created, modified, or merged -- without making any changes. Currently, adopting projd into an existing project is a one-way operation (though it backs up conflicts to `.pre-projd/`). A dry-run lets the operator review the impact before committing.

This is especially important for projects with existing `.claude/settings.json` or `CLAUDE.md` files, where the merge behavior needs to be understood before execution.

Connects to: `/projd-adopt` skill (add --dry-run flag handling at the beginning of the workflow).

#### Post-Dispatch Notification

**Impact**: Low | **Feasibility**: Easy | **Dimension**: UI/UX

After `/projd-hands-off` completes (all waves done), trigger a terminal bell and optionally an OS notification (via `osascript` on macOS or `notify-send` on Linux). For long-running parallel dispatches, the operator may switch to other work and miss the completion.

Could also support a webhook URL in `.projd/agent.json` for Slack/Discord notifications, but the simple terminal notification covers the common case with zero configuration.

Connects to: `/projd-hands-off` (fires notification at end of dispatch), `.projd/agent.json` (optional webhook URL field).

---

### Integration

#### CI Feedback Loop

**Impact**: High | **Feasibility**: Hard | **Dimension**: Effectiveness

A mechanism for CI pipeline results to flow back into projd's feature lifecycle. When a PR's CI checks fail, the feature's status could be updated with the failure details, and the operator (or auto-review agent) gets actionable context about what broke.

This could work via a post-CI script that reads PR check status (`gh pr checks`) and updates the corresponding feature file. Or a GitHub Action that calls a projd script when checks complete. The key insight is that smoke tests run locally, but CI often catches issues that local smoke misses (different OS, integration tests, deployment checks).

Connects to: `.projd/progress/*.json` (status and notes), `projd-end` (currently only checks local smoke), GitHub Actions / CI systems, `gh` CLI.

#### Changelog Generation

**Impact**: Medium | **Feasibility**: Medium | **Dimension**: Effectiveness

After a set of features are complete and merged, auto-generate release notes from the feature descriptions, acceptance criteria, and PR bodies. Group by category (if features have tags/labels) or by wave. Output as a markdown file or as input to `gh release create`.

The data already exists in `.projd/progress/*.json` and in the PR bodies that `projd-end` creates. This skill just aggregates and formats it. Valuable for projects that ship releases to users and need to communicate what changed.

Connects to: `.projd/progress/*.json` (feature descriptions), PR bodies (created by `projd-end`), `gh release create` (optional output target).

#### Feature Progress Webhooks

**Impact**: Low | **Feasibility**: Medium | **Dimension**: Effectiveness

Optional webhook configuration in `.projd/agent.json` that fires HTTP requests when feature status changes. Enables integration with project management tools (Linear, Jira, Notion), chat (Slack, Discord), or custom dashboards.

Payload would include: feature ID, old status, new status, branch, PR URL (if applicable), and timestamp. The webhook URL and optional auth header would be configured in `.projd/agent.json` under a new `integrations` key.

Connects to: `.projd/agent.json` (new `integrations.webhook_url` field), `projd-end` (fires webhook on status change), `.projd/progress/*.json` (status transitions).

---

### Moonshots

#### Codebase-Aware Planning

**Impact**: High | **Feasibility**: Hard

Enhance `/projd-plan` to analyze the existing codebase structure before generating features. Map modules, imports, test coverage, and file organization to inform how features are decomposed. A feature that touches a well-tested module with clear interfaces should be sized differently than one that requires modifying untested, tightly-coupled code.

This would require static analysis (at least file-level dependency graphing) and heuristics about code complexity. The payoff is better feature sizing, more accurate `blocked_by` relationships, and fewer mid-implementation surprises. The hard part is making it language-agnostic given projd's multi-language support.

#### Cross-Feature Impact Analysis

**Impact**: High | **Feasibility**: Hard

When a feature modifies shared code (utility functions, database schemas, API contracts), identify other in-progress or pending features that depend on the same code. Surface this as a warning before merging, so the operator knows which other features might need rebasing or adjustment.

This requires understanding code-level dependencies across feature branches -- essentially a diff-aware dependency graph. Git's merge-base and diff tools provide the raw data, but interpreting it (which changes are "shared code" vs. "isolated to this feature") requires heuristics.

#### Adaptive Agent Configuration

**Impact**: Medium | **Feasibility**: Hard

Track agent performance across features (success rate, token consumption, retry frequency) and suggest `.projd/agent.json` tuning. For example: if agents consistently fail on large features, suggest lowering the acceptance criteria count threshold. If token usage varies wildly, suggest adjusting `max_agents` to avoid rate limiting. If certain types of features always succeed on first try, suggest enabling `auto_review` for those categories.

This requires a historical data layer that persists across sessions and dispatches -- beyond what the current feature files store.

## Past Ideas

_No previous ideation sessions recorded._
