# Hook Architecture

projd enforces git policies from `agent.json` through two independent layers: a Claude Code PreToolUse hook (primary) and a Lefthook pre-push hook (secondary). Together they ensure the agent cannot violate branch protection, push restrictions, or naming conventions -- even if it tries multiple approaches. A third hook (path guard) is available for vibes mode to prevent file operations outside the project directory.

## PreToolUse Hook (Primary)

**File**: `.claude/hooks/check-git-policy.sh`
**Configured in**: `.claude/settings.json`
**Timeout**: 10 seconds

This hook runs before every bash command that Claude Code executes. It receives the command as JSON on stdin and either exits silently (allow) or returns a JSON deny decision (block).

### How it works

1. Claude Code is about to run a bash command (e.g., `git push origin agent/my-feature`)
2. The hook receives JSON: `{"tool_name": "Bash", "tool_input": {"command": "git push origin agent/my-feature"}}`
3. The hook reads `agent.json` to get the current policy
4. It checks the command against each policy rule
5. If any rule is violated, it returns: `{"decision": "block", "reason": "..."}`
6. If all rules pass, it exits 0 with no output (command proceeds)

### What it checks

| Check | Trigger | Rule |
|-------|---------|------|
| Force push | Command contains `--force` or `-f` with `push` | Blocked if `allow_force_push` is `false` |
| Push target | Any `git push` command | Blocked if `allow_push` is `false`. If `"feature"`, branch must match `branch_prefix`. Protected branches always blocked. |
| Direct commit | `git commit` on a protected branch | Blocked (exception: initial commit when HEAD doesn't exist) |
| Branch creation | `git checkout -b`, `git switch -c`, or `git branch` | Branch name must start with `branch_prefix` |
| Merge to protected | `git merge` while on a protected branch | Blocked (enforces PR-only merging) |

### Refspec handling

The hook handles git push refspecs correctly. For `git push origin src:dst`, it checks the destination ref against push policy, not the source. For bare `git push origin branch-name`, it checks the branch name directly.

### Edge cases

- **Initial commit**: When `git rev-parse HEAD` fails (no commits yet), direct commits are allowed on any branch. This lets `setup.sh` and `/projd-create` make the first commit.
- **Missing agent.json**: If `agent.json` doesn't exist or can't be parsed, the hook exits silently (allows everything). This prevents the hook from blocking work in repos that haven't been configured.
- **Non-git commands**: The hook only inspects commands that start with `git`. All other commands pass through immediately.

## Lefthook Pre-Push Hook (Secondary)

**File**: `lefthook.yml` (under `pre-push`)
**Installed by**: `./scripts/init.sh` (via `lefthook install`)

This hook runs when `git push` is invoked directly in the terminal -- outside of Claude Code. It provides the same push-policy enforcement as a safety net.

### What it checks

- If `allow_push` is `false`: blocks all pushes with a message suggesting `git push --no-verify` to override.
- If `allow_push` is `"feature"`: checks that the current branch starts with `branch_prefix`. Blocks pushes from non-matching branches and from protected branches.

### Override

The pre-push hook can be bypassed with `git push --no-verify`. This is intentional -- it's a guard for the operator, not a hard lock. The PreToolUse hook has no bypass.

## Path Guard Hook (Vibes Mode)

**File**: `.claude/hooks/check-path-guard.sh`
**Configured by**: `/projd-create` (vibes mode) and `/projd-adopt` (vibes mode)
**Timeout**: 10 seconds

In vibes mode, most tools are auto-approved. The path guard hook prevents the agent from reading, writing, or deleting files outside the project directory -- catching `..` traversal, absolute path escapes, and symlink tricks.

### How it works

1. For Claude tools (`Read`, `Write`, `Edit`): checks that `tool_input.file_path` resolves to a path inside the project root
2. For Bash commands (`rm`, `cp`, `mv`, `cat`, `head`, `tail`, `touch`, `chmod`): extracts file arguments and checks each resolves inside the project root
3. Path resolution handles relative paths, `..` components, and symlinks by walking up to the nearest existing ancestor directory

### What it checks

| Tool type | Check |
|-----------|-------|
| `Read`, `Write`, `Edit` | `file_path` must resolve inside the project directory |
| `rm`, `cp`, `mv`, `cat`, `head`, `tail`, `touch`, `chmod` | All file arguments must resolve inside the project directory |

### When it's enabled

This hook is NOT enabled by default. It is added to `.claude/settings.json` only when vibes mode is selected during `/projd-create` or `/projd-adopt`. In developer mode, the standard permission prompts provide sufficient protection.

When enabled, it is configured with two matchers -- one for Bash commands and one for file tools:

```json
{
  "matcher": "Bash",
  "hooks": [
    { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/check-path-guard.sh", "timeout": 10 }
  ]
},
{
  "matcher": "Read|Write|Edit",
  "hooks": [
    { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/check-path-guard.sh", "timeout": 10 }
  ]
}
```

## Configuration

Both hooks read from the same `agent.json`:

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

Changes to `agent.json` take effect immediately -- both hooks read it fresh on every invocation. There is no cache to invalidate.

## Settings

The PreToolUse hook is configured in `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
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
    ]
  }
}
```

The `matcher` restricts the hook to `Bash` tool calls only. Other tools (Read, Edit, Write, etc.) are not intercepted. The `$CLAUDE_PROJECT_DIR` variable ensures the hook is found regardless of the current working directory.

## Debugging

To test the hook manually, pipe a JSON command to it:

```bash
# Should be blocked (push to protected branch):
echo '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}' | .claude/hooks/check-git-policy.sh

# Should be allowed (push to feature branch):
echo '{"tool_name":"Bash","tool_input":{"command":"git push origin agent/my-feature"}}' | .claude/hooks/check-git-policy.sh

# Should be blocked (branch without prefix):
echo '{"tool_name":"Bash","tool_input":{"command":"git checkout -b no-prefix"}}' | .claude/hooks/check-git-policy.sh
```

Blocked commands produce JSON output. Allowed commands produce no output (exit 0).
