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

## Workflow: New Project

You have an idea. You want a project that exists and works. Here's how that happens.

**1. Scaffold it**

If you've installed the scaffolding skill (see [Setup](#setup)), just open Claude Code anywhere and run:

```
/projd-create
```

It asks for a name, language, and description. It clones the template, configures everything, interviews you about build commands and architecture, and commits. You now have a fully configured project directory. No manual file editing, no copy-paste ceremonies.

Alternatively, copy the template and run `./setup.sh` yourself. It's interactive. It won't judge you.

**2. Plan it**

Open Claude Code in your new project and describe what you want to build:

```
/projd-plan "A REST API with user auth, a todo CRUD, and a dashboard"
```

Claude reads your requirements, breaks them into discrete features with acceptance criteria and dependency ordering, and writes them as JSON files in `progress/`. You review the plan. Nothing gets built yet -- this is the "measure twice" step.

**3. Build it**

Pick a feature and let the agent loose:

```
/projd-hands-on
```

This grabs the highest-priority unblocked feature, creates a branch, and presents the acceptance criteria. The agent orients itself, implements the feature, runs smoke tests, commits incrementally, pushes the branch, and opens a PR. You review it, merge it, and move on.

If you have multiple independent features and you're feeling ambitious:

```
/projd-hands-off
```

This launches parallel agents, each in its own isolated worktree, each working on a separate feature. They don't step on each other. They each open their own PR. You merge at your leisure.

**4. Repeat**

Pick the next feature. Or plan more features. The cycle is: plan, pick, build, review. Features track their own status and dependencies, so you always know what's done, what's in progress, and what's next.

## Workflow: Adding Features to an Existing Project

You already have a projd project. Something new needs to exist. Maybe a user asked for it. Maybe you woke up at 3am with an idea. Either way:

**1. Plan the work**

```
/projd-plan "Add WebSocket support for real-time notifications"
```

Claude looks at your existing codebase, understands what's already there, and breaks the new work into features that build on top of it. Dependencies are set automatically -- if the notification feature needs a message queue feature first, that gets expressed in `blocked_by`.

**2. Build it**

Same as before:

```
/projd-hands-on    # one feature at a time, you review each step
/projd-hands-off   # or several at once, tests keep them honest
```

The agent reads the existing code, the feature's acceptance criteria, and any handoff notes from previous sessions. It picks up where things left off. Each feature is a branch, each branch becomes a PR. Your main branch stays clean throughout.

**3. That's it**

There is no step 3. If something goes sideways, check `progress/` to see what's done, look at the branch's commit history for granular rollback points, and reset the feature to `pending` to retry. The codebase is always in a mergeable state because projd commits incrementally and never leaves half-finished work on a branch.

## What's Included

| File | Purpose |
|------|---------|
| `CLAUDE.md` | Agent instructions: session protocol, git controls, feature workflow |
| `agent.json` | Git permission boundaries (branch protection, push control) |
| `progress/` | Per-feature tracking files with acceptance criteria and status |
| `setup.sh` | Interactive wizard to configure the boilerplate for your language |
| `scripts/validate.sh` | Verify the boilerplate was configured correctly |
| `scripts/init.sh` | Environment bootstrap (dependencies, git hooks) |
| `scripts/smoke.sh` | Fast lint + typecheck verification |
| `scripts/status.sh` | Git state, feature progress, and handoff context at a glance |
| `lefthook.yml` | Pre-commit hooks (lint + typecheck) and pre-push guard |
| `.claude/settings.json` | Claude Code hook configuration |
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

The skill clones the latest template, runs setup non-interactively, and interviews you to fill in the full CLAUDE.md. When it finishes, the project is ready for `/projd-plan`.

```bash
./scripts/install-skill.sh --check   # show diff if skill changed
./scripts/install-skill.sh --remove  # uninstall the skill
```

## Skills

| Skill | Purpose |
|-------|---------|
| `/projd-plan <requirements>` | Break requirements into feature files. Does not implement. |
| `/projd-hands-on [feature-id]` | Select a feature, create branch, present acceptance criteria. You stay in the loop. |
| `/projd-hands-off [--dry-run]` | Launch parallel agents on independent features. Tests are the quality gate. |
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

`agent.json` defines what the agent is allowed to do with git:

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

| Field | Default | Effect |
|-------|---------|--------|
| `branch_prefix` | `"agent/"` | All agent-created branches must start with this prefix |
| `protected_branches` | `["main", "master"]` | Agent must never commit directly to these branches |
| `allow_push` | `"feature"` | `false`: no pushing. `"feature"`: push only branches with the configured prefix. `true`: push anything. |
| `allow_force_push` | `false` | If false, `--force` push is blocked |
| `auto_commit` | `true` | If true, agent commits incrementally. If false, agent stages changes but the operator commits. |
