# Landscape

This space is moving fast. Here's how projd compares to other open-source tools for orchestrating AI coding agents. The table focuses on capabilities that matter for structured, multi-session development work -- not benchmarks or model support breadth.

## Comparison

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

## Where projd fits

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

## Other tools worth knowing about

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
