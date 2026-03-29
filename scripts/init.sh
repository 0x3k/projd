#!/usr/bin/env bash
set -euo pipefail

# init.sh -- Bootstrap the development environment.
#
# Run this once after cloning (or after ./setup.sh) to install
# dependencies, set up git hooks, and verify the project builds.
# Idempotent -- safe to re-run.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

echo "=== Initializing project ==="

# --- Git hooks (Lefthook) ---
if command -v lefthook &>/dev/null; then
    lefthook install
    echo "[ok] Lefthook hooks installed"
else
    echo "[warn] Lefthook not found -- install with: brew install lefthook"
    echo "       Pre-commit hooks will not run until Lefthook is installed."
fi

# --- Claude Code hooks ---
if [ -d .claude/hooks ]; then
    chmod +x .claude/hooks/*.sh 2>/dev/null
    echo "[ok] Claude Code hook scripts marked executable"
fi

# --- Dependencies (activated by ./setup.sh) ---

# [typescript]
# if [ -f package.json ]; then
#     npm install
#     echo "[ok] npm dependencies installed"
# fi
# [/typescript]

# [go]
# if [ -f go.mod ]; then
#     go mod download
#     echo "[ok] Go dependencies downloaded"
# fi
# [/go]

# [python]
# if [ ! -d .venv ]; then
#     python3 -m venv .venv
#     echo "[ok] Python venv created"
# fi
# source .venv/bin/activate
# if [ -f requirements.txt ]; then
#     pip install -r requirements.txt
#     echo "[ok] Python dependencies installed"
# fi
# [/python]

# [swift]
# if [ -f Package.swift ]; then
#     swift package resolve
#     echo "[ok] Swift dependencies resolved"
# fi
# [/swift]

# [kotlin]
# if [ -f build.gradle ] || [ -f build.gradle.kts ]; then
#     ./gradlew dependencies
#     echo "[ok] Gradle dependencies downloaded"
# fi
# [/kotlin]

# --- Sub-projects ---
if [ -f projects.json ]; then
    for dir in $(jq -r '.projects[].path' projects.json); do
        if [ -x "$dir/scripts/init.sh" ]; then
            echo ""
            echo "=== Initializing $dir ==="
            (cd "$dir" && ./scripts/init.sh)
        fi
    done
fi

echo ""
echo "=== Init complete ==="
echo "Run ./scripts/smoke.sh to verify everything works."
