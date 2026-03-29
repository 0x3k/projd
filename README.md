# projd

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Built for Claude Code](https://img.shields.io/badge/Built_for-Claude_Code-6B5CE7)](https://claude.ai/code)

**Project Daemon** -- pronounced "prodigy" `/ˈprɒdɪdʒi/` by some. We don't correct them.

> A project harness for long-running and parallel AI agent sessions. You describe what you want, projd breaks it into features, and Claude builds them -- one at a time or several in parallel. You review PRs. That's the whole deal.

Claude Code works great in a single sitting. But when sessions get long or you want multiple agents working at once, things fall apart -- the agent loses context, commits to branches it shouldn't, starts work that conflicts with other agents, and leaves half-finished code behind.

projd adds the missing pieces: session continuity, git guardrails, a feature lifecycle with dependency tracking, and branch-per-feature isolation so agents don't step on each other.

**What you get:**

- **Feature planning**
  Break requirements into feature files with acceptance criteria and dependency ordering.

- **Branch-per-feature isolation**
  Each agent works in its own git worktree. No conflicts.

- **Git policy enforcement**
  PreToolUse hooks block violations before they execute, not after.

- **Parallel dispatch**
  Up to 20 agents in dependency-aware waves, with optional auto-review.

- **Session continuity**
  Structured `HANDOFF.md` preserves context between sessions.

- **Smoke-test gates**
  Features aren't marked complete until lint, typecheck, and tests pass.

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

Run `./scripts/monitor.sh` in a second terminal for a live dashboard -- progress bars, per-feature token tracking, and keyboard shortcuts to act on features directly. See [Parallel Agents](docs/parallel-agents.md) for details.

---

### Quick Start

**Prerequisites:**

| Tool | Install |
|------|---------|
| [Claude Code](https://claude.ai/code) | See [claude.ai/code](https://claude.ai/code) |
| [Lefthook](https://github.com/evilmartians/lefthook) | `brew install lefthook` |
| [jq](https://jqlang.github.io/jq/) | `brew install jq` |
| [gh](https://cli.github.com/) | `brew install gh` |

Full guide: [Setup](docs/setup.md)

**One-line install** (from anywhere):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/0x3k/projd/main/scripts/remote-install.sh)
```

Or from a local clone:

```bash
./scripts/install-skill.sh
```

This installs `/projd-create` and `/projd-adopt` to `~/.claude/skills/`. Skills auto-update once per day when invoked.

```
/projd-create                 # scaffold a new project from any Claude Code session
/projd-adopt                  # add projd to an existing project
/projd-plan "your idea"       # break it into features
/projd-hands-on               # build one feature at a time
/projd-hands-off              # or launch parallel agents
```

**Next steps:** Check the PRs it created. Read [Features](docs/features.md) for the feature file format, and [Agent Controls](docs/agent-controls.md) to tune git policy and dispatch behavior.

### Adding projd to an existing project

Already have a working codebase? Use `/projd-adopt` instead of `/projd-create`:

```
cd your-existing-project
/projd-adopt
```

The skill copies infrastructure files (skills, hooks, scripts), merges your existing `.claude/settings.json` and `CLAUDE.md` non-destructively, creates `agent.json`, and sets up the `progress/` directory. It supports both developer and vibes modes. See [Setup](docs/setup.md) for details.

### How it works

```
  /projd-plan "requirements"
          |
          v
  progress/*.json (feature files)
          |
    +-----+------+
    |            |
hands-on    hands-off
    |            |
    v            v
 1 agent    N agents
 you watch   in parallel
    |            |
    v            v
   PRs         PRs
    |            |
    +-----+------+
          |
    +-----+------+
    |            |
you review   reviewer agent
  + merge    (vibes mode)
    |            |
    +-----+------+
          |
     /projd-plan (repeat)
```

**Hands-on** -- you stay in the loop with one agent:

```
  YOU                AGENT
   |                   |
   |  /projd-hands-on  |
   |------------------>|
   |                   |  reads HANDOFF.md
   |                   |  runs smoke tests
   |                   |  implements feature
   |                   |  commits + pushes
   |     PR ready      |
   |<------------------|
   |                   |
   |  review + merge   |
   |  next feature     |
   |------------------>|
   :     (repeat)      :
```

**Hands-off** -- agents work in parallel, you review at the end:

```
  YOU             DISPATCHER           AGENTS
   |                  |                  |
   |  /projd-hands-off|                  |
   |----------------->|                  |
   |                  |  wave 1          |
   |                  |----------------->|  agent/feature-a (worktree)
   |                  |----------------->|  agent/feature-b (worktree)
   |                  |                  |
   |                  |  blockers done   |
   |                  |  wave 2          |
   |                  |----------------->|  agent/feature-c (worktree)
   |                  |                  |
   |    PRs ready     |                  |
   |<-----------------|                  |
   |                  |                  |
   |  review + merge  |                  |
```

**Hands-off with vibes mode** (`auto_review: true`) -- fully autonomous. A reviewer agent checks each PR, fixes issues, and merges passing ones without you:

```
  YOU             DISPATCHER           AGENTS            REVIEWER
   |                  |                  |                  |
   |  /projd-hands-off|                  |                  |
   |----------------->|                  |                  |
   |                  |  wave 1          |                  |
   |                  |----------------->|  feature-a       |
   |                  |----------------->|  feature-b       |
   |                  |                  |                  |
   |                  |    PR ready      |                  |
   |                  |                  |----------------->|
   |                  |                  |   smoke tests    |
   |                  |                  |   check criteria |
   |                  |                  |                  |
   |                  |                  |   pass? merge    |
   |                  |                  |<-- auto-merged --|
   |                  |                  |                  |
   |                  |                  |   fail? fix+retry|
   |                  |                  |   still fail?    |
   |  flagged for you |                  |   flag for human |
   |<----------------------------------------------------- |
   |                  |                  |                  |
   |                  |  wave 2 begins   |                  |
   |                  |  (blockers merged)|                 |
   |                  |----------------->|  feature-c       |
```

Set `"auto_review": true` in `agent.json` to enable vibes mode. The reviewer runs smoke tests, verifies acceptance criteria, and merges passing PRs. If it finds issues, it fixes trivial ones inline and spawns a subagent for larger fixes. PRs that still fail after fixes are flagged for manual review.

Each agent reads `HANDOFF.md` for prior context, implements against acceptance criteria, runs smoke tests, and creates a PR. `/projd-plan` again when new work comes in.

<details>
<summary><strong>Docs</strong></summary>

| Topic | Link |
|-------|------|
| Setup | [docs/setup.md](docs/setup.md) |
| Skills | [docs/skills.md](docs/skills.md) |
| Features | [docs/features.md](docs/features.md) |
| Agent Controls | [docs/agent-controls.md](docs/agent-controls.md) |
| Parallel Agents | [docs/parallel-agents.md](docs/parallel-agents.md) |
| Hooks | [docs/hooks.md](docs/hooks.md) |
| Multi-Project | [docs/multi-project.md](docs/multi-project.md) |
| Troubleshooting | [docs/troubleshooting.md](docs/troubleshooting.md) |
| Contributing | [CONTRIBUTING.md](CONTRIBUTING.md) |

</details>

---

## What's Included

| Path | Purpose |
|------|---------|
| `CLAUDE.md` | Agent instructions: session protocol, git controls, feature workflow |
| `agent.json` | Git policy and dispatch config (branch protection, push control, parallel limits) |
| `progress/` | Per-feature tracking files with acceptance criteria, dependencies, and status |
| `scripts/` | Setup, validation, smoke tests, monitoring, status line, environment bootstrap |
| `.claude/hooks/` | Git policy enforcement (PreToolUse hook blocks violations before they execute) |
| `.claude/skills/` | The projd skill family: plan, hands-on, hands-off, create, adopt, start, end |
| `lefthook.yml` | Pre-commit hooks (lint + typecheck) and pre-push guard |
| `setup.sh` | Interactive wizard to configure the template for your language and project |

## Parallel Agents

`/projd-hands-off` dispatches parallel agents on independent features. Each gets its own git worktree and branch.

```
progress/*.json
      |
      v
  +---+---+---+         +---+---+
  | Wave 1    |         | Wave 2 |    (blocked_by resolved)
  +-----------+         +--------+
  | user-auth | ------> | todo   |
  | api-docs  |         | crud   |
  +-----------+         +--------+
      |                     |
      v                     v
  2 PRs created         1 PR created
```

Features with `blocked_by` dependencies are scheduled in waves -- wave 2 starts only after its blockers complete.

With **vibes mode** (`"auto_review": true` in `agent.json`), the loop closes itself -- a reviewer agent checks each PR, fixes what it can, and merges passing ones automatically. You only get pulled in when something fails twice.

> [!TIP]
> Use `--dry-run` to preview dispatch order before committing to a run.

See [Parallel Agents](docs/parallel-agents.md) for the full dispatch protocol, monitor dashboard, and configuration options.

## Monorepo / Multi-Project

Add a `projects.json` at the root and each sub-project becomes its own projd instance -- own `CLAUDE.md`, `progress/`, and scripts. Agents work across sub-projects in parallel, and root-level features handle cross-cutting work.

```
  projects.json
       |
       +-- services/api/          (own CLAUDE.md, progress/, scripts)
       |     +-- feature-a  -->  agent in worktree
       |     +-- feature-b  -->  agent in worktree
       |
       +-- services/worker/       (own CLAUDE.md, progress/, scripts)
       |     +-- feature-c  -->  agent in worktree
       |
       +-- root progress/         (cross-cutting features)
             +-- feature-d  -->  agent in worktree
```

Root scripts (`status.sh`, `smoke.sh`, `init.sh`) automatically aggregate across all sub-projects. See [Multi-Project](docs/multi-project.md) for setup details.

## Landscape

**projd is a project template, not a platform.** You clone it, configure it once, and the structure lives inside your repo alongside your code. Nothing to install globally, no daemon, no desktop app. The trade-off: it's opinionated about Claude Code and doesn't support other agents.

What projd does that most alternatives don't:

| Capability | How |
|------------|-----|
| **Git policy enforcement** | PreToolUse hook intercepts commands before they execute -- the agent cannot bypass branch protection |
| **Session continuity** | Structured `HANDOFF.md` preserves context between sessions instead of relying on chat history |
| **Dependency-aware dispatch** | Features declare `blocked_by` dependencies; the dispatcher schedules waves and won't start blocked work |
| **Smoke-test gates** | A feature isn't complete until lint, typecheck, and tests pass -- enforced by the skill, not judgment |

See [Landscape](docs/landscape.md) for a detailed comparison with Spec Kit, Agent Orchestrator, Kagan, Emdash, Claude Squad, dmux, Plandex, and others.

---

Based on patterns from [Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents). MIT License -- see [LICENSE](LICENSE).
