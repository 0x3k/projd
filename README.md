# projd

[![npm version](https://img.shields.io/npm/v/@0spoon/projd)](https://www.npmjs.com/package/@0spoon/projd)
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
  Structured `.projd/HANDOFF.md` preserves context between sessions.

- **Smoke-test gates**
  Features aren't marked complete until lint, typecheck, and tests pass.

### What it looks like

```
$ /projd-plan "A CLI tool for managing dev environments with Docker"

  Created 7 features in .projd/progress/:
    1. config-loader       Parse YAML config with validation and defaults
    2. env-lifecycle       Create, start, stop, destroy environments
    3. docker-backend      Docker container management (blocked by: config-loader)
    4. template-engine     Project templates with variable substitution (blocked by: config-loader)
    5. port-forwarding     Automatic port mapping and conflict detection (blocked by: docker-backend)
    6. shell-completions   Bash/zsh/fish completions (blocked by: env-lifecycle)
    7. status-dashboard    Live TUI showing running environments (blocked by: docker-backend)

$ /projd-hands-off --dry-run

  Dispatch plan (max_agents: 20):
    Wave 1: config-loader, env-lifecycle                        (2 agents)
    Wave 2: docker-backend, template-engine, shell-completions  (3 agents)
    Wave 3: port-forwarding, status-dashboard                   (2 agents)

  7 features, 3 waves. Run without --dry-run to start.

$ /projd-hands-off

  Dispatching wave 1...
    [config-loader]  worktree created   branch: agent/config-loader
    [env-lifecycle]  worktree created   branch: agent/env-lifecycle

  Wave 1 complete. Dispatching wave 2...
    [docker-backend]     worktree created   branch: agent/docker-backend
    [template-engine]    worktree created   branch: agent/template-engine
    [shell-completions]  worktree created   branch: agent/shell-completions

  Wave 2 complete. Dispatching wave 3...
    [port-forwarding]    worktree created   branch: agent/port-forwarding
    [status-dashboard]   worktree created   branch: agent/status-dashboard

  7/7 features complete. 7 PRs ready for review.
```

Run `./.projd/scripts/monitor.sh` in a second terminal for a live dashboard -- progress bars, per-feature token tracking, and keyboard shortcuts to act on features directly. See [Parallel Agents](docs/parallel-agents.md) for details.

---

### When to use projd

| Scenario | Why projd helps |
|----------|----------------|
| **Greenfield build from a spec** | You have requirements. projd decomposes them into features, builds them in parallel, and you review PRs. A weekend project that would take a week of sequential sessions. |
| **Adding a major capability to an existing app** | `/projd-adopt` + `/projd-plan`. The dependency graph ensures new features build on each other correctly. Agents can't break what's already working because smoke tests gate completion. |
| **Batch of independent improvements** | 8 features on your backlog, none depend on each other. `/projd-hands-off` builds all 8 in parallel. You merge the PRs. |
| **Multi-service monorepo** | `projects.json` gives each service its own progress tracker. Agents work across services in parallel without conflicts. |

projd is overkill for single-feature bug fixes, quick scripts, or exploratory "I don't know what I want yet" sessions. Just use Claude Code directly for those.

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

**Install with npm/pnpm** (from anywhere):

```bash
npx @0spoon/projd
# or
pnpm dlx @0spoon/projd
```

**Or with curl** (from anywhere):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/0spoon/projd/main/.projd/scripts/remote-install.sh)
```

**Or from a local clone:**

```bash
./.projd/scripts/install-skill.sh
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

The skill copies infrastructure files (skills, hooks, scripts), merges your existing `.claude/settings.json` and `CLAUDE.md` non-destructively, creates `.projd/agent.json`, and sets up the `.projd/progress/` directory. It supports both developer and vibes modes. See [Setup](docs/setup.md) for details.

### How it works

```
  /projd-plan "requirements"
          |
          v
  .projd/progress/*.json (feature files)
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

**Hands-on** -- you stay in the loop with one agent. You pick a feature, the agent implements it, you review the PR and start the next one. Good for when you want to steer.

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

Set `"auto_review": true` in `.projd/agent.json` to enable vibes mode. The reviewer runs smoke tests, verifies acceptance criteria, and merges passing PRs. If it finds issues, it fixes trivial ones inline and spawns a subagent for larger fixes. PRs that still fail after fixes are flagged for manual review.

Each agent reads `.projd/HANDOFF.md` for prior context, implements against acceptance criteria, runs smoke tests, and creates a PR. `/projd-plan` again when new work comes in.

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
| `CLAUDE.md` | Project knowledge: overview, build commands, architecture, conventions |
| `.claude/CLAUDE.md` | projd workflow: agent controls, session protocol, feature lifecycle |
| `.projd/agent.json` | Git policy and dispatch config (branch protection, push control, parallel limits) |
| `.projd/progress/` | Per-feature tracking files with acceptance criteria, dependencies, and status |
| `.projd/scripts/` | Setup, validation, smoke tests, monitoring, status line, environment bootstrap |
| `.claude/hooks/` | Git policy enforcement (PreToolUse hook blocks violations before they execute) |
| `.claude/skills/` | The projd skill family: plan, hands-on, hands-off, create, adopt, start, end |
| `lefthook.yml` | Pre-commit hooks (lint + typecheck) and pre-push guard |
| `setup.sh` | Interactive wizard to configure language, project details, and team/solo mode |

## Parallel Agents

`/projd-hands-off` dispatches parallel agents on independent features. Each gets its own git worktree and branch.

```
.projd/progress/*.json
      |
      v
  +-----------+     +----------------+     +-----------+
  | Wave 1    |     | Wave 2         |     | Wave 3    |
  +-----------+     +----------------+     +-----------+
  | config    | --> | docker-backend | --> | port-fwd  |
  | env-life  |     | template-eng   |     | status-ui |
  |           |     | completions    |     |           |
  +-----------+     +----------------+     +-----------+
      |                   |                     |
      v                   v                     v
  2 PRs              3 PRs                 2 PRs
```

Features with `blocked_by` dependencies are scheduled in waves -- each wave starts only after its blockers complete.

With **vibes mode** (`"auto_review": true` in `.projd/agent.json`), the loop closes itself -- a reviewer agent checks each PR, fixes what it can, and merges passing ones automatically. You only get pulled in when something fails twice.

> [!TIP]
> Use `--dry-run` to preview dispatch order before committing to a run.

See [Parallel Agents](docs/parallel-agents.md) for the full dispatch protocol, monitor dashboard, and configuration options.

## Monorepo / Multi-Project

Add a `projects.json` at the root and each sub-project becomes its own projd instance -- own `CLAUDE.md`, `.projd/progress/`, and `.projd/scripts/`. Agents work across sub-projects in parallel, and root-level features handle cross-cutting work.

```
  projects.json
       |
       +-- services/api/          (own CLAUDE.md, .projd/progress/, .projd/scripts/)
       |     +-- feature-a  -->  agent in worktree
       |     +-- feature-b  -->  agent in worktree
       |
       +-- services/worker/       (own CLAUDE.md, .projd/progress/, .projd/scripts/)
       |     +-- feature-c  -->  agent in worktree
       |
       +-- root .projd/progress/  (cross-cutting features)
             +-- feature-d  -->  agent in worktree
```

Root scripts (`status.sh`, `smoke.sh`, `init.sh`) automatically aggregate across all sub-projects. See [Multi-Project](docs/multi-project.md) for setup details.

## Landscape

**projd is a project template, not a platform.** You clone it, configure it once, and the structure lives inside your repo alongside your code. Nothing to install globally, no daemon, no desktop app. The trade-off: it's opinionated about Claude Code and doesn't support other agents.

What projd does that most alternatives don't:

| Capability | How |
|------------|-----|
| **Git policy enforcement** | PreToolUse hook intercepts commands before they execute -- the agent cannot bypass branch protection |
| **Session continuity** | Structured `.projd/HANDOFF.md` preserves context between sessions instead of relying on chat history |
| **Dependency-aware dispatch** | Features declare `blocked_by` dependencies; the dispatcher schedules waves and won't start blocked work |
| **Smoke-test gates** | A feature isn't complete until lint, typecheck, and tests pass -- enforced by the skill, not judgment |

See [Landscape](docs/landscape.md) for a detailed comparison with Spec Kit, Agent Orchestrator, Kagan, Emdash, Claude Squad, dmux, Plandex, and others.

---

Based on patterns from [Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents). MIT License -- see [LICENSE](LICENSE).
