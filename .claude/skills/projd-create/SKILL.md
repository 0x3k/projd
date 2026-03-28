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

Current directory:
!`pwd`

## Arguments

`$ARGUMENTS`

## Instructions

### 0. Placeholder guard

Check the BOILERPLATE_REMOTE_URL value above. If it still contains `{{` (the placeholder was not replaced by the install script), stop immediately and tell the user:

> This skill has not been installed properly. Run `./scripts/install-skill.sh` from the projd repo to install it.

Do not proceed.

### 1. Gather inputs

Before asking, run `gh auth status` to check if GitHub CLI is authenticated. Remember the result for the GitHub question below.

**Important**: AskUserQuestion only works for multiple-choice inputs. When the user picks "Other", you do NOT receive what they typed -- you only see that they chose "Other" and must ask again. So never use AskUserQuestion for inputs that are naturally free-text (names, descriptions). Use it only for selecting from a fixed set of choices.

**Step 1a -- AskUserQuestion for choices:**

Use a single AskUserQuestion call. Each question MUST have 2-4 options. Include these questions:

1. **Language** (header: "Language", multiSelect: true): Options: `Go`, `TypeScript`, `Python`, `You choose` (you infer the best language from the project name/description and confirm with the user). The user picks "Other" to type a different language not listed.
2. **GitHub repo** (header: "GitHub"): Only include this question if `gh auth status` showed an authenticated session. Options: "Private repo (Recommended)", "Public repo", "No GitHub repo". If gh is not authenticated, skip this question entirely (mention it in the output, suggesting `gh auth login`).

**Step 1b -- Plain text for free-text inputs:**

After the AskUserQuestion answers come back, print a message asking for the remaining details. If a project name was provided in `$ARGUMENTS`, use it and skip that prompt.

Ask in a single message and wait for the user to reply:
- **Project name** (required): kebab-case slug. Suggest the current directory basename as a default.
- **One-line description** (required): what the project does.

Derive the **target path** as `./<project-name>` relative to the current directory. Print the summary of all inputs (name, language, description, target path, GitHub choice) and ask the user to confirm before proceeding. If they want a different target path, let them override it.

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
cd "<target-path>" && ./setup.sh --name "<name>" --lang "<comma-separated-langs>" --desc "<desc>"
```

Pass languages as a comma-separated string (e.g., `--lang "go,python"`). This activates language blocks for languages that have built-in template support, updates the project overview in CLAUDE.md (Name, Language, Purpose), removes the example feature, and runs init.sh and validate.sh.

If setup.sh fails, report the error. Do NOT delete the target directory -- leave it for manual recovery. Stop.

### 6b. Add language support for non-template languages

If any of the chosen languages do NOT have built-in template blocks (i.e., they are not one of `typescript`, `go`, `python`, `swift`, `kotlin`), you must manually add equivalent content to the three template files. Use the existing blocks as a guide for the format and add idiomatic tooling for the language.

**`lefthook.yml`** -- add a pre-commit command block under `pre-commit.commands`. Follow the existing pattern:
```yaml
    <tool-name>:
      glob: "**/*.<ext>"
      run: <lint/format command> {staged_files}
```
Choose the standard linter/formatter for the language (e.g., `cargo clippy` and `cargo fmt --check` for Rust, `rubocop` for Ruby, `checkstyle` for Java).

**`scripts/smoke.sh`** -- add `run_check` lines after the comment `# --- Local checks ---`. Follow the existing pattern:
```bash
run_check "<name>" <command>
```
Use the same tools chosen for lefthook (e.g., `run_check "clippy" cargo clippy -- -D warnings` for Rust).

**`scripts/init.sh`** -- add dependency installation lines after the comment `# --- Dependencies ---`. Follow the existing pattern:
```bash
if [ -f <manifest-file> ]; then
    <install command>
    echo "[ok] <Language> dependencies installed"
fi
```
Use the standard dependency file and install command (e.g., `Cargo.toml`/`cargo fetch` for Rust, `Gemfile`/`bundle install` for Ruby).

Skip this step entirely if all chosen languages have built-in template support.

### 7. Interview user to complete CLAUDE.md

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

**Environment Variables** -- ask:
- Are there any environment variables the project needs?
- For each: name, required (yes/no), default value, purpose
- Format as a markdown table

**Key Patterns** -- ask:
- Any coding patterns, conventions, or rules to follow?
- Examples: error handling style, naming conventions, module structure

After gathering answers, read `<target-path>/CLAUDE.md` and update each section by replacing the placeholder comments with the user's answers. Use the Edit tool or sed to make targeted replacements in the Build & Dev Commands block, Architecture section, Environment Variables table, and Key Patterns section.

### 8. First commit

```bash
cd "<target-path>" && git add -A && git commit -m "Initial project from projd"
```

### 9. GitHub repo (conditional)

Only if the user opted in at step 1:

```bash
cd "<target-path>" && gh repo create "<name>" --private --source . --push
```

Use `--public` instead of `--private` if the user chose public.

If this fails, report the error but do not treat it as fatal -- the local project is still valid.

### 10. Report and handoff

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
- Stop on fatal errors (steps 0, 2, 3, 6). Non-fatal errors (step 9) are reported but do not block completion.
- Do not modify the boilerplate repo itself -- only the new project at the target path.
- Never use emojis in output or generated content.
- When updating CLAUDE.md, preserve existing structure and formatting. Only replace placeholder content.
