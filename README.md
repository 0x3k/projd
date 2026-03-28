# projd

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Built for Claude Code](https://img.shields.io/badge/Built_for-Claude_Code-6B5CE7)](https://claude.ai/code)

**Project Daemon** -- pronounced "prodigy" `/ˈprɒdɪdʒi/` by some. We don't correct them.

> A project harness for long-running and parallel AI agent sessions. You describe what you want, projd breaks it into features, and Claude builds them -- one at a time or several in parallel. You review PRs. That's the whole deal.

Claude Code works great in a single sitting. But when sessions get long or you want multiple agents working at once, things fall apart: the agent loses context, commits to branches it shouldn't, starts work that conflicts with other agents, and leaves half-finished code behind. projd adds session continuity, git guardrails, a feature lifecycle with dependency tracking, and branch-per-feature isolation so agents don't step on each other.

### What it looks like

```
$ /projd-plan "A REST API with user auth and todo CRUD"

  Created 3 features in progress/:
    1. user-auth       JWT-based login and registration
    2. todo-crud       CRUD endpoints for todo items (blocked by: user-auth)
    3. api-docs        OpenAPI spec generation

$ /projd-hands-off --dry-run

  Dispatch plan (max_agents: 20):
    Wave 1: user-auth, api-docs      (2 agents, parallel)
    Wave 2: todo-crud                (1 agent, after user-auth completes)

  3 features, 2 waves. Run without --dry-run to start.

$ /projd-hands-off

  Dispatching wave 1...
    [user-auth]  worktree created   branch: agent/user-auth
    [api-docs]   worktree created   branch: agent/api-docs

  Wave 1 complete. Dispatching wave 2...
    [todo-crud]  worktree created   branch: agent/todo-crud

  3/3 features complete. 3 PRs ready for review.
```

Meanwhile, in another terminal:

```
◐ projd monitor  my-app  -- A REST API with auth and todos   14:32:07

  ████████████████░░░░  80%  2 done  1 wip  0 pending  (3 total)  tokens: 245k

  FEATURE                STATE WAVE TOKENS     DETAILS
  user-auth              done  --   82k/14k    agent/user-auth
  api-docs               done  --   45k/8k     agent/api-docs
> todo-crud              wip   w2   71k/12k    agent/todo-crud  writing tests

  2 active worktrees
  2 open PRs

  j/k navigate  d detail  l log  p pr  r reset  c complete  x kill  m merge  q quit
```

---

### Quick Start

> [!NOTE]
> Requires [Claude Code](https://claude.ai/code), [Lefthook](https://github.com/evilmartians/lefthook), [jq](https://jqlang.github.io/jq/), and [gh](https://cli.github.com/). See [Setup](docs/setup.md) for details.

```bash
./scripts/install-skill.sh   # install the scaffolding skill (one-time)
```
```
/projd-create                 # scaffold a new project from any Claude Code session
/projd-plan "your idea"       # break it into features
/projd-hands-on               # build one feature at a time
/projd-hands-off              # or launch parallel agents
```

### How it works

The cycle is always the same: **scaffold** (once) > **plan** > **build** > **review** > repeat.

1. **Scaffold** -- `/projd-create` clones the template, asks developer-or-vibes, and configures everything. Or clone manually and run `./setup.sh`.
2. **Plan** -- `/projd-plan` breaks requirements into feature files in `progress/` with acceptance criteria and dependency ordering. Nothing gets built yet.
3. **Build** -- `/projd-hands-on` picks the highest-priority unblocked feature and walks you through it. `/projd-hands-off` launches parallel agents, each in its own worktree. Sessions pick up where they left off via `HANDOFF.md`.
4. **Review** -- Merge PRs. Run `/projd-plan` again when new work comes in.

---

## Contents

- [What's Included](#whats-included)
- [Parallel Agents](#parallel-agents)
- [Landscape](#landscape)

**Docs:** [Setup](docs/setup.md) | [Skills](docs/skills.md) | [Features](docs/features.md) | [Agent Controls](docs/agent-controls.md) | [Parallel Agents](docs/parallel-agents.md) | [Hooks](docs/hooks.md) | [Multi-Project](docs/multi-project.md) | [Troubleshooting](docs/troubleshooting.md) | [Contributing](CONTRIBUTING.md)

---

## What's Included

| Path | Purpose |
|------|---------|
| `CLAUDE.md` | Agent instructions: session protocol, git controls, feature workflow |
| `agent.json` | Git policy and dispatch config (branch protection, push control, parallel limits) |
| `progress/` | Per-feature tracking files with acceptance criteria, dependencies, and status |
| `scripts/` | Setup, validation, smoke tests, monitoring, status line, environment bootstrap |
| `.claude/hooks/` | Git policy enforcement (PreToolUse hook blocks violations before they execute) |
| `.claude/skills/` | The projd skill family: plan, hands-on, hands-off, create, start, end |
| `lefthook.yml` | Pre-commit hooks (lint + typecheck) and pre-push guard |
| `setup.sh` | Interactive wizard to configure the template for your language and project |

## Parallel Agents

`/projd-hands-off` dispatches up to `max_agents` (default 20) parallel agents on independent features. Each gets its own git worktree and branch. Features with `blocked_by` dependencies are scheduled in waves -- wave 2 starts only after its blockers complete. When `auto_review` is enabled, a reviewer agent checks each PR and merges passing ones automatically.

The Claude Code status line shows progress at a glance:

```
Opus 4.6  main  42%  |  3/7  2 wip  |  2 agents  |  15.2k/4.8k tok  +156/-23  12m
```

Run `./scripts/monitor.sh` in another terminal for the interactive dashboard shown above -- progress bars, feature table with wave and token tracking, worktree and PR status, and keyboard shortcuts to act on features directly.

> [!TIP]
> Use `--dry-run` to preview which features would be dispatched and in what order before committing to a run.

## Landscape

**projd is a project template, not a platform.** You clone it, configure it once, and the structure lives inside your repo alongside your code. There's nothing to install globally, no daemon to run, no desktop app to keep open. The trade-off is that it's opinionated about Claude Code and doesn't support other agents.

What projd does that most alternatives don't:

- **Git policy enforcement at the hook level.** The PreToolUse hook intercepts commands before they execute -- the agent cannot bypass branch protection, even if it tries.
- **Session continuity via `HANDOFF.md`.** Structured handoff notes preserve context between sessions instead of relying on chat history.
- **Dependency-aware dispatch.** Features declare `blocked_by` dependencies. The dispatcher schedules waves automatically and won't start a feature until its blockers complete.
- **Smoke tests as a completion gate.** A feature isn't marked complete until lint, typecheck, and tests pass. Enforced by the skill, not left to judgment.

See [Landscape](docs/landscape.md) for a detailed comparison with Spec Kit, Agent Orchestrator, Kagan, Emdash, Claude Squad, dmux, Plandex, and others.

---

**Docs:** [Setup](docs/setup.md) | [Skills](docs/skills.md) | [Features](docs/features.md) | [Agent Controls](docs/agent-controls.md) | [Hooks](docs/hooks.md) | [Troubleshooting](docs/troubleshooting.md) | [Contributing](CONTRIBUTING.md)

Based on patterns from [Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents). MIT License -- see [LICENSE](LICENSE).
