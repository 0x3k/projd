# Parallel Agents

## Dispatch

`/projd-hands-off` reads `dispatch.max_agents` from `agent.json` (default **20**). If more features are eligible than the limit, they are dispatched in waves -- the next batch starts after the current one completes. Each agent runs in its own git worktree with its own feature branch, so there are no write conflicts.

Use `--dry-run` to preview which features would be dispatched and in what order before committing to a run.

## Auto-review

When `dispatch.auto_review` is `true`, a reviewer agent is spawned for each completed PR. The reviewer runs smoke tests, verifies acceptance criteria, and merges passing PRs. If it finds issues, it fixes trivial ones inline and spawns a subagent for larger fixes. PRs that still fail after fixes are flagged for manual review.

## Monitoring

### Status line

The Claude Code status line shows feature progress at a glance, updated after every assistant message:

```
Opus 4.6  main  42%  |  3/7  2 wip  |  2 agents  |  15.2k/4.8k tok  +156/-23  12m
```

It reads `progress/*.json` files and counts active git worktrees, so when parallel agents update feature status or create/remove worktrees, the status line reflects it on the next refresh. The status line is configured in `.claude/settings.json` and powered by `scripts/statusline.sh`.

### Monitor dashboard

For a detailed live view, run the monitor from another terminal:

```bash
./scripts/monitor.sh            # interactive dashboard (default 5s refresh)
./scripts/monitor.sh --once     # print snapshot and exit (non-interactive)
./scripts/monitor.sh --watch    # auto-refresh every 5 seconds
./scripts/monitor.sh --watch 3  # auto-refresh every 3 seconds
```

The monitor shows:

- **Progress bar** with weighted completion percentage and token totals
- **Feature table** with columns: FEATURE, STATE, WAVE, TOKENS, DETAILS
- **Active worktrees** with branch names
- **Open PRs** from agent branches

### Monitor navigation

Navigate features with arrow keys or `j`/`k`, act on the selected feature with single-key commands:

| Key | Action |
|-----|--------|
| `Up`/`k` | Move selection up |
| `Down`/`j` | Move selection down |
| `d` | Feature details (JSON, commits, diff stats) |
| `l` | Recent commits on the feature branch |
| `p` | Open the feature's PR in browser |
| `r` | Reset feature to pending |
| `c` | Mark feature complete |
| `x` | Remove the feature's worktree |
| `m` | Merge the feature's PR |
| `/` | Refresh now |
| `q` | Quit |
