#!/usr/bin/env bash
set -euo pipefail

# setup.sh -- Configure the boilerplate for your project.
#
# Interactive:  ./setup.sh
# Scripted:     ./setup.sh --name my-app --lang typescript --desc "My app"
#
# Languages with built-in template support: typescript, go, python, swift, kotlin
# Any language is accepted; unsupported ones skip template activation.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

TEMPLATE_LANGS="typescript go python swift kotlin"

# --- Parse flags ---
NAME=""
LANGS=""
DESC=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --name) NAME="$2"; shift 2 ;;
        --lang) LANGS="$2"; shift 2 ;;
        --desc|--description) DESC="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: ./setup.sh [--name NAME] [--lang LANG[,LANG,...]] [--desc DESCRIPTION]"
            echo ""
            echo "Languages with template support: $TEMPLATE_LANGS"
            echo "Any language is accepted (comma-separated for multiple)."
            echo ""
            echo "If flags are omitted, you will be prompted interactively."
            exit 0
            ;;
        *) echo "Unknown flag: $1 (try --help)"; exit 1 ;;
    esac
done

# --- Interactive prompts for missing values ---
if [ -z "$NAME" ]; then
    read -rp "Project name: " NAME
fi

if [ -z "$LANGS" ]; then
    echo "Languages with template support: $TEMPLATE_LANGS"
    echo "Any language is accepted (comma-separated for multiple, e.g. go,python)"
    read -rp "Language(s): " LANGS
fi

if [ -z "$DESC" ]; then
    read -rp "One-line description: " DESC
fi

# --- Validate ---
if [ -z "$NAME" ]; then
    echo "ERROR: project name is required"
    exit 1
fi

# Normalize: strip spaces, convert comma-separated to space-separated
LANGS=$(echo "$LANGS" | tr ',' ' ' | xargs)

if [ -z "$LANGS" ]; then
    echo "ERROR: at least one language is required"
    exit 1
fi

# Note languages without built-in template blocks
for L in $LANGS; do
    HAS_TEMPLATE=false
    for T in $TEMPLATE_LANGS; do
        if [ "$L" = "$T" ]; then
            HAS_TEMPLATE=true
            break
        fi
    done
    if [ "$HAS_TEMPLATE" = false ]; then
        echo "NOTE: '$L' has no template blocks -- add lint/smoke/init config manually"
    fi
done

echo ""
echo "=== Configuring project ==="
echo "  Name:      $NAME"
echo "  Languages: $LANGS"
echo "  Desc:      $DESC"
echo ""

# --- Activate language blocks ---
# Delegates to scripts/activate-langs.sh which handles uncommenting
# selected language blocks and removing unselected ones.

for f in lefthook.yml scripts/smoke.sh scripts/init.sh; do
    if [ -f "$f" ]; then
        ./scripts/activate-langs.sh "$f" $LANGS
    fi
done
echo "[ok] Activated language blocks in template files"

# --- Update CLAUDE.md ---
if [ -f CLAUDE.md ]; then
    LANG_DISPLAY=""
    for L in $LANGS; do
        case "$L" in
            typescript) D="TypeScript" ;;
            go) D="Go" ;;
            python) D="Python" ;;
            swift) D="Swift" ;;
            kotlin) D="Kotlin" ;;
            rust) D="Rust" ;;
            java) D="Java" ;;
            ruby) D="Ruby" ;;
            *) D="$L" ;;
        esac
        if [ -z "$LANG_DISPLAY" ]; then
            LANG_DISPLAY="$D"
        else
            LANG_DISPLAY="$LANG_DISPLAY, $D"
        fi
    done

    # Remove the template guard section (between "## Template Guard" and "---")
    tmpfile=$(mktemp)
    awk '
    /^## Template Guard/ { skip = 1; next }
    skip && /^---$/ { skip = 0; next }
    skip { next }
    { print }
    ' CLAUDE.md > "$tmpfile"
    mv "$tmpfile" CLAUDE.md

    tmpfile=$(mktemp)
    awk -v name="$NAME" -v lang="$LANG_DISPLAY" -v desc="$DESC" '
    /^\*\*Name\*\*:/ { print "**Name**: " name; next }
    /^\*\*Language\*\*:/ { print "**Language**: " lang; next }
    /^\*\*Purpose\*\*:/ { print "**Purpose**: " desc; next }
    { print }
    ' CLAUDE.md > "$tmpfile"
    mv "$tmpfile" CLAUDE.md
    echo "[ok] Updated project overview in CLAUDE.md"
fi

# --- Remove example feature ---
if [ -f progress/example-feature.json ]; then
    rm progress/example-feature.json
    echo "[ok] Removed example feature from progress/"
    echo ""
    echo "[action needed] Add your feature files to progress/"
    echo "  Example: progress/my-feature.json"
fi

# --- Run init.sh ---
echo ""
if [ -x scripts/init.sh ]; then
    echo "--- Running scripts/init.sh ---"
    ./scripts/init.sh
fi

# --- Run validate.sh ---
echo ""
if [ -x scripts/validate.sh ]; then
    echo "--- Running scripts/validate.sh ---"
    ./scripts/validate.sh || true
fi

echo ""
echo "=== Setup complete ==="
echo ""
echo "Next steps:"
echo "  1. Fill in Build & Dev Commands and Architecture in CLAUDE.md"
echo "  2. Run /projd-plan to create feature files, or add them manually to progress/"
echo "  3. Run ./scripts/validate.sh to verify everything is configured"

# --- Generate upgrade manifest ---
mkdir -p .projd

# Store the template source for future upgrades
REMOTE_URL=$(git remote get-url origin 2>/dev/null || true)
if [ -n "$REMOTE_URL" ]; then
    echo "$REMOTE_URL" > .projd/source
fi

# Compute checksums of template infrastructure files
TEMPLATE_FILES=(
    ".claude/hooks/check-git-policy.sh"
    ".claude/hooks/check-path-guard.sh"
    ".claude/skills/projd-start/SKILL.md"
    ".claude/skills/projd-end/SKILL.md"
    ".claude/skills/projd-plan/SKILL.md"
    ".claude/skills/projd-hands-on/SKILL.md"
    ".claude/skills/projd-hands-off/SKILL.md"
    "scripts/init.sh"
    "scripts/monitor.sh"
    "scripts/skill-context.sh"
    "scripts/smoke.sh"
    "scripts/status.sh"
    "scripts/statusline.sh"
    "scripts/validate.sh"
    "scripts/upgrade.sh"
    "scripts/activate-langs.sh"
    "lefthook.yml"
)
: > .projd/manifest
for tf in "${TEMPLATE_FILES[@]}"; do
    if [ -f "$tf" ]; then
        cs=$(shasum -a 256 "$tf" | awk '{print $1}')
        printf '%s\t%s\n' "$tf" "$cs" >> .projd/manifest
    fi
done
echo "[ok] Generated upgrade manifest (.projd/manifest)"

# --- Remove template files ---
rm -f README.md LICENSE scripts/install-skill.sh
rm -rf .claude/skills/projd-create .claude/skills/projd-adopt
rm -- "$0"
echo "[ok] Removed template files (README.md, LICENSE, install-skill.sh, projd-create/adopt skills, setup.sh)"

# --- Create project README ---
cat > README.md << READMEEOF
# $NAME

$DESC

## Getting Started

See \`CLAUDE.md\` for build commands and project details.
READMEEOF
echo "[ok] Created README.md"
