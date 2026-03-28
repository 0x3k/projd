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

## Table of Contents

- [Why](#why)
- [Prerequisites](#prerequisites)
- [Workflow: New Project](#workflow-new-project)
- [Workflow: Adding Features](#workflow-adding-features-to-an-existing-project)
- [What's Included](#whats-included)
- [Setup](#setup)
- [Skills](#skills-projd)
- [Feature Schema](#feature-schema)
- [Agent Controls](#agent-controls)
- [Running Sessions](#running-sessions)
- [Multi-Project Workspaces](#multi-project-workspaces)
- [Contributing](#contributing)
- [License](#license)

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

### Option A: Interactive wizard

```bash
cp -r projd/ my-new-project/
cd my-new-project/
git init
chmod +x setup.sh scripts/*.sh
./setup.sh
```

The wizard prompts for project name, language, and description, then:
- Activates the language-specific blocks in `lefthook.yml`, `scripts/smoke.sh`, and `scripts/init.sh`
- Updates the project overview in `CLAUDE.md`
- Removes placeholder/example content
- Runs `scripts/init.sh` and `scripts/validate.sh` to verify

### Option B: Scripted (non-interactive)

```bash
./setup.sh --name my-app --lang typescript --desc "My application"
```

Supported languages: `typescript`, `go`, `python`, `swift`, `kotlin`.

### Option C: Manual

If you prefer to configure by hand:

1. **`CLAUDE.md`** -- Fill in project name, language, build commands, architecture
2. **`lefthook.yml`** -- Uncomment the hooks for your language, delete the `placeholder` command
3. **`scripts/smoke.sh`** -- Uncomment the checks for your language
4. **`scripts/init.sh`** -- Uncomment the dependency block for your language
5. **`agent.json`** -- Adjust git controls to your preference
6. **`progress/`** -- Delete `example-feature.json`, add your real features

Then run `./scripts/init.sh` and `./scripts/validate.sh` to verify.

### Option D: Scaffolding skill (recommended for repeat use)

Install the `/projd-create` skill once, then create new projects from any Claude Code session:

```bash
# From the boilerplate repo:
./scripts/install-skill.sh

# Then, from any Claude Code session:
/projd-create
```

The skill clones the latest boilerplate, runs setup non-interactively, and interviews you to fill in the full CLAUDE.md (build commands, architecture, env vars, key patterns). When it finishes, the project is ready for `/projd-plan` with no manual editing needed.

```bash
# Manage the installed skill:
./scripts/install-skill.sh --check   # show diff if skill changed
./scripts/install-skill.sh --remove  # uninstall the skill
```

### After setup

Regardless of which option you used, you still need to:

1. **Fill in `CLAUDE.md`**: Build & Dev Commands, Architecture, Environment Variables, Key Patterns. The wizard fills in the overview but the technical sections are project-specific.
2. **Add features**: Run `/projd-plan` in Claude Code to create features interactively, or add JSON files to `progress/` manually (see [Feature Schema](#feature-schema)).
3. **Run `./scripts/validate.sh`** to check everything is configured.

## Skills (projd)

The projd skill family automates the agent workflow. Project-scoped skills are available in Claude Code sessions within the project. The scaffolding skill (`/projd-create`) is user-scoped and available everywhere once installed.

### Human-facing skills

| Skill | Purpose |
|-------|---------|
| `/projd-plan <requirements>` | Break requirements into feature files. Does not implement. |
| `/projd-hands-on [feature-id]` | Select a feature, create branch, present acceptance criteria. You stay in the loop. |
| `/projd-hands-off [--dry-run]` | Launch parallel agents on independent features. Tests are the quality gate. |
| `/projd-create [name]` | Scaffold a new project from the template (user-level, install with `install-skill.sh`). |

### Agent-facing skills

These are auto-triggered by Claude (not shown in the `/` menu):

| Skill | Purpose |
|-------|---------|
| `projd-start` | Orient at session start: read state, handoff, smoke test. |
| `projd-end` | Wrap up: commit, update feature, push branch, create PR. |

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

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Unique identifier, used in `blocked_by` references and branch names |
| `name` | string | Human-readable name |
| `description` | string | What the feature does |
| `acceptance_criteria` | string[] | Observable, testable conditions that must all pass |
| `priority` | number | Lower = higher priority. Agents pick the lowest-priority-number pending feature |
| `status` | string | `"pending"`, `"in_progress"`, or `"complete"` |
| `branch` | string | Git branch where work happens (set when work starts) |
| `blocked_by` | string[] | IDs of features that must be `complete` before this one can start |
| `notes` | string | Free-form notes (updated by agent at session end) |

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

### How enforcement works

Three layers:
1. **Hook-based**: A Claude Code PreToolUse hook (`.claude/hooks/check-git-policy.sh`) reads `agent.json` and blocks git commands that violate the policy before they execute. This is the primary enforcement mechanism.
2. **Instruction-based**: `CLAUDE.md` tells the agent to read and follow `agent.json`. The agent complies because it follows its instructions.
3. **Lefthook**: The pre-push hook in `lefthook.yml` provides a secondary guard for git usage outside Claude Code.

### Git command auto-approval

By default, `.claude/settings.json` includes permission rules that auto-approve git commands (`Bash(git *)` and `Bash(cd * && git *)`). This prevents the agent from prompting you on every git operation during the workflow. The policy hook still enforces `agent.json` rules regardless of auto-approval.

If you prefer to review each git command before it runs, remove those entries from the `permissions.allow` array in `.claude/settings.json`.

## Running Sessions

### Single agent

```
/projd-hands-on --> projd-start --> implement --> projd-end --> PR
```

1. Operator runs `/projd-hands-on` to select a feature and create a branch
2. Agent orients via `projd-start` (reads state, handoff, smoke test)
3. Agent implements the feature against acceptance criteria
4. Agent wraps up via `projd-end` (commits, pushes, creates PR)
5. Operator reviews and merges the PR

### Parallel agents

```
/projd-hands-off --> Agent 1 (feature-a) --> PR
                --> Agent 2 (feature-b) --> PR
                --> Agent 3 (feature-c) --> PR
```

1. Operator runs `/projd-hands-off` to launch agents on parallelizable features
2. Each agent gets its own isolated worktree and works independently
3. Each agent creates a PR when its feature is complete
4. Operator reviews and merges PRs

Use `--dry-run` to preview which features would be dispatched.

### Planning sessions

For a new project or large initiative:

1. Operator runs `/projd-plan "requirements description"` (or passes a file path)
2. Claude breaks requirements into features with acceptance criteria and dependencies
3. Operator reviews and confirms the plan
4. Features are written to `progress/`
5. Then: `/projd-hands-on` for single agent, `/projd-hands-off` for parallel

### Recovering from a bad session

- Check `progress/` to see what was marked complete vs. in-progress
- Check `git log` on the feature branch for granular commit history
- `git revert` or `git reset` to a known-good commit
- Run `./scripts/smoke.sh` to confirm the codebase is healthy
- Delete stale `HANDOFF.md` if it contains misleading context
- Reset the feature's status to `pending` to retry from scratch

## Multi-Project Workspaces

For monorepos and multi-service setups, see [docs/multi-project.md](docs/multi-project.md).

## Contributing

Contributions are welcome. Open an issue to discuss what you'd like to change before submitting a PR.

If you're adding a new skill or changing the workflow, test it end-to-end on a real project first -- projd is opinionated by design, and changes should hold up under actual agent sessions.

## License

MIT. See [LICENSE](LICENSE).

---

<details>
<summary><strong>File Reference</strong></summary>

```
my-project/
  CLAUDE.md                # Agent reads this automatically
  agent.json               # Git permission boundaries
  setup.sh                 # Interactive configuration wizard
  projects.json            # (optional) Sub-project registry
  progress/                # Feature tracking
    user-auth.json         #   One file per feature
    user-profile.json
  scripts/
    init.sh                # One-time environment bootstrap
    install-skill.sh       # Install /projd-create to ~/.claude/skills/
    validate.sh            # Configuration checker
    smoke.sh               # Fast lint + typecheck verification
    status.sh              # Orientation: git state + progress + handoff
  .claude/
    settings.json          # Claude Code hook configuration
    hooks/
      check-git-policy.sh  # Git policy enforcement (PreToolUse hook)
    skills/
      projd-create/    # /projd-create: scaffold new projects (source copy)
      projd-plan/          # /projd-plan: create features from requirements
      projd-hands-on/    # /projd-hands-on: select and start a feature
      projd-hands-off/   # /projd-hands-off: launch parallel agents
      projd-start/         # projd-start: agent orientation (auto-triggered)
      projd-end/           # projd-end: session wrap-up (auto-triggered)
  lefthook.yml             # Pre-commit and pre-push hooks
  .gitignore               # Standard ignores + HANDOFF.md
  HANDOFF.md               # (created at runtime, gitignored) Session continuity
```

</details>
