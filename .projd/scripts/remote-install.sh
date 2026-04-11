#!/usr/bin/env bash
set -euo pipefail

# remote-install.sh -- One-line installer for projd user-level skills.
#
# Clones the projd repo to a temp directory, runs install-skill.sh, cleans up.
#
# Usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/0spoon/projd/main/.projd/scripts/remote-install.sh)

REPO_URL="https://github.com/0spoon/projd.git"

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

echo "Fetching projd..."
if ! git clone --depth 1 "$REPO_URL" "$T" 2>/dev/null; then
    echo "ERROR: Failed to clone from $REPO_URL"
    exit 1
fi

"$T/.projd/scripts/install-skill.sh"
