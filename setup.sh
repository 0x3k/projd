#!/usr/bin/env bash
set -euo pipefail

# setup.sh -- Configure the boilerplate for your project.
#
# Interactive:  ./setup.sh
# Scripted:     ./setup.sh --name my-app --lang typescript --desc "My app"
#
# Supported languages: typescript, go, python, swift, kotlin

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

SUPPORTED_LANGS="typescript go python swift kotlin"

# --- Parse flags ---
NAME=""
LANG=""
DESC=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --name) NAME="$2"; shift 2 ;;
        --lang) LANG="$2"; shift 2 ;;
        --desc|--description) DESC="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: ./setup.sh [--name NAME] [--lang LANG] [--desc DESCRIPTION]"
            echo ""
            echo "Supported languages: $SUPPORTED_LANGS"
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

if [ -z "$LANG" ]; then
    echo "Supported languages: $SUPPORTED_LANGS"
    read -rp "Language: " LANG
fi

if [ -z "$DESC" ]; then
    read -rp "One-line description: " DESC
fi

# --- Validate ---
if [ -z "$NAME" ]; then
    echo "ERROR: project name is required"
    exit 1
fi

VALID=false
for L in $SUPPORTED_LANGS; do
    if [ "$LANG" = "$L" ]; then
        VALID=true
        break
    fi
done

if [ "$VALID" = false ]; then
    echo "ERROR: unsupported language '$LANG'"
    echo "Supported: $SUPPORTED_LANGS"
    exit 1
fi

echo ""
echo "=== Configuring project ==="
echo "  Name:     $NAME"
echo "  Language: $LANG"
echo "  Desc:     $DESC"
echo ""

# --- Activate language blocks ---
# Files use markers like:
#   # [typescript]
#   # commented code...
#   # [/typescript]
#
# For the selected language: uncomment the block (remove "# " prefix).
# For other languages: delete the block entirely.

activate_lang() {
    local file="$1"
    local lang="$2"
    local tmpfile
    tmpfile=$(mktemp)

    awk -v lang="$lang" '
    BEGIN { skip = 0; uncomment = 0; blank = 0 }
    {
        # Opening tag: # [langname]
        if ($0 ~ /# \[[a-z]+\]$/ && $0 !~ /\//) {
            tag = $0
            gsub(/.*\[/, "", tag)
            gsub(/\].*/, "", tag)
            if (tag == lang) {
                uncomment = 1
            } else {
                skip = 1
            }
            next
        }
        # Closing tag: # [/langname]
        if ($0 ~ /# \[\/[a-z]+\]/) {
            skip = 0
            uncomment = 0
            next
        }
        if (skip) next
        if (uncomment) {
            sub(/# /, "")
        }
        # Collapse consecutive blank lines
        if ($0 ~ /^[[:space:]]*$/) {
            if (!blank) { print; blank = 1 }
            next
        }
        blank = 0
        print
    }
    ' "$file" > "$tmpfile"

    # Preserve executable bit
    if [ -x "$file" ]; then
        chmod +x "$tmpfile"
    fi
    mv "$tmpfile" "$file"
}

for f in lefthook.yml scripts/smoke.sh scripts/init.sh; do
    if [ -f "$f" ]; then
        activate_lang "$f" "$LANG"
        echo "[ok] Activated $LANG blocks in $f"
    fi
done

# --- Remove placeholder command and setup comment from lefthook.yml ---
if [ -f lefthook.yml ]; then
    tmpfile=$(mktemp)
    awk '
    /placeholder:/ { skip = 1; next }
    skip && /run:/ { skip = 0; next }
    skip { next }
    /activated by \.\/setup\.sh/ { next }
    /delete the placeholder/ { next }
    { print }
    ' lefthook.yml > "$tmpfile"
    mv "$tmpfile" lefthook.yml
    echo "[ok] Removed placeholder from lefthook.yml"
fi

# --- Update CLAUDE.md ---
if [ -f CLAUDE.md ]; then
    case "$LANG" in
        typescript) LANG_DISPLAY="TypeScript" ;;
        go) LANG_DISPLAY="Go" ;;
        python) LANG_DISPLAY="Python" ;;
        swift) LANG_DISPLAY="Swift" ;;
        kotlin) LANG_DISPLAY="Kotlin" ;;
        *) LANG_DISPLAY="$LANG" ;;
    esac

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

# --- Self-remove ---
rm -- "$0"
echo "[ok] Removed setup.sh (no longer needed)"
