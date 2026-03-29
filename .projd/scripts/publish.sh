#!/usr/bin/env bash
set -euo pipefail

# publish.sh -- Publish the npm package using an automation token.
#
# Reads NPM_TOKEN from .env and publishes with a temporary .npmrc
# so the token bypasses 2FA without touching the user's global config.
#
# Usage:
#   ./.projd/scripts/publish.sh           # publish current version
#   ./.projd/scripts/publish.sh --dry-run # preview without publishing

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
cd "$PROJECT_DIR"

DRY_RUN=false
if [ "${1:-}" = "--dry-run" ]; then
    DRY_RUN=true
fi

# --- Load token ---
if [ -z "${NPM_TOKEN:-}" ]; then
    if [ -f "$PROJECT_DIR/.env" ]; then
        # shellcheck disable=SC1091
        source "$PROJECT_DIR/.env"
    fi
fi

if [ -z "${NPM_TOKEN:-}" ]; then
    echo -e "${RED}NPM_TOKEN not set. Add it to .env:${R}"
    echo "  NPM_TOKEN=npm_<your-automation-token>"
    exit 1
fi

# --- Publish ---
TMPRC=$(mktemp)
trap 'rm -f "$TMPRC"' EXIT
echo "//registry.npmjs.org/:_authToken=${NPM_TOKEN}" > "$TMPRC"

VERSION=$(jq -r '.version' package.json)
echo -e "${DIM}Publishing @0x3k/projd@${VERSION}...${R}"

if [ "$DRY_RUN" = true ]; then
    npm publish --access public --userconfig "$TMPRC" --dry-run
else
    npm publish --access public --userconfig "$TMPRC"
    echo -e "${GRN}Published @0x3k/projd@${VERSION}${R}"
fi
