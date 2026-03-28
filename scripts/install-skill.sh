#!/usr/bin/env bash
set -euo pipefail

# install-skill.sh -- Install, check, or remove the /projd-create user-level skill.
#
# Usage:
#   ./scripts/install-skill.sh           Install or update the skill
#   ./scripts/install-skill.sh --check   Show diff if already installed
#   ./scripts/install-skill.sh --remove  Remove the installed skill

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

SOURCE="$PROJECT_DIR/.claude/skills/projd-create/SKILL.md"
TARGET_DIR="$HOME/.claude/skills/projd-create"
TARGET="$TARGET_DIR/SKILL.md"

MODE="install"
case "${1:-}" in
    --check)  MODE="check" ;;
    --remove) MODE="remove" ;;
    --help|-h)
        echo "Usage:"
        echo "  ./scripts/install-skill.sh           Install or update the skill"
        echo "  ./scripts/install-skill.sh --check   Show diff if already installed"
        echo "  ./scripts/install-skill.sh --remove  Remove the installed skill"
        exit 0
        ;;
    "")       MODE="install" ;;
    *)        echo "Unknown flag: $1 (try --help)"; exit 1 ;;
esac

# --- Remove mode ---
if [ "$MODE" = "remove" ]; then
    if [ ! -f "$TARGET" ]; then
        echo "Not installed. Nothing to remove."
        exit 0
    fi
    rm "$TARGET"
    rmdir "$TARGET_DIR" 2>/dev/null || true
    echo "Removed /projd-create skill from $TARGET_DIR"
    exit 0
fi

# --- Verify source exists ---
if [ ! -f "$SOURCE" ]; then
    echo "ERROR: Source SKILL.md not found at $SOURCE"
    exit 1
fi

# --- Resolve remote URL ---
REMOTE_URL="$(git -C "$PROJECT_DIR" remote get-url origin 2>/dev/null)" || true
if [ -z "$REMOTE_URL" ]; then
    echo "ERROR: No git remote 'origin' found."
    echo "Push the boilerplate to GitHub first, then re-run this script."
    exit 1
fi

# --- Build content with placeholders replaced ---
CONTENT="$(sed "s|{{BOILERPLATE_REMOTE_URL}}|$REMOTE_URL|g" "$SOURCE")"
CONTENT="$(echo "$CONTENT" | sed "s|{{BOILERPLATE_LOCAL_PATH}}|$PROJECT_DIR|g")"

if echo "$CONTENT" | grep -q '{{BOILERPLATE_REMOTE_URL}}'; then
    echo "ERROR: Placeholder replacement failed."
    exit 1
fi

# --- Check mode ---
if [ "$MODE" = "check" ]; then
    if [ ! -f "$TARGET" ]; then
        echo "Not installed."
        exit 0
    fi
    DIFF="$(diff "$TARGET" <(echo "$CONTENT") || true)"
    if [ -z "$DIFF" ]; then
        echo "Already up to date."
    else
        echo "Changes between installed and current:"
        echo ""
        echo "$DIFF"
    fi
    exit 0
fi

# --- Install mode ---
if [ -f "$TARGET" ]; then
    DIFF="$(diff "$TARGET" <(echo "$CONTENT") || true)"
    if [ -z "$DIFF" ]; then
        echo "Already up to date. No changes."
        exit 0
    fi
    echo "Skill already installed at $TARGET"
    echo ""
    echo "Changes:"
    echo "$DIFF"
    echo ""
    read -rp "Overwrite? [y/N] " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
fi

mkdir -p "$TARGET_DIR"
echo "$CONTENT" > "$TARGET"
echo "Installed /projd-create skill to $TARGET"
