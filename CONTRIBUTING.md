# Contributing to projd

Forks and contributions are welcome. This document covers how projd is structured, how to set up a development environment, and how to contribute changes back.

## Getting Started

```bash
# Fork the repo on GitHub, then:
git clone https://github.com/<your-username>/projd.git
cd projd
```

projd is a template repository -- the files in this repo are what get copied into new projects. There is no build step. The "product" is the collection of scripts, skills, hooks, and configuration files that ship with every new projd project.

### Prerequisites

- [Claude Code](https://claude.ai/code) (CLI, desktop, or IDE extension)
- [Lefthook](https://github.com/evilmartians/lefthook): `brew install lefthook`
- [jq](https://jqlang.github.io/jq/): `brew install jq`
- [GitHub CLI](https://cli.github.com/): `brew install gh`
- A shell: bash or zsh (macOS/Linux)

## Project Structure

```
projd/
├── .claude/
│   ├── CLAUDE.md                     # projd workflow instructions (gitignored in solo mode)
│   ├── hooks/
│   │   ├── check-git-policy.sh      # PreToolUse hook: git policy enforcement
│   │   └── check-path-guard.sh      # PreToolUse hook: path escape guard (vibes mode)
│   ├── settings.json                 # Claude Code project settings (committed in team mode)
│   ├── settings.local.json           # Local overrides (gitignored)
│   └── skills/
│       ├── projd-start/SKILL.md      # Session orientation (agent-facing)
│       ├── projd-plan/SKILL.md       # Planning (user-invocable)
│       ├── projd-hands-on/SKILL.md   # Feature selection (user-invocable)
│       ├── projd-hands-off/SKILL.md  # Parallel dispatch (user-invocable)
│       ├── projd-end/SKILL.md        # Session wrap-up (agent-facing)
│       ├── projd-create/SKILL.md     # Scaffolding (user-level, installed separately)
│       └── projd-adopt/SKILL.md      # Adopt into existing project (user-level, installed separately)
├── .projd/
│   ├── scripts/
│   │   ├── status.sh                 # Project state overview
│   │   ├── smoke.sh                  # Fast lint + typecheck verification
│   │   ├── validate.sh               # Configuration validation
│   │   ├── init.sh                   # Environment bootstrap
│   │   ├── activate-langs.sh         # Language block activation (used by setup.sh and adopt)
│   │   ├── skill-context.sh          # Context provider for skills
│   │   ├── statusline.sh             # Claude Code status line provider
│   │   ├── monitor.sh                # Interactive live dashboard for parallel sessions
│   │   ├── upgrade.sh                # Update project to latest template version
│   │   └── install-skill.sh          # Install /projd-create and /projd-adopt to user-level skills
│   ├── progress/
│   │   └── example-feature.json      # Example feature file (removed by setup.sh)
│   └── agent.json                    # Git policy configuration
├── docs/                             # Additional documentation
├── CLAUDE.md                         # Project knowledge: overview, build commands, architecture
├── lefthook.yml                      # Pre-commit and pre-push hooks
├── setup.sh                          # Interactive setup wizard (self-deleting after use)
├── LICENSE
└── README.md
```

### What ships with every project

When a user runs `setup.sh` or `/projd-create`, they get a copy of this repo with:
- Language-specific blocks activated in `lefthook.yml`, `.projd/scripts/smoke.sh`, and `.projd/scripts/init.sh`
- Root `CLAUDE.md` filled in with project details (overview, build commands)
- `.claude/CLAUDE.md` containing projd workflow instructions (agent controls, session conventions)
- Template files removed (`README.md`, `LICENSE`, `setup.sh`, `.projd/scripts/install-skill.sh`, the `projd-create` and `projd-adopt` skill directories)
- The example feature file removed
- Mode set to `team` or `solo` (solo mode gitignores all projd infrastructure files)

Everything else ships as-is. Changes you make to scripts, skills, hooks, or configuration directly affect what new projects receive.

## Key Concepts

### Template Block System

Several files use a marker-based system to support multiple languages in one template. Blocks look like this:

```bash
# [typescript]
# npx eslint .
# [/typescript]

# [go]
# go vet ./...
# [/go]
```

`.projd/scripts/activate-langs.sh` processes these markers with AWK (called by both `setup.sh` and `/projd-adopt`):
- For the selected language(s): uncomments the block (removes the leading `# ` prefix)
- For all other languages: deletes the entire block

This applies to `lefthook.yml`, `.projd/scripts/smoke.sh`, and `.projd/scripts/init.sh`. To add support for a new language, add a commented block in each of these three files using the `# [lang]` / `# [/lang]` markers.

### Skill System

Skills are Markdown files at `.claude/skills/<name>/SKILL.md`. They contain instructions that Claude Code executes when invoked. There are two kinds:

- **User-invocable** (`/projd-plan`, `/projd-hands-on`, `/projd-hands-off`, `/projd-create`, `/projd-adopt`): Triggered by the operator typing the slash command. These have `disable-model-invocation: true` in frontmatter so the agent can't trigger them on its own.
- **Agent-facing** (`projd-start`, `projd-end`): Triggered by the agent during its workflow. No `disable-model-invocation` restriction.

Skills call `./.projd/scripts/skill-context.sh` to load project state (features, agent config, git status, etc.) without requiring complex shell expressions.

### Hook System

The PreToolUse hook (`.claude/hooks/check-git-policy.sh`) is the primary enforcement layer for `.projd/agent.json`. It runs before every bash command, receives the command as JSON on stdin, and returns a JSON deny decision if the command violates policy. See [docs/hooks.md](docs/hooks.md) for the full architecture.

A second PreToolUse hook (`.claude/hooks/check-path-guard.sh`) blocks file operations that target paths outside the project directory. It catches absolute paths, `..` traversal, and symlink escapes in both Bash commands (`rm`, `cp`, `mv`, etc.) and Claude tools (`Read`, `Write`, `Edit`). This hook is only enabled in vibes mode (configured by `/projd-create` and `/projd-adopt`).

A secondary pre-push hook in `lefthook.yml` provides the same push-policy checks for direct git usage outside of Claude Code.

### Feature State Machine

Features in `.projd/progress/` follow a lifecycle: `pending` -> `in_progress` -> `complete` -> merged via PR. The `blocked_by` array expresses dependencies between features. Skills enforce this lifecycle -- `projd-hands-on` won't pick a feature whose blockers aren't complete, and `projd-end` won't mark a feature complete unless smoke tests pass.

## How to Contribute

### Adding a new language

1. Add a commented block in `lefthook.yml` under `pre-commit` with the language's lint and typecheck commands.
2. Add a matching block in `.projd/scripts/smoke.sh` with `run_check` calls for the same commands.
3. Add a matching block in `.projd/scripts/init.sh` with the dependency install command.
4. Use the `# [lang]` / `# [/lang]` markers so `setup.sh` can activate them.
5. Update the "Supported languages" line in `setup.sh` and `README.md`.

Example for a hypothetical `rust` language:

```yaml
# lefthook.yml, under pre-commit > commands:
    # [rust]
    # rust-clippy:
    #   run: cargo clippy -- -D warnings
    # rust-fmt:
    #   run: cargo fmt -- --check
    # [/rust]
```

```bash
# .projd/scripts/smoke.sh:
# [rust]
# run_check "clippy" "cargo clippy -- -D warnings"
# run_check "rustfmt" "cargo fmt -- --check"
# [/rust]
```

```bash
# .projd/scripts/init.sh:
# [rust]
# if [ -f Cargo.toml ]; then
#   cargo fetch
#   echo "[ok] rust dependencies fetched"
# fi
# [/rust]
```

### Modifying a skill

Skills are self-contained Markdown files. Edit the SKILL.md directly. Key things to keep in mind:

- Skills call `./.projd/scripts/skill-context.sh` for project state. If you need a new kind of context, add a subcommand to that script rather than embedding shell logic in the skill.
- User-invocable skills should have `disable-model-invocation: true` in frontmatter.
- Test your skill changes by running the skill in a real (or test) projd project.

### Modifying the hook

The hook at `.claude/hooks/check-git-policy.sh` receives JSON on stdin and must return valid JSON to deny a command or exit silently (exit 0, no output) to allow it. Key constraints:

- The hook has a 10-second timeout. Keep it fast.
- It must handle missing or malformed input gracefully (the tool may send unexpected shapes).
- Use portable shell constructs -- no bash-only features, no GNU-only flags. The hook runs on macOS and Linux.
- Test with both `jq` available and unavailable (the hook should degrade gracefully).

### Modifying scripts

All scripts in `.projd/scripts/` should:
- Be POSIX-compatible where possible (avoid bashisms, use `#!/usr/bin/env bash` or `#!/bin/sh`)
- Handle the `projects.json` multi-project case if they aggregate across sub-projects
- Be idempotent (safe to re-run)
- Use `[ok]`, `[warn]`, `[PASS]`, `[FAIL]` output conventions matching the existing scripts

## Testing Changes

There is no automated test suite. Testing is manual:

1. **Smoke test the template itself**: Run `./.projd/scripts/validate.sh --strict` from the repo root. This checks that all configuration is valid and smoke tests pass.

2. **Test setup end-to-end**: Copy the repo to a temp directory and run `./setup.sh` with a language you changed. Verify the output files have the correct blocks activated and placeholders removed.

   ```bash
   cp -r . /tmp/test-projd
   cd /tmp/test-projd
   rm -rf .git && git init
   ./setup.sh --name test-app --lang go --desc "Test"
   ./.projd/scripts/validate.sh --strict
   ```

3. **Test skills**: Create a test project with `setup.sh`, add a feature file to `.projd/progress/`, and run through the skill workflow (`/projd-plan`, `/projd-hands-on`, `/projd-end`).

4. **Test the hook**: The hook can be tested by piping JSON to it directly:

   ```bash
   echo '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}' | .claude/hooks/check-git-policy.sh
   ```

   A deny response means the hook is working. No output (exit 0) means the command was allowed.

## Pull Request Guidelines

- One logical change per PR. Don't bundle unrelated fixes.
- If you're adding a language, include all three files (lefthook.yml, smoke.sh, init.sh) in one PR.
- Test your changes with a real `setup.sh` run before submitting.
- Keep commit messages descriptive -- explain what changed and why, not just what files were touched.
- No emojis in code, comments, or commit messages.

## Local Development Settings

`.claude/settings.local.json` is gitignored and can be used to add permissions needed during development (e.g., allowing `chmod`, `WebSearch`, or other tools). This file is never committed and won't affect other contributors.

## Questions

If something is unclear or you hit an issue, open a GitHub issue. We'd rather answer a question than review a PR built on a wrong assumption.
