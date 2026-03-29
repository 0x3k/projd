---
name: projd-adopt
description: "Add projd infrastructure to an existing project. Copies skills, hooks, scripts, and merges CLAUDE.md and settings.json without disturbing existing code."
user-invocable: true
disable-model-invocation: true
argument-hint: ""
---

You add projd infrastructure to an existing, working project. You copy skills, hooks, and scripts from the template, merge configuration files non-destructively, and leave the project ready for `/projd-plan`.

BOILERPLATE_REMOTE_URL: {{BOILERPLATE_REMOTE_URL}}
BOILERPLATE_LOCAL_PATH: {{BOILERPLATE_LOCAL_PATH}}

## Arguments

`$ARGUMENTS`

## Instructions

### Pre-flight: gather context and check for updates

Run these commands to gather context before proceeding:

1. `bash "$HOME/.claude/skills/.projd-updater.sh"` -- check for skill updates
2. `pwd` -- confirm current directory
3. `gh auth status` -- check GitHub CLI authentication
4. `ls -la CLAUDE.md .projd/agent.json lefthook.yml .claude/settings.json` -- check for existing files
5. `ls -d .projd .projd/progress .projd/scripts .claude/hooks .claude/skills` -- check for existing projd directories

If the updater output contains `PROJD_UPDATED`, stop immediately and tell the user:

> Skills were updated to the latest version. Please re-run `/projd-adopt`.

Do not proceed with any other steps.

### 0. Placeholder guard

Check the BOILERPLATE_REMOTE_URL value above. If it still contains `{{` (the placeholder was not replaced by the install script), stop immediately and tell the user:

> This skill has not been installed properly. Run `./scripts/install-skill.sh` from the projd repo to install it.

Do not proceed.

### 1. Validate context

Run these checks. Stop on any failure.

1. **Git repo**: Run `git rev-parse --is-inside-work-tree`. If not a git repo, stop and suggest `git init`.
2. **Not already projd**: Check for `.projd/` directory. If it exists, stop and tell the user to use `./.projd/scripts/upgrade.sh` instead.
3. **Not already adopted**: Check for `.claude/CLAUDE.md`. If it exists and contains `## Agent Controls`, stop -- projd is already adopted. Also check if `CLAUDE.md` contains `<!-- projd:begin -->` (legacy sentinel format) -- if found, stop and suggest running `./.projd/scripts/upgrade.sh` to migrate.

Remember the `gh auth status` result from the Context section above for later steps.

### 2. Interview

**Step 2a -- Experience level:**

Use AskUserQuestion with a single question:

1. **Experience** (header: "Mode"): "How do you want to work?" Options: `Developer -- I make the decisions`, `Vibes -- Claude picks everything`.

Remember the choice for all subsequent steps.

**Step 2b -- Developer path (if "Developer" was chosen):**

First, auto-detect languages by checking for these files in the project:

| File | Language |
|------|----------|
| `go.mod` | Go |
| `package.json` | TypeScript |
| `requirements.txt` or `pyproject.toml` or `setup.py` | Python |
| `Package.swift` | Swift |
| `build.gradle` or `build.gradle.kts` | Kotlin |
| `Cargo.toml` | Rust |
| `Gemfile` | Ruby |

Then use a single AskUserQuestion call with these questions:

1. **Language** (header: "Language", multiSelect: true): Options: `Go`, `TypeScript`, `Python`, `None -- skip language hooks`. Pre-select detected languages by listing them first with "(detected)" in the label. The user picks "Other" to type a different language.
2. **Branch prefix** (header: "Prefix"): "Branch prefix for agent work?" Options: `agent/ (Recommended)`, `feature/`, `claude/`. The user picks "Other" to type their own.
3. **Push policy** (header: "Push"): "Push policy?" Options: `Feature branches only (Recommended)`, `All branches`, `No pushing -- local only`.
4. **Mode** (header: "Mode"): "How should projd files be managed?" Options: `Team -- committed to git (Recommended)`, `Solo -- gitignored, only you see them`.

**Step 2c -- Vibes path (if "Vibes" was chosen):**

Auto-detect language from project files (same detection as 2b). Use defaults:
- Branch prefix: `agent/`
- Push policy: `feature` (if `gh` is authenticated), `false` (if not)
- Auto-review: `true` (if `gh` is authenticated), `false` (if not)
- Mode: `solo`

Show a one-line summary of choices and ask the user to confirm before proceeding.

### 3. Clone template to temp dir

Try the remote URL first. If it fails, fall back to the local path:

```bash
TEMP_DIR=$(mktemp -d)
git clone --depth 1 <BOILERPLATE_REMOTE_URL> "$TEMP_DIR" 2>/dev/null
```

If the remote clone fails, try the local fallback (if BOILERPLATE_LOCAL_PATH is set and not the placeholder):

```bash
git clone <BOILERPLATE_LOCAL_PATH> "$TEMP_DIR"
```

If both fail, report and stop.

### 4. Check for file conflicts

These are the template-managed files that will be copied:

```
.claude/CLAUDE.md
.claude/hooks/check-git-policy.sh
.claude/hooks/check-path-guard.sh
.claude/skills/projd-start/SKILL.md
.claude/skills/projd-end/SKILL.md
.claude/skills/projd-plan/SKILL.md
.claude/skills/projd-hands-on/SKILL.md
.claude/skills/projd-hands-off/SKILL.md
.projd/scripts/init.sh
.projd/scripts/monitor.sh
.projd/scripts/skill-context.sh
.projd/scripts/smoke.sh
.projd/scripts/status.sh
.projd/scripts/statusline.sh
.projd/scripts/validate.sh
.projd/scripts/upgrade.sh
.projd/scripts/activate-langs.sh
.projd/agent.json
lefthook.yml
```

For each file, check if it already exists in the project. If **any** conflicts are found, list them and use AskUserQuestion:

1. **Conflicts** (header: "Conflicts"): "These files already exist: <list>. How to proceed?" Options: `Back up to *.pre-projd and overwrite`, `Skip conflicting files`, `Abort`.

If "Abort", clean up the temp dir and stop.

If no conflicts, skip the question and proceed.

### 5. Copy infrastructure files

For each template file listed in step 4:

1. Create parent directories as needed (`mkdir -p`)
2. If the file conflicts and the user chose "Back up", rename the existing file to `<filename>.pre-projd`
3. If the file conflicts and the user chose "Skip", skip it
4. Otherwise, copy the file from the temp clone

After copying, set executable permissions:

```bash
chmod +x .projd/scripts/*.sh .claude/hooks/*.sh
```

### 6. Activate language blocks

If the user selected languages that have built-in template support (typescript, go, python, swift, kotlin), run the activation script on each file that has language blocks:

```bash
./.projd/scripts/activate-langs.sh .projd/scripts/smoke.sh <lang1> <lang2> ...
./.projd/scripts/activate-langs.sh .projd/scripts/init.sh <lang1> <lang2> ...
./.projd/scripts/activate-langs.sh lefthook.yml <lang1> <lang2> ...
```

If any selected languages do NOT have built-in template blocks (not in: typescript, go, python, swift, kotlin), manually add equivalent content following the same approach as projd-create step 6b:

**`lefthook.yml`** -- add a pre-commit command block under `pre-commit.commands`:
```yaml
    <tool-name>:
      glob: "**/*.<ext>"
      run: <lint/format command> {staged_files}
```

**`.projd/scripts/smoke.sh`** -- add `run_check` lines after `# --- Local checks ---`:
```bash
run_check "<name>" <command>
```

**`.projd/scripts/init.sh`** -- add dependency install lines after `# --- Dependencies ---`:
```bash
if [ -f <manifest-file> ]; then
    <install command>
    echo "[ok] <Language> dependencies installed"
fi
```

If the user chose "None -- skip language hooks", skip this entire step.

### 7. Merge Claude Code settings

Determine the target settings file based on the mode chosen in step 2:
- **Team mode**: `.claude/settings.json`
- **Solo mode**: `.claude/settings.local.json`

Read the target file if it exists. If it does not exist, start with an empty `{}`.

**Base mode (Developer):**

Merge these entries:

- Add to `permissions.allow` (deduplicate -- do not add entries that already exist):
  ```json
  "Bash(./.projd/scripts/skill-context.sh:*)",
  "Bash(git *)"
  ```

- Set `statusLine` (if the key does not already exist):
  ```json
  "statusLine": {
    "type": "command",
    "command": "\"$CLAUDE_PROJECT_DIR\"/.projd/scripts/statusline.sh"
  }
  ```
  If a `statusLine` already exists, use AskUserQuestion to ask:
  1. **StatusLine** (header: "StatusLine"): "A status line is already configured. Replace with projd's?" Options: `Yes -- use projd status line`, `No -- keep existing`.

- Add to `hooks.PreToolUse` (only if no existing hook already references `check-git-policy.sh`):
  ```json
  {
    "matcher": "Bash",
    "hooks": [
      {
        "type": "command",
        "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/check-git-policy.sh",
        "timeout": 10
      }
    ]
  }
  ```

**Vibes mode:**

Replace `permissions.allow` with the expanded list:

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

If the existing file had additional `permissions.allow` entries not in the list above, preserve them (union).

Set `statusLine` (same as base mode, with the same conflict handling).

Set `hooks.PreToolUse` to include both hooks with the path guard:

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

If existing `hooks.PreToolUse` entries exist that are NOT projd hooks, preserve them (append projd entries to the array).

Write the merged result back to the target settings file (`.claude/settings.json` for team mode, `.claude/settings.local.json` for solo mode).

### 8. Create .projd/agent.json

Build `.projd/agent.json` from interview answers:

```json
{
  "git": {
    "branch_prefix": "<from interview>",
    "protected_branches": ["main", "master"],
    "allow_push": "<from interview: 'feature' | true | false>",
    "allow_force_push": false,
    "auto_commit": true
  },
  "dispatch": {
    "max_agents": 20,
    "auto_review": <true if vibes with gh auth, false otherwise>
  }
}
```

Map push policy answers:
- "Feature branches only" -> `"feature"`
- "All branches" -> `true`
- "No pushing -- local only" -> `false`

If `.projd/agent.json` already exists, read it and warn the user: "A .projd/agent.json already exists. It will be overwritten with your new settings." Then write the new file. The old values are not merged -- the user just configured fresh values in the interview.

### 9. Write .claude/CLAUDE.md

Copy `.claude/CLAUDE.md` from the temp clone directory to the project. This file contains the projd workflow instructions (Agent Controls, Session Conventions, etc.) and is auto-loaded by Claude Code alongside the root `CLAUDE.md`.

```bash
cp "$TEMP_DIR/.claude/CLAUDE.md" .claude/CLAUDE.md
```

Do NOT modify the user's existing root `CLAUDE.md`. The projd workflow now lives in `.claude/CLAUDE.md` as a separate file.

**Important**: Read `.claude/CLAUDE.md` from the temp clone (not the root CLAUDE.md) to get the canonical projd sections.

### 10. Create directories, metadata, and mode

```bash
mkdir -p .projd/progress
```

Write the mode:

```bash
echo "<mode>" > .projd/mode
```

If **solo mode**, append projd entries to `.gitignore`:

```gitignore
# projd infrastructure (solo mode)
.projd/
.claude/CLAUDE.md
.claude/hooks/
.claude/skills/
lefthook.yml
```

Generate `.projd/manifest` with SHA256 checksums of all copied template files:

```bash
: > .projd/manifest
for tf in <each template file>; do
    if [ -f "$tf" ]; then
        cs=$(shasum -a 256 "$tf" | awk '{print $1}')
        printf '%s\t%s\n' "$tf" "$cs" >> .projd/manifest
    fi
done
```

Write `.projd/source` with the BOILERPLATE_REMOTE_URL.

### 11. Bootstrap and validate

Run the initialization script to install Lefthook and set up the development environment:

```bash
./.projd/scripts/init.sh
```

Then run validation (allow it to fail -- warnings about missing features in `.projd/progress/` are expected):

```bash
./.projd/scripts/validate.sh || true
```

Report any warnings or failures to the user.

### 12. Clean up and report

Remove the temp clone directory:

```bash
rm -rf "$TEMP_DIR"
```

Print a summary:

```
projd infrastructure added.

Installed:
  Skills:  projd-start, projd-end, projd-plan, projd-hands-on, projd-hands-off
  Hooks:   check-git-policy.sh [+ check-path-guard.sh if vibes]
  Scripts: init, smoke, validate, status, statusline, upgrade, skill-context, monitor, activate-langs
  Config:  .projd/agent.json, lefthook.yml, settings (merged into <settings file>)
  .claude/CLAUDE.md created (projd workflow instructions)
  Mode:    <team|solo>

Next steps:
  1. Review the changes: git diff
  2. Commit when ready
  3. Plan features: /projd-plan <your requirements>
```

If there were skipped files (from conflict resolution), list them and suggest the user merge manually.

## Rules

- Run each step sequentially. Do not skip ahead.
- Stop on fatal errors (steps 0, 1, 3). Non-fatal errors (step 11 validate) are reported but do not block.
- Never modify the user's existing source code, tests, or non-configuration files.
- Never create a commit. The user decides when to commit the infrastructure changes.
- Never use emojis in output or generated content.
- When merging settings, preserve all existing entries. Only add, never remove.
- Write `.claude/CLAUDE.md` as a separate file. Do not modify the user's root `CLAUDE.md`.
