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

## Context

Current directory:
!`pwd`

GitHub CLI:
!`gh auth status 2>&1 || echo "NOT_AUTHENTICATED"`

Existing files:
!`ls -la CLAUDE.md agent.json lefthook.yml .claude/settings.json 2>/dev/null || echo "(none found)"`
!`ls -d .projd progress scripts .claude/hooks .claude/skills 2>/dev/null || echo "(no projd dirs)"`

## Arguments

`$ARGUMENTS`

## Instructions

### 0. Placeholder guard

Check the BOILERPLATE_REMOTE_URL value above. If it still contains `{{` (the placeholder was not replaced by the install script), stop immediately and tell the user:

> This skill has not been installed properly. Run `./scripts/install-skill.sh` from the projd repo to install it.

Do not proceed.

### 1. Validate context

Run these checks. Stop on any failure.

1. **Git repo**: Run `git rev-parse --is-inside-work-tree`. If not a git repo, stop and suggest `git init`.
2. **Not already projd**: Check for `.projd/` directory. If it exists, stop and tell the user to use `./scripts/upgrade.sh` instead.
3. **Not already adopted**: Check if `CLAUDE.md` contains `<!-- projd:begin -->`. If found, stop -- projd sections are already present.

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

**Step 2c -- Vibes path (if "Vibes" was chosen):**

Auto-detect language from project files (same detection as 2b). Use defaults:
- Branch prefix: `agent/`
- Push policy: `feature` (if `gh` is authenticated), `false` (if not)
- Auto-review: `true` (if `gh` is authenticated), `false` (if not)

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
.claude/hooks/check-git-policy.sh
.claude/hooks/check-path-guard.sh
.claude/skills/projd-start/SKILL.md
.claude/skills/projd-end/SKILL.md
.claude/skills/projd-plan/SKILL.md
.claude/skills/projd-hands-on/SKILL.md
.claude/skills/projd-hands-off/SKILL.md
scripts/init.sh
scripts/monitor.sh
scripts/skill-context.sh
scripts/smoke.sh
scripts/status.sh
scripts/statusline.sh
scripts/validate.sh
scripts/upgrade.sh
scripts/activate-langs.sh
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
chmod +x scripts/*.sh .claude/hooks/*.sh
```

### 6. Activate language blocks

If the user selected languages that have built-in template support (typescript, go, python, swift, kotlin), run the activation script on each file that has language blocks:

```bash
./scripts/activate-langs.sh scripts/smoke.sh <lang1> <lang2> ...
./scripts/activate-langs.sh scripts/init.sh <lang1> <lang2> ...
./scripts/activate-langs.sh lefthook.yml <lang1> <lang2> ...
```

If any selected languages do NOT have built-in template blocks (not in: typescript, go, python, swift, kotlin), manually add equivalent content following the same approach as projd-create step 6b:

**`lefthook.yml`** -- add a pre-commit command block under `pre-commit.commands`:
```yaml
    <tool-name>:
      glob: "**/*.<ext>"
      run: <lint/format command> {staged_files}
```

**`scripts/smoke.sh`** -- add `run_check` lines after `# --- Local checks ---`:
```bash
run_check "<name>" <command>
```

**`scripts/init.sh`** -- add dependency install lines after `# --- Dependencies ---`:
```bash
if [ -f <manifest-file> ]; then
    <install command>
    echo "[ok] <Language> dependencies installed"
fi
```

If the user chose "None -- skip language hooks", skip this entire step.

### 7. Merge .claude/settings.json

Read the existing `.claude/settings.json` if it exists. If it does not exist, start with an empty `{}`.

**Base mode (Developer):**

Merge these entries:

- Add to `permissions.allow` (deduplicate -- do not add entries that already exist):
  ```json
  "Bash(./scripts/skill-context.sh:*)",
  "Bash(git *)"
  ```

- Set `statusLine` (if the key does not already exist):
  ```json
  "statusLine": {
    "type": "command",
    "command": "\"$CLAUDE_PROJECT_DIR\"/scripts/statusline.sh"
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
  "Bash(./scripts/*)",
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

Write the merged result back to `.claude/settings.json`.

### 8. Create agent.json

Build `agent.json` from interview answers:

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

If `agent.json` already exists, read it and warn the user: "An agent.json already exists. It will be overwritten with your new settings." Then write the new file. The old values are not merged -- the user just configured fresh values in the interview.

### 9. Update CLAUDE.md

Read the existing `CLAUDE.md`. If it does not exist, create an empty one.

Append the projd sections at the end of the file, wrapped in sentinel comments. The content between the sentinels is the standard projd workflow documentation.

Use the Edit tool to append this block at the very end of the file:

```markdown

<!-- projd:begin -->
<!-- projd workflow sections -- do not edit between these markers -->

## Agent Controls

Read `agent.json` before any git operation. It defines what you are allowed to do:

[... full Agent Controls section from template CLAUDE.md ...]

## Session Conventions

[... full Session Conventions section with all subsections ...]

## Sub-Projects

[... full Sub-Projects section ...]

## Pre-Commit Quality Gates

[... full Pre-Commit Quality Gates section ...]

## Code Conventions

- Never use emojis in code or comments
- Use `git -C <path>` instead of `cd <path> && git` when running git commands in another directory. This avoids compound shell commands and matches the `Bash(git *)` auto-approve rule.

<!-- projd:end -->
```

To get the exact content: read the template CLAUDE.md from the temp clone directory. Extract everything from `## Agent Controls` to the end of the file. Wrap it with the sentinel comments and append to the existing CLAUDE.md.

**Important**: Read the template CLAUDE.md from the temp clone (not the project's existing CLAUDE.md) to get the canonical projd sections.

### 10. Create directories and metadata

```bash
mkdir -p progress .projd
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
./scripts/init.sh
```

Then run validation (allow it to fail -- warnings about missing features in `progress/` are expected):

```bash
./scripts/validate.sh || true
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
  Config:  agent.json, lefthook.yml, .claude/settings.json (merged)
  CLAUDE.md updated with projd workflow sections

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
- When merging settings.json, preserve all existing entries. Only add, never remove.
- When updating CLAUDE.md, only append -- never modify or remove existing content.
