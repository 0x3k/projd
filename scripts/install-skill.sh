#!/usr/bin/env bash
set -euo pipefail

# install-skill.sh -- Install, check, or remove projd user-level skills.
#
# Installs both /projd-create and /projd-adopt to ~/.claude/skills/,
# plus an auto-updater that checks for new versions once per day.
#
# Usage:
#   ./scripts/install-skill.sh           Install or update all skills
#   ./scripts/install-skill.sh --check   Show diff if already installed
#   ./scripts/install-skill.sh --remove  Remove all installed skills

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

SKILLS=("projd-create" "projd-adopt")

MODE="install"
case "${1:-}" in
    --check)  MODE="check" ;;
    --remove) MODE="remove" ;;
    --help|-h)
        echo "Usage:"
        echo "  ./scripts/install-skill.sh           Install or update all skills"
        echo "  ./scripts/install-skill.sh --check   Show diff if already installed"
        echo "  ./scripts/install-skill.sh --remove  Remove all installed skills"
        echo ""
        echo "Skills: ${SKILLS[*]}"
        exit 0
        ;;
    "")       MODE="install" ;;
    *)        echo "Unknown flag: $1 (try --help)"; exit 1 ;;
esac

# --- Resolve remote URL (needed for install mode) ---
REMOTE_URL=""
if [ "$MODE" != "remove" ]; then
    REMOTE_URL="$(git -C "$PROJECT_DIR" remote get-url origin 2>/dev/null)" || true
    if [ -z "$REMOTE_URL" ] && [ "$MODE" = "install" ]; then
        echo "ERROR: No git remote 'origin' found."
        echo "Push the boilerplate to GitHub first, then re-run this script."
        exit 1
    fi
fi

for SKILL in "${SKILLS[@]}"; do
    SOURCE="$PROJECT_DIR/.claude/skills/$SKILL/SKILL.md"
    TARGET_DIR="$HOME/.claude/skills/$SKILL"
    TARGET="$TARGET_DIR/SKILL.md"

    echo "--- $SKILL ---"

    # --- Remove mode ---
    if [ "$MODE" = "remove" ]; then
        if [ ! -f "$TARGET" ]; then
            echo "  Not installed. Nothing to remove."
        else
            rm "$TARGET"
            rmdir "$TARGET_DIR" 2>/dev/null || true
            echo "  Removed /$SKILL from $TARGET_DIR"
        fi
        continue
    fi

    # --- Verify source exists ---
    if [ ! -f "$SOURCE" ]; then
        echo "  Source SKILL.md not found at $SOURCE -- skipping."
        continue
    fi

    # --- Build content with placeholders replaced ---
    CONTENT="$(sed "s|{{BOILERPLATE_REMOTE_URL}}|$REMOTE_URL|g" "$SOURCE")"
    CONTENT="$(echo "$CONTENT" | sed "s|{{BOILERPLATE_LOCAL_PATH}}|$PROJECT_DIR|g")"

    if echo "$CONTENT" | grep -q '{{BOILERPLATE_REMOTE_URL}}'; then
        echo "  ERROR: Placeholder replacement failed -- skipping."
        continue
    fi

    # --- Check mode ---
    if [ "$MODE" = "check" ]; then
        if [ ! -f "$TARGET" ]; then
            echo "  Not installed."
        else
            DIFF="$(diff "$TARGET" <(echo "$CONTENT") || true)"
            if [ -z "$DIFF" ]; then
                echo "  Already up to date."
            else
                echo "  Changes between installed and current:"
                echo ""
                echo "$DIFF"
            fi
        fi
        continue
    fi

    # --- Install mode ---
    if [ -f "$TARGET" ]; then
        DIFF="$(diff "$TARGET" <(echo "$CONTENT") || true)"
        if [ -z "$DIFF" ]; then
            echo "  Already up to date. No changes."
            continue
        fi
        echo "  Skill already installed. Updating."
    fi

    mkdir -p "$TARGET_DIR"
    echo "$CONTENT" > "$TARGET"
    echo "  Installed /$SKILL to $TARGET"
done

# --- Auto-updater ---
UPDATER="$HOME/.claude/skills/.projd-updater.sh"
UPDATER_CACHE="$HOME/.claude/skills/.projd-cache"

build_updater_body() {
    local body
    body=$(cat << 'UPDATER_EOF'
#!/usr/bin/env bash
set -euo pipefail
# projd auto-updater -- checks for skill updates at most once per day.
# Installed by install-skill.sh. Called from skill context commands.

REMOTE="__PROJD_REMOTE__"
LOCAL="__PROJD_LOCAL__"
DIR="$HOME/.claude/skills"
CACHE="$DIR/.projd-cache"
STAMP="$CACHE/last-check"

# Rate limit: at most once per 24 hours
NOW=$(date +%s)
if [ -f "$STAMP" ]; then
    LAST=$(cat "$STAMP")
    [ $((NOW - LAST)) -lt 86400 ] && exit 0
fi

# Fetch latest template
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
if ! git clone --depth 1 "$REMOTE" "$T" 2>/dev/null; then
    if [ -n "$LOCAL" ] && [ -d "$LOCAL" ]; then
        git clone --depth 1 "$LOCAL" "$T" 2>/dev/null || exit 0
    else
        exit 0
    fi
fi

mkdir -p "$CACHE"
echo "$NOW" > "$STAMP"

# Compare and update each skill
UPDATED=""
for S in projd-create projd-adopt; do
    SRC="$T/.claude/skills/$S/SKILL.md"
    DST="$DIR/$S/SKILL.md"
    [ ! -f "$SRC" ] && continue
    [ ! -f "$DST" ] && continue
    NEW=$(sed "s|{{BOILERPLATE_REMOTE_URL}}|$REMOTE|g" "$SRC" | sed "s|{{BOILERPLATE_LOCAL_PATH}}|$LOCAL|g")
    if ! diff -q <(echo "$NEW") "$DST" >/dev/null 2>&1; then
        echo "$NEW" > "$DST"
        UPDATED="$UPDATED $S"
    fi
done

[ -n "$UPDATED" ] && echo "PROJD_UPDATED:$UPDATED updated to latest version. Re-run the command."
UPDATER_EOF
)
    body="${body//__PROJD_REMOTE__/$REMOTE_URL}"
    body="${body//__PROJD_LOCAL__/$PROJECT_DIR}"
    echo "$body"
}

if [ "$MODE" = "remove" ]; then
    echo "--- updater ---"
    if [ -f "$UPDATER" ]; then
        rm "$UPDATER"
        rm -rf "$UPDATER_CACHE" 2>/dev/null || true
        echo "  Removed $UPDATER"
    else
        echo "  Not installed. Nothing to remove."
    fi
elif [ "$MODE" = "install" ]; then
    UPDATER_BODY="$(build_updater_body)"

    echo "--- updater ---"
    if [ -f "$UPDATER" ]; then
        DIFF="$(diff "$UPDATER" <(echo "$UPDATER_BODY") || true)"
        if [ -z "$DIFF" ]; then
            echo "  Already up to date. No changes."
        else
            echo "$UPDATER_BODY" > "$UPDATER"
            chmod +x "$UPDATER"
            echo "  Updated $UPDATER"
        fi
    else
        echo "$UPDATER_BODY" > "$UPDATER"
        chmod +x "$UPDATER"
        echo "  Installed to $UPDATER"
    fi
elif [ "$MODE" = "check" ]; then
    echo "--- updater ---"
    if [ ! -f "$UPDATER" ]; then
        echo "  Not installed."
    else
        UPDATER_BODY="$(build_updater_body)"
        DIFF="$(diff "$UPDATER" <(echo "$UPDATER_BODY") || true)"
        if [ -z "$DIFF" ]; then
            echo "  Already up to date."
        else
            echo "  Changes between installed and current:"
            echo ""
            echo "$DIFF"
        fi
    fi
fi
