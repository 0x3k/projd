# Setup

## Prerequisites

- [Claude Code](https://claude.ai/code): CLI, desktop app, or IDE extension
- [Lefthook](https://github.com/evilmartians/lefthook): `brew install lefthook`
- [jq](https://jqlang.github.io/jq/): `brew install jq`
- [GitHub CLI](https://cli.github.com/): `brew install gh` (for PR creation)
- Language-specific linters for your project (see `lefthook.yml` comments)

## Interactive wizard

```bash
cp -r projd/ my-new-project/
cd my-new-project/
git init
chmod +x setup.sh scripts/*.sh
./setup.sh                                           # interactive
./setup.sh --name my-app --lang go --desc "My app"   # or scripted
```

Supported languages with built-in template blocks: `typescript`, `go`, `python`, `swift`, `kotlin`. Any language is accepted -- unsupported ones skip template activation.

## Scaffolding skill (recommended for repeat use)

Install the projd skills once, then create or adopt projects from any Claude Code session:

```bash
./scripts/install-skill.sh   # from the template repo (one-time)
```
```
/projd-create                 # scaffold a new project
/projd-adopt                  # add projd to an existing project
```

`/projd-create` asks developer-or-vibes, clones the latest template, runs setup, and either interviews you (developer) or auto-fills everything (vibes) to produce a complete CLAUDE.md. It can optionally scan for similar open-source projects for inspiration. When it finishes, the project is ready for `/projd-plan`.

```bash
./scripts/install-skill.sh --check   # show diff if skills changed
./scripts/install-skill.sh --remove  # uninstall all projd skills
```

## Adopting an existing project

If you already have a working codebase and want to add projd's workflow infrastructure to it, use `/projd-adopt` from within that project:

```
cd your-existing-project
/projd-adopt
```

The skill:

1. Validates you're in a git repo that doesn't already have projd
2. Interviews you (developer or vibes mode) for language, branch prefix, and push policy
3. Copies infrastructure files from the template (skills, hooks, scripts, lefthook.yml)
4. Activates language blocks for your project's language(s)
5. **Merges** `.claude/settings.json` non-destructively (adds permissions, hooks, status line without removing existing entries)
6. **Appends** projd workflow sections to your existing `CLAUDE.md` (does not modify existing content)
7. Creates `agent.json` with your configured policies
8. Sets up `progress/` and `.projd/` directories
9. Runs `init.sh` and `validate.sh`

After adoption, your project supports the full projd workflow: `/projd-plan`, `/projd-hands-on`, `/projd-hands-off`, session continuity, and `./scripts/upgrade.sh` for future template updates.

## Verifying your setup

After running `setup.sh`, use the validation script to check that everything was configured correctly:

```bash
./scripts/validate.sh            # check configuration
./scripts/validate.sh --strict   # also run smoke tests
```

This checks that `CLAUDE.md` is filled in, `agent.json` is valid, `lefthook.yml` has active hooks, `smoke.sh` has active checks, and feature files (if any) have valid schemas. Failures block; warnings are advisory.

## Bootstrapping the environment

```bash
./scripts/init.sh
```

This installs Lefthook git hooks, makes Claude Code hook scripts executable, and installs language-specific dependencies (e.g., `npm install`, `go mod download`, `pip install` in a venv). It's idempotent -- safe to re-run. For multi-project workspaces, it bootstraps each sub-project automatically.
