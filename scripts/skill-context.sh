#!/usr/bin/env bash
set -euo pipefail

# skill-context.sh -- Print project context for skill load-time.
#
# Each subcommand outputs one section of context.
# Skills call this instead of inline shell to avoid permission errors
# from compound expressions in !` ` blocks.
#
# Usage:
#   ./scripts/skill-context.sh features
#   ./scripts/skill-context.sh agent-json
#   ./scripts/skill-context.sh claude-md
#   ./scripts/skill-context.sh branch
#   ./scripts/skill-context.sh git-status
#   ./scripts/skill-context.sh git-diff-stat
#   ./scripts/skill-context.sh handoff
#   ./scripts/skill-context.sh status
#   ./scripts/skill-context.sh smoke
#   ./scripts/skill-context.sh gh-auth

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

cmd="${1:-help}"

case "$cmd" in
    features)
        found=false
        for f in progress/*.json; do
            if [ -f "$f" ]; then
                found=true
                jq -c '{id, name, status, priority, blocked_by, branch}' "$f" 2>/dev/null || true
            fi
        done
        if [ "$found" = false ]; then
            echo "none"
        fi
        ;;
    agent-json)
        if [ -f agent.json ]; then
            cat agent.json
        else
            echo "not found"
        fi
        ;;
    claude-md)
        if [ -f CLAUDE.md ]; then
            head -30 CLAUDE.md
        else
            echo "no CLAUDE.md"
        fi
        ;;
    branch)
        git branch --show-current 2>/dev/null || echo "detached"
        ;;
    git-status)
        git status --short 2>/dev/null || echo "not a git repo"
        ;;
    git-diff-stat)
        git diff --stat 2>/dev/null
        ;;
    handoff)
        if [ -f HANDOFF.md ]; then
            cat HANDOFF.md
        else
            echo "No HANDOFF.md -- clean start."
        fi
        ;;
    status)
        if [ -x scripts/status.sh ]; then
            ./scripts/status.sh 2>&1 || echo "status.sh failed"
        else
            echo "scripts/status.sh not found"
        fi
        ;;
    smoke)
        if [ -x scripts/smoke.sh ]; then
            ./scripts/smoke.sh 2>&1
            echo "EXIT_CODE=$?"
        else
            echo "scripts/smoke.sh not found"
        fi
        ;;
    gh-auth)
        gh auth status 2>&1 || echo "gh: not available or not authenticated"
        ;;
    help)
        echo "Usage: $0 <subcommand>"
        echo ""
        echo "Subcommands: features agent-json claude-md branch git-status"
        echo "             git-diff-stat handoff status smoke gh-auth"
        ;;
    *)
        echo "Unknown subcommand: $cmd"
        exit 1
        ;;
esac
