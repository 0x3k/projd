# Troubleshooting

**`setup.sh` fails or lefthook not found**
Install prerequisites first: `brew install lefthook jq gh`. Then re-run `./.projd/scripts/init.sh`.

**Smoke tests fail before I've written any code**
The template ships with placeholder commands. Run `setup.sh` to activate the correct language blocks, or manually edit `lefthook.yml` and `.projd/scripts/smoke.sh` to match your toolchain.

**Hook blocks a git command I expected to work**
The PreToolUse hook reads `.projd/agent.json` on every command. Check that `branch_prefix`, `allow_push`, and `protected_branches` match your intent. You can inspect the hook logic in `.claude/hooks/check-git-policy.sh`. See [hooks.md](hooks.md) for the full architecture.

**Agent creates a branch without the prefix**
The hook enforces the prefix from `.projd/agent.json`. If the prefix was changed after the branch was created, the push will be blocked. Rename the branch: `git branch -m old-name agent/new-name`.

**`/projd-create` says placeholders not replaced**
Run `./.projd/scripts/install-skill.sh` from the template repo first. It bakes in your repo's remote URL and local path so the skill knows where to clone from.

**Feature stuck in `in_progress`**
If a session ended without running `projd-end`, the feature file won't have been updated. Manually set `"status": "pending"` and clear the `"branch"` field in the feature's JSON file to retry, or set `"status": "complete"` if the work was actually finished.

**`gh pr create` fails**
Ensure you're authenticated: `gh auth status`. The agent will still push the branch even if PR creation fails -- you can create the PR manually from GitHub.
