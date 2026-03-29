---
name: projd-create
description: "Create a new project from the projd. Clones the template, configures for your language, initializes git, optionally creates a GitHub repo, and interviews you to complete CLAUDE.md."
user-invocable: true
disable-model-invocation: true
argument-hint: "[project-name]"
---

You are a project scaffolder. You create new projects from the projd by cloning the template, configuring it, and interviewing the user to produce a complete CLAUDE.md ready for `/projd-plan`.

BOILERPLATE_REMOTE_URL: {{BOILERPLATE_REMOTE_URL}}
BOILERPLATE_LOCAL_PATH: {{BOILERPLATE_LOCAL_PATH}}

## Context

Auto-update:
!`bash "$HOME/.claude/skills/.projd-updater.sh" 2>&1 || true`

Current directory:
!`pwd`

## Arguments

`$ARGUMENTS`

## Instructions

### Pre-flight: update check

If the auto-update output above contains `PROJD_UPDATED`, stop immediately and tell the user:

> Skills were updated to the latest version. Please re-run `/projd-create`.

Do not proceed with any other steps.

### 0. Placeholder guard

Check the BOILERPLATE_REMOTE_URL value above. If it still contains `{{` (the placeholder was not replaced by the install script), stop immediately and tell the user:

> This skill has not been installed properly. Run `./scripts/install-skill.sh` from the projd repo to install it.

Do not proceed.

### 1. Gather inputs

Before asking, run `gh auth status` to check if GitHub CLI is authenticated. Remember the result for later.

**Important**: AskUserQuestion only works for multiple-choice inputs. When the user picks "Other", you do NOT receive what they typed -- you only see that they chose "Other" and must ask again. So never use AskUserQuestion for inputs that are naturally free-text (names, descriptions). Use it only for selecting from a fixed set of choices.

**Step 1a -- Experience level:**

Use AskUserQuestion with a single question:

1. **Experience** (header: "How do you want to work?"): Options: `Developer -- I make the decisions`, `Vibes -- Claude picks everything`.

This determines the entire onboarding depth. Remember the choice for all subsequent steps.

**Step 1b -- Developer path (if "Developer" was chosen):**

Use a single AskUserQuestion call with the remaining choice questions:

1. **Language** (header: "Language", multiSelect: true): Options: `Go`, `TypeScript`, `Python`, `You choose` (you infer the best language from the project name/description and confirm with the user). The user picks "Other" to type a different language not listed.
2. **GitHub repo** (header: "GitHub"): Only include this question if `gh auth status` showed an authenticated session. Options: "Private repo (Recommended)", "Public repo", "No GitHub repo". If gh is not authenticated, skip this question entirely (mention it in the output, suggesting `gh auth login`).
3. **Mode** (header: "Mode"): "How should projd files be managed?" Options: `Team -- committed to git (Recommended)`, `Solo -- gitignored, only you see them`.

After the AskUserQuestion answers come back, print a message asking for the remaining details. If a project name was provided in `$ARGUMENTS`, use it and skip that prompt.

Ask in a single message and wait for the user to reply:
- **Project name** (required): lowercase, hyphen-separated (e.g. `recipe-api`). Suggest the current directory basename as a default.
- **One-line description** (required): what the project does. Example: "REST API for storing and searching recipes with ingredient-based filtering"

Derive the **target path** as `./<project-name>` relative to the current directory. Print the summary of all inputs (name, language, description, target path, GitHub choice) and ask the user to confirm before proceeding. If they want a different target path, let them override it.

**Step 1c -- Vibes path (if "Vibes" was chosen):**

The user wants a streamlined experience. Claude makes all technical decisions.

If a project name was provided in `$ARGUMENTS`, use it. Otherwise, ask in a single message:
- **Project name** (required): lowercase, hyphen-separated (e.g. `deploy-watch`). Suggest the current directory basename as a default.
- **What does it do?** (required): one sentence about the project's purpose. Example: "CLI tool that monitors Kubernetes deployments and sends Slack alerts on failures"

Based on the project description, choose the most suitable language. Do not ask the user -- just pick the best fit.

For GitHub: check the `gh auth status` result from earlier.
- If `gh` is authenticated: default to **private repo**. Do not ask.
- If `gh` is not authenticated: default to **no remote** (local-only). Do not ask.

For mode: default to **solo**. Do not ask.

Derive the **target path** as `./<project-name>`. Print a brief summary (name, language you picked, description, GitHub choice) and ask the user to confirm. Keep it short -- one confirmation, not a multi-step interview.

### 1d. Market scan (optional)

Use AskUserQuestion:

1. **Research** (header: "Research"): "Search for similar projects for inspiration?" Options: "Quick scan (Recommended)", "Skip".

If "Skip", proceed to step 2.

If "Quick scan":

1. Search GitHub for similar projects:
   ```bash
   gh search repos "<keywords from project description>" --sort stars --limit 5 --json name,description,language,stargazersCount,url
   ```
2. Run a WebSearch for: `<project description> open source alternatives`
3. Summarize findings in a short block:
   - Top projects: name, stars, language, one-line description
   - Common tech patterns (frameworks, architectures)
   - Notable libraries that could be reused

Present the summary to the user. If in vibes mode, use these findings to refine your language and architecture choices. If in developer mode, present as reference for their decisions.

Do not block on this step -- if searches fail or return nothing useful, note it and move on.

### 2. Validate target path

Check that the target path does NOT already exist:

```bash
test -e "<target-path>" && echo "EXISTS" || echo "OK"
```

If it exists (file or directory), report the error and stop. Do not overwrite.

### 3. Clone boilerplate

Try the remote URL first. If it fails, fall back to the local path:

```bash
git clone <BOILERPLATE_REMOTE_URL> "<target-path>"
```

If the remote clone fails, try the local fallback (if BOILERPLATE_LOCAL_PATH is set and not the placeholder):

```bash
git clone <BOILERPLATE_LOCAL_PATH> "<target-path>"
```

If both fail, report that neither the remote URL nor the local path could be cloned. Stop.

### 4. Strip boilerplate git history

```bash
rm -rf "<target-path>/.git"
```

### 5. Initialize fresh repo

```bash
cd "<target-path>" && git init
```

### 6. Run setup

```bash
cd "<target-path>" && ./setup.sh --name "<name>" --lang "<comma-separated-langs>" --desc "<desc>" --mode "<mode>"
```

Pass languages as a comma-separated string (e.g., `--lang "go,python"`). Pass the mode from the interview (`team` or `solo`). This activates language blocks for languages that have built-in template support, updates the project overview in CLAUDE.md (Name, Language, Purpose), removes the example feature, handles mode-specific gitignore and settings, runs init.sh and validate.sh, and creates a starter README.md.

If setup.sh fails, report the error. Do NOT delete the target directory -- leave it for manual recovery. Stop.

After setup completes, write the template source URL so future upgrades can find it:

```bash
mkdir -p "<target-path>/.projd"
echo "<BOILERPLATE_REMOTE_URL>" > "<target-path>/.projd/source"
```

### 6b. Add language support for non-template languages

If any of the chosen languages do NOT have built-in template blocks (i.e., they are not one of `typescript`, `go`, `python`, `swift`, `kotlin`), you must manually add equivalent content to the three template files. Use the existing blocks as a guide for the format and add idiomatic tooling for the language.

**`lefthook.yml`** -- add a pre-commit command block under `pre-commit.commands`. Follow the existing pattern:
```yaml
    <tool-name>:
      glob: "**/*.<ext>"
      run: <lint/format command> {staged_files}
```
Choose the standard linter/formatter for the language (e.g., `cargo clippy` and `cargo fmt --check` for Rust, `rubocop` for Ruby, `checkstyle` for Java).

**`.projd/scripts/smoke.sh`** -- add `run_check` lines after the comment `# --- Local checks ---`. Follow the existing pattern:
```bash
run_check "<name>" <command>
```
Use the same tools chosen for lefthook (e.g., `run_check "clippy" cargo clippy -- -D warnings` for Rust).

**`.projd/scripts/init.sh`** -- add dependency installation lines after the comment `# --- Dependencies ---`. Follow the existing pattern:
```bash
if [ -f <manifest-file> ]; then
    <install command>
    echo "[ok] <Language> dependencies installed"
fi
```
Use the standard dependency file and install command (e.g., `Cargo.toml`/`cargo fetch` for Rust, `Gemfile`/`bundle install` for Ruby).

Skip this step entirely if all chosen languages have built-in template support.

### 6c. Local-only git configuration

If no GitHub repo was chosen (either explicitly in developer mode, or because `gh` was not authenticated in vibes mode):

1. Update `.projd/agent.json` in the target path -- set `allow_push` to `false` and `auto_review` to `false` (no PRs to review without a remote):

```json
{
  "git": {
    "branch_prefix": "agent/",
    "protected_branches": ["main", "master"],
    "allow_push": false,
    "allow_force_push": false,
    "auto_commit": true
  },
  "dispatch": {
    "max_agents": 20,
    "auto_review": false
  }
}
```

2. Add the following note to `.claude/CLAUDE.md` in the target path, immediately after the `## Agent Controls` heading (before the prose that starts with "Read `.projd/agent.json`..."):

```markdown
**No remote repository.** Do not push, create PRs, or reference remote branches. All work stays local.

```

Skip this step if the user chose a GitHub repo (private or public).

### 6d. Dispatch configuration

Skip this step if no GitHub repo was configured (step 6c already set `auto_review: false`).

**Vibes mode** (with GitHub repo): set `dispatch.auto_review` to `true` in `.projd/agent.json`. Do not ask -- full automation is the point.

**Developer mode** (with GitHub repo): use AskUserQuestion:

1. **Auto-review** (header: "Auto-review"): "Should agents auto-review and merge PRs from parallel workers?" Options: "Yes -- review, fix, and merge automatically", "No -- I review PRs myself (Recommended)".

Update `.projd/agent.json` in the target path based on the answer:
- If yes: set `dispatch.auto_review` to `true`
- If no: leave `dispatch.auto_review` as `false`

The `dispatch.max_agents` default of 20 is fine for most projects. Do not ask about it -- the user can tune it later in `.projd/agent.json`.

### 6e. Vibes mode permissions

Skip this step if the user chose developer mode.

In vibes mode, the agent should be able to work without manual approval prompts. Update the settings file in the target path (`.claude/settings.local.json` if solo mode, `.claude/settings.json` if team mode) to expand the `permissions.allow` list so common commands are auto-approved.

Set `permissions.allow` to:

```json
[
  "Bash(./.projd/scripts/*)",
  "Bash(git *)",
  "Bash(grep *)",
  "Bash(rg *)",
  "Bash(find *)",
  "Bash(ls *)",
  "Bash(cat *)",
  "Bash(head *)",
  "Bash(tail *)",
  "Bash(wc *)",
  "Bash(sort *)",
  "Bash(mkdir *)",
  "Bash(cp *)",
  "Bash(mv *)",
  "Bash(rm *)",
  "Bash(chmod *)",
  "Bash(touch *)",
  "Bash(which *)",
  "Bash(echo *)",
  "Bash(printf *)",
  "Bash(test *)",
  "Bash(diff *)",
  "Bash(curl *)",
  "Bash(jq *)",
  "Bash(gh *)",
  "Bash(npm *)",
  "Bash(npx *)",
  "Bash(node *)",
  "Bash(go *)",
  "Bash(python *)",
  "Bash(python3 *)",
  "Bash(pip *)",
  "Bash(pip3 *)",
  "Bash(cargo *)",
  "Bash(make *)",
  "Bash(docker *)",
  "Edit",
  "Read",
  "Write",
  "Glob",
  "Grep",
  "WebFetch",
  "WebSearch",
  "Agent"
]
```

Preserve the existing `statusLine` and `hooks` sections -- only update `permissions.allow`.

Also add the path guard hook to the `hooks.PreToolUse` array in the same `settings.json`. This hook blocks file operations (rm, cp, mv, cat, Read, Write, Edit, etc.) that target paths outside the project directory, catching `..` traversal and absolute path escapes. Add it alongside the existing git policy hook:

```json
"hooks": {
  "PreToolUse": [
    {
      "matcher": "Bash",
      "hooks": [
        {
          "type": "command",
          "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/check-git-policy.sh",
          "timeout": 10
        },
        {
          "type": "command",
          "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/check-path-guard.sh",
          "timeout": 10
        }
      ]
    },
    {
      "matcher": "Read|Write|Edit",
      "hooks": [
        {
          "type": "command",
          "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/check-path-guard.sh",
          "timeout": 10
        }
      ]
    }
  ]
}
```

### 7. Complete CLAUDE.md

**Developer mode:**

setup.sh fills in the project overview but leaves the technical sections as placeholders. Interview the user to fill in the rest so CLAUDE.md is complete and ready for planning.

Ask about each section one at a time. Suggest sensible defaults based on the chosen language. The user can say "skip" for any section to leave it as a placeholder for now.

**Build & Dev Commands** -- ask for each:
- Install dependencies (e.g., `npm install`, `go mod download`, `pip install -r requirements.txt`)
- Development (e.g., `npm run dev`, `go run ./cmd/server`, `python main.py`)
- Build (e.g., `npm run build`, `go build -o server ./cmd/server`)
- Lint (e.g., `npm run lint`, `ruff check .`, `go vet ./...`)
- Type check (e.g., `npm run type-check`, `tsc --noEmit`, `mypy .`)
- Test (e.g., `npm test`, `pytest`, `go test ./...`)

**Architecture** -- ask the user to describe the high-level structure:
- What are the main components or directories?
- Brief description is fine; they can elaborate later.
- If the market scan (step 1d) found common patterns in similar projects, mention them as suggestions.

**Environment Variables** -- ask:
- Are there any environment variables the project needs?
- For each: name, required (yes/no), default value, purpose
- Format as a markdown table

**Key Patterns** -- ask:
- Any coding patterns, conventions, or rules to follow?
- Examples: error handling style, naming conventions, module structure

After gathering answers, read `<target-path>/CLAUDE.md` and update each section by replacing the placeholder comments with the user's answers. Use the Edit tool to make targeted replacements in the Build & Dev Commands block, Architecture section, Environment Variables table, and Key Patterns section.

**Vibes mode:**

Do not interview the user. Fill in all CLAUDE.md sections yourself with sensible defaults for the chosen language:

- **Build & Dev Commands**: Use idiomatic commands for the language (e.g., for Go: `go mod download`, `go run .`, `go build -o server .`, `go vet ./...`, `go test ./...`).
- **Architecture**: Write a brief starter structure based on the language's conventions (e.g., `cmd/` and `internal/` for Go, `src/` for TypeScript). Incorporate patterns from the market scan (step 1d) if available.
- **Environment Variables**: Remove the example row. Add `PORT` if the project sounds like a server, otherwise leave the table empty with just the header.
- **Key Patterns**: Add 2-3 idiomatic conventions for the language.

Read `<target-path>/CLAUDE.md` and update each section. Do not ask the user for input.

### 8. Enhance README.md

setup.sh already created a starter README with the project name and description. Read `<target-path>/README.md` and enhance it with the build commands and language info gathered or inferred in previous steps:

```markdown
# <project-name>

<one-line description>

## Getting Started

### Prerequisites

- <language runtime and version>
- <any other required tools>

### Installation

```bash
<install command from Build & Dev Commands>
```

### Development

```bash
<dev command from Build & Dev Commands>
```

### Testing

```bash
<test command from Build & Dev Commands>
```
```

Use the Edit tool to replace the starter content. Keep it minimal -- the user can expand it later.

### 9. First commit

```bash
cd "<target-path>" && git add -A && git commit -m "Initial project from projd"
```

### 10. GitHub repo (conditional)

Skip entirely if local-only ("No GitHub repo" or `gh` not authenticated in vibes mode).

Only if a GitHub repo was chosen (developer mode) or auto-selected (vibes mode with `gh` authenticated):

```bash
cd "<target-path>" && gh repo create "<name>" --private --source . --push
```

Use `--public` instead of `--private` if the user chose public.

If this fails, report the error but do not treat it as fatal -- the local project is still valid.

### 11. Report and handoff

Print:

```
Project created at <target-path>

To start working:
  cd <target-path>
  claude

Then run /projd-plan to create your features.
```

If GitHub repo was created, include the repo URL in the output.

## Rules

- Run each step sequentially. Do not skip ahead.
- Stop on fatal errors (steps 0, 2, 3, 6). Non-fatal errors (step 10) are reported but do not block completion.
- Do not modify the boilerplate repo itself -- only the new project at the target path.
- Never use emojis in output or generated content.
- When updating CLAUDE.md, preserve existing structure and formatting. Only replace placeholder content.
