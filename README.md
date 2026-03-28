# projd

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Built for Claude Code](https://img.shields.io/badge/Built_for-Claude_Code-6B5CE7)](https://claude.ai/code)

**Project Daemon** -- pronounced "prodigy" `/ˈprɒdɪdʒi/` by some. We don't correct them.

> A project harness for long-running and parallel AI agent sessions. You describe what you want, projd breaks it into features, and Claude builds them -- one at a time or several in parallel. You review PRs. That's the whole deal.

Based on patterns from [Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) and production-tested conventions.

---

### Quick Start

```bash
./scripts/install-skill.sh   # install the scaffolding skill (one-time)
```
```
/projd-create                 # scaffold a new project from any Claude Code session
/projd-plan "your idea"       # break it into features
/projd-hands-on               # build one feature at a time
/projd-hands-off              # or launch parallel agents
```

---

## Why

Claude Code works great in a single sitting. But when sessions get long or you want multiple agents working at once, things fall apart: the agent loses context between sessions, commits to branches it shouldn't, starts work that conflicts with other agents, and leaves half-finished code behind with no trail.

projd adds the structure that makes long-running and parallel agent work reliable: session continuity through handoff notes, git guardrails through policy hooks, a feature lifecycle that tracks what's done and what's next, and branch-per-feature isolation so agents don't step on each other.

## Prerequisites

- [Claude Code](https://claude.ai/code): CLI, desktop app, or IDE extension
- [Lefthook](https://github.com/evilmartians/lefthook): `brew install lefthook`
- [jq](https://jqlang.github.io/jq/): `brew install jq`
- [GitHub CLI](https://cli.github.com/): `brew install gh` (for PR creation)
- Language-specific linters for your project (see `lefthook.yml` comments)

## Workflow

The cycle is always the same: **scaffold** (once) → **plan** → **build** → **review** → repeat.

### Scaffold (new projects only)

```
/projd-create
```

Asks developer-or-vibes, clones the template, and configures everything. Developers make every decision; vibes mode auto-fills. Or copy the template and run `./setup.sh` yourself.

### Plan

```
/projd-plan "A REST API with user auth, a todo CRUD, and a dashboard"
```

Breaks requirements into feature files in `progress/` with acceptance criteria and dependency ordering. Works the same for a brand-new project or adding features to an existing one. Nothing gets built yet.

### Build

```
/projd-hands-on              # one feature at a time, you review each step
/projd-hands-off             # parallel agents, each in its own worktree
/projd-hands-off --dry-run   # preview what would be dispatched
```

**Hands-on**: picks the highest-priority unblocked feature, creates a branch, implements, commits incrementally, pushes, and opens a PR.

**Hands-off**: launches up to `max_agents` (default 20) parallel agents on independent features. Each gets its own worktree and branch. If `auto_review` is enabled, a reviewer agent checks each PR and merges passing ones automatically.

Sessions pick up where they left off -- `HANDOFF.md` preserves context between sessions, and features track their own status and dependencies.

### Review and repeat

Merge PRs. Run `/projd-plan` again when new work comes in. If something goes sideways, check `progress/` for status, use the branch's commit history for rollback, or reset a feature to `pending` to retry.

## What's Included

| File | Purpose |
|------|---------|
| `CLAUDE.md` | Agent instructions: session protocol, git controls, feature workflow |
| `agent.json` | Git policy and dispatch config (branch protection, push control, parallel limits, auto-review) |
| `progress/` | Per-feature tracking files with acceptance criteria and status |
| `setup.sh` | Interactive wizard to configure the boilerplate for your language |
| `scripts/validate.sh` | Verify the boilerplate was configured correctly |
| `scripts/init.sh` | Environment bootstrap (dependencies, git hooks) |
| `scripts/smoke.sh` | Fast lint + typecheck verification |
| `scripts/status.sh` | Git state, feature progress, and handoff context at a glance |
| `scripts/statusline.sh` | Claude Code status line: feature progress, agent count, context usage |
| `scripts/monitor.sh` | Live progress dashboard for parallel agent sessions |
| `lefthook.yml` | Pre-commit hooks (lint + typecheck) and pre-push guard |
| `.claude/settings.json` | Claude Code hook and status line configuration |
| `.claude/hooks/` | Git policy enforcement hook |
| `.claude/skills/` | projd skill family (plan, pick, start, end, dispatch, create-new) |
| `scripts/install-skill.sh` | Install the `/projd-create` scaffolding skill to `~/.claude/skills/` |

## Setup

### Interactive wizard

```bash
cp -r projd/ my-new-project/
cd my-new-project/
git init
chmod +x setup.sh scripts/*.sh
./setup.sh                                           # interactive
./setup.sh --name my-app --lang go --desc "My app"   # or scripted
```

Supported languages with built-in template blocks: `typescript`, `go`, `python`, `swift`, `kotlin`. Any language is accepted -- unsupported ones skip template activation.

### Scaffolding skill (recommended for repeat use)

Install the `/projd-create` skill once, then create new projects from any Claude Code session:

```bash
./scripts/install-skill.sh   # from the template repo (one-time)
```
```
/projd-create                 # from any Claude Code session
```

The skill asks developer-or-vibes, clones the latest template, runs setup, and either interviews you (developer) or auto-fills everything (vibes) to produce a complete CLAUDE.md. It can optionally scan for similar open-source projects for inspiration. When it finishes, the project is ready for `/projd-plan`.

```bash
./scripts/install-skill.sh --check   # show diff if skill changed
./scripts/install-skill.sh --remove  # uninstall the skill
```

## Skills

| Skill | Purpose |
|-------|---------|
| `/projd-plan <requirements>` | Break requirements into feature files. Optionally researches existing solutions for inspiration. Does not implement. |
| `/projd-hands-on [feature-id]` | Select a feature, create branch, present acceptance criteria. You stay in the loop. |
| `/projd-hands-off [--dry-run]` | Launch parallel agents on independent features. Optional auto-review merges passing PRs. |
| `/projd-create [name]` | Scaffold a new project from the template (user-level, install with `install-skill.sh`). |
| `projd-start` | Agent orientation at session start (auto-triggered). |
| `projd-end` | Session wrap-up: commit, push, PR (auto-triggered). |

## Feature Schema

Each feature is a JSON file in `progress/`. The filename should match the `id` (e.g., `progress/user-auth.json`).

```json
{
  "id": "user-auth",
  "name": "User Authentication",
  "description": "JWT-based login and registration with email/password.",
  "acceptance_criteria": [
    "POST /auth/register creates a user and returns a JWT",
    "POST /auth/login returns a JWT for valid credentials, 401 for invalid",
    "Protected routes return 401 without a valid token"
  ],
  "priority": 1,
  "status": "pending",
  "branch": "",
  "blocked_by": [],
  "notes": ""
}
```

### Writing good features

- **Independently shippable**: Each feature should leave the codebase in a working state even if the next feature never gets built.
- **Observable criteria**: "returns a 200" not "is well-designed." Things you can verify by running a command or hitting an endpoint.
- **One session scope**: If a feature is too big for one session, split it into smaller features and use `blocked_by` to order them.
- **Explicit dependencies**: If feature B requires feature A's code to exist, add `"blocked_by": ["feature-a"]`. This lets agents and operators see what can be parallelized.

## Agent Controls

`agent.json` defines what agents are allowed to do:

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

| Field | Default | Effect |
|-------|---------|--------|
| `git.branch_prefix` | `"agent/"` | All agent-created branches must start with this prefix |
| `git.protected_branches` | `["main", "master"]` | Agent must never commit directly to these branches |
| `git.allow_push` | `"feature"` | `false`: no pushing. `"feature"`: push only branches with the configured prefix. `true`: push anything. |
| `git.allow_force_push` | `false` | If false, `--force` push is blocked |
| `git.auto_commit` | `true` | If true, agent commits incrementally. If false, agent stages changes but the operator commits. |
| `dispatch.max_agents` | `20` | Maximum parallel agents spawned by `/projd-hands-off`. Dispatches in waves if more features are eligible. |
| `dispatch.auto_review` | `false` | If true, a reviewer agent auto-reviews each PR: runs smoke tests, verifies acceptance criteria, fixes issues, and merges passing PRs. |

These rules are enforced at two layers. The primary enforcement is a Claude Code **PreToolUse hook** (`.claude/hooks/check-git-policy.sh`) that intercepts every bash command and blocks violations before they execute. A secondary **pre-push hook** via Lefthook guards against direct `git push` usage outside of Claude Code. See [docs/hooks.md](docs/hooks.md) for details.

## Session Continuity

Long-running work often spans multiple sessions. projd handles this through `HANDOFF.md`:

- When a session ends with incomplete work, `projd-end` writes a `HANDOFF.md` to the project root with what was accomplished, current state, and prioritized next steps.
- When the next session starts, `projd-start` reads `HANDOFF.md` and orients the agent with full context from where the previous session left off.
- When a feature is completed, `HANDOFF.md` is deleted -- there's nothing to hand off.

`HANDOFF.md` is ephemeral (listed in `.gitignore`). It exists only between sessions and is never committed.

## Parallel Agents

`/projd-hands-off` reads `dispatch.max_agents` from `agent.json` (default **20**). If more features are eligible than the limit, they are dispatched in waves -- the next batch starts after the current one completes. Each agent runs in its own git worktree with its own feature branch, so there are no write conflicts.

When `dispatch.auto_review` is `true`, a reviewer agent is spawned for each completed PR. The reviewer runs smoke tests, verifies acceptance criteria, and merges passing PRs. If it finds issues, it fixes trivial ones inline and spawns a subagent for larger fixes. PRs that still fail after fixes are flagged for manual review.

Use `--dry-run` to preview which features would be dispatched and in what order before committing to a run.

## Monitoring

### Status line

The Claude Code status line shows feature progress at a glance, updated after every assistant message:

```
Opus 4.6  main  42%  |  3/7  2 wip  |  2 agents  |  15.2k/4.8k tok  +156/-23  12m
```

It reads `progress/*.json` files and counts active git worktrees, so when parallel agents update feature status or create/remove worktrees, the status line reflects it on the next refresh. The status line is configured in `.claude/settings.json` and powered by `scripts/statusline.sh`.

### Monitor script

For a detailed live view, run the monitor from another terminal:

```bash
./scripts/monitor.sh            # one-time snapshot
./scripts/monitor.sh --watch    # auto-refresh every 5 seconds
./scripts/monitor.sh --watch 3  # auto-refresh every 3 seconds
```

The monitor shows a progress bar, per-feature status table, active worktrees with branches, and open PRs from agent branches. It's useful alongside `/projd-hands-off` to watch agents work in real time.

## Verifying Your Setup

After running `setup.sh`, use the validation script to check that everything was configured correctly:

```bash
./scripts/validate.sh            # check configuration
./scripts/validate.sh --strict   # also run smoke tests
```

This checks that `CLAUDE.md` is filled in, `agent.json` is valid, `lefthook.yml` has active hooks, `smoke.sh` has active checks, and feature files (if any) have valid schemas. Failures block; warnings are advisory.

## Bootstrapping the Environment

```bash
./scripts/init.sh
```

This installs Lefthook git hooks, makes Claude Code hook scripts executable, and installs language-specific dependencies (e.g., `npm install`, `go mod download`, `pip install` in a venv). It's idempotent -- safe to re-run. For multi-project workspaces, it bootstraps each sub-project automatically.

## Documentation

| Document | Purpose |
|----------|---------|
| [Multi-Project Workspaces](docs/multi-project.md) | Setting up monorepos and microservice workspaces with `projects.json` |
| [Hook Architecture](docs/hooks.md) | How git policy enforcement works (PreToolUse hook + Lefthook pre-push) |
| [Contributing](CONTRIBUTING.md) | How to set up a development environment, project structure, and contribution guidelines |

## Landscape

This space is moving fast. Here's how projd compares to other open-source tools for orchestrating AI coding agents. The table focuses on capabilities that matter for structured, multi-session development work -- not benchmarks or model support breadth.

### Comparison

| | projd | [Spec Kit](https://github.com/github/spec-kit) | [Agent Orchestrator](https://github.com/ComposioHQ/agent-orchestrator) | [Kagan](https://github.com/kagan-sh/kagan) | [Emdash](https://github.com/generalaction/emdash) | [Claude Squad](https://github.com/smtg-ai/claude-squad) | [dmux](https://github.com/standardagents/dmux) | [Plandex](https://github.com/plandex-ai/plandex) | [Claude Agent Teams](https://docs.claude.ai/en/docs/agent-teams) |
|---|---|---|---|---|---|---|---|---|---|
| **Approach** | Project template | Spec-driven CLI toolkit | Platform | TUI daemon | Desktop app | Terminal multiplexer | Terminal multiplexer | Single agent CLI | Built-in feature |
| **Parallel agents** | Yes (worktrees, configurable limit) | No | Yes (30+ worktrees) | Yes (14+ agents) | Yes (worktrees) | Yes (tmux sessions) | Yes (tmux + worktrees) | No | Yes (worktrees) |
| **Feature planning** | JSON files with acceptance criteria | Specs + plans + task breakdown | Backlog management | Kanban board | Kanban + issue tracker sync | No | No | Plan versioning | No |
| **Dependency tracking** | `blocked_by` fields | Task ordering | Yes | No | No | No | No | No | No |
| **Git policy enforcement** | PreToolUse hook + Lefthook | No | Partial | No | No | No | Pre/post-merge hooks | No | No |
| **Session handoff** | `HANDOFF.md` between sessions | No | No | No | No | No | No | No | No |
| **Quality gates** | Smoke tests + pre-commit hooks | Extension-based (Verify, Review) | CI auto-fix | Code review flow | No | No | Hook support | Diff sandbox | No |
| **Auto PR creation** | Yes (+ optional auto-review/merge) | No | Yes | Yes | No | No | No | No | No |
| **Agent support** | Claude Code | 25+ agents | Claude Code, Codex, Aider, etc. | 14+ agents | 18+ agents | Claude Code, Codex, Aider, etc. | 11+ agents | Any LLM | Claude Code only |
| **Interface** | CLI + files | CLI + spec files | Dashboard + CLI | TUI (keyboard-first) | macOS/Linux desktop | TUI | tmux panes | CLI | CLI |
| **Install model** | Clone template, run `setup.sh` | `uv tool install` | `npm install` | `brew install` / binary | Download app | `go install` | `go install` | `brew install` | Built into Claude Code |

### Where projd fits

**projd is a project template, not a platform.** You clone it, configure it once, and the structure lives inside your repo alongside your code. There's nothing to install globally, no daemon to run, no desktop app to keep open. The trade-off is that it's opinionated about Claude Code and doesn't support other agents.

What projd does that most alternatives don't:

- **Git policy enforcement at the hook level.** The PreToolUse hook intercepts commands before they execute. The agent cannot bypass branch protection, push to the wrong branch, or force-push. Most orchestrators trust the agent or rely on CI after the fact.
- **Session continuity via `HANDOFF.md`.** When a session ends with incomplete work, structured handoff notes preserve context for the next session. Most tools assume continuous operation or rely on chat history.
- **Feature files with `blocked_by` dependencies.** Features declare their dependencies explicitly. The dispatcher won't start a feature until its blockers are complete. This prevents out-of-order execution in parallel runs.
- **Smoke tests as a completion gate.** A feature isn't marked complete until lint, typecheck, and tests pass. This is enforced by the skill, not left to the agent's judgment.

What projd doesn't do that some alternatives do:

- **Multi-agent CLI support.** projd works with Claude Code only. If you use Codex, Aider, or other agents, look at Spec Kit, Agent Orchestrator, dmux, or Kagan.
- **GUI/TUI for monitoring.** projd is file-driven. If you want a visual dashboard, Emdash, Kagan, or Superset provide that.
- **Autonomous CI remediation.** Agent Orchestrator can detect CI failures and spawn agents to fix them. projd stops at "smoke tests failed, feature not marked complete."
- **Scale beyond dozens of agents.** projd defaults to 20 parallel agents (configurable via `dispatch.max_agents`). If you need 30+, Agent Orchestrator or Ruflo are built for that.

### Other tools worth knowing about

These aren't direct competitors but occupy adjacent space:

| Tool | What it does | Relevance |
|------|-------------|-----------|
| [Aider](https://github.com/Aider-AI/aider) | AI pair programming with auto-commits | Strong single-agent git integration; could run under an orchestrator |
| [OpenHands](https://github.com/OpenHands/OpenHands) | Autonomous agent in sandboxed cloud environments | Different execution model (cloud sandbox vs. local worktree) |
| [Cline](https://github.com/cline/cline) | VS Code agent with subagent support | IDE-native approach; subagents provide some parallelism |
| [Codex CLI](https://github.com/openai/codex) | OpenAI's terminal coding agent | Subagent workflows for parallelization, but no lifecycle tracking |
| [Goose](https://github.com/block/goose) | Extensible AI agent by Block | Autonomous single agent; MCP integration |
| [SWE-agent](https://github.com/SWE-agent/SWE-agent) | Automated issue fixing for benchmarks | Research-oriented; solves issues, not feature development |
| [GPT-Pilot](https://github.com/Pythagora-io/gpt-pilot) | Multi-role agent system (architect, developer, reviewer) | Specialized roles within a single task vs. parallel features |
| [Worktrunk](https://github.com/max-sixty/worktrunk) | Git worktree management CLI | Pure infrastructure; one piece of what projd bundles |

*This landscape was last reviewed in March 2026. If something is missing or wrong, open an issue.*

## Troubleshooting

**`setup.sh` fails or lefthook not found**
Install prerequisites first: `brew install lefthook jq gh`. Then re-run `./scripts/init.sh`.

**Smoke tests fail before I've written any code**
The template ships with placeholder commands. Run `setup.sh` to activate the correct language blocks, or manually edit `lefthook.yml` and `scripts/smoke.sh` to match your toolchain.

**Hook blocks a git command I expected to work**
The PreToolUse hook reads `agent.json` on every command. Check that `branch_prefix`, `allow_push`, and `protected_branches` match your intent. You can inspect the hook logic in `.claude/hooks/check-git-policy.sh`.

**Agent creates a branch without the prefix**
The hook enforces the prefix from `agent.json`. If the prefix was changed after the branch was created, the push will be blocked. Rename the branch: `git branch -m old-name agent/new-name`.

**`/projd-create` says placeholders not replaced**
Run `./scripts/install-skill.sh` from the template repo first. It bakes in your repo's remote URL and local path so the skill knows where to clone from.

**Feature stuck in `in_progress`**
If a session ended without running `projd-end`, the feature file won't have been updated. Manually set `"status": "pending"` and clear the `"branch"` field in the feature's JSON file to retry, or set `"status": "complete"` if the work was actually finished.

**`gh pr create` fails**
Ensure you're authenticated: `gh auth status`. The agent will still push the branch even if PR creation fails -- you can create the PR manually from GitHub.
