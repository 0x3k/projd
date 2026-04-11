#!/usr/bin/env node

import {
  readFileSync,
  writeFileSync,
  mkdirSync,
  existsSync,
  unlinkSync,
  rmdirSync,
  chmodSync,
  rmSync,
} from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { homedir } from "node:os";

const __dirname = dirname(fileURLToPath(import.meta.url));
const packageDir = join(__dirname, "..");
const remoteUrl = "https://github.com/0spoon/projd.git";
const skills = ["projd-create", "projd-adopt"];
const skillsDir = join(homedir(), ".claude", "skills");

function printHelp() {
  console.log("projd -- install Claude Code skills for project management");
  console.log("");
  console.log("Usage: projd [--check | --remove | --help]");
  console.log("");
  console.log("  projd           Install or update projd skills");
  console.log("  projd --check   Show diff if already installed");
  console.log("  projd --remove  Remove all installed skills");
  console.log("");
  console.log(`Skills: ${skills.join(", ")}`);
}

function buildUpdaterBody() {
  // The local path points to where the npm package is installed.
  // For global installs this persists; for npx/pnpm dlx it is temporary.
  // The auto-updater handles missing local paths gracefully.
  const localPath = packageDir;

  return `#!/usr/bin/env bash
set -euo pipefail
# projd auto-updater -- checks for skill updates at most once per day.
# Installed by projd. Called from skill context commands.

REMOTE="${remoteUrl}"
LOCAL="${localPath}"
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
`;
}

function handleSkills(mode) {
  for (const skill of skills) {
    const source = join(packageDir, ".claude", "skills", skill, "SKILL.md");
    const targetDir = join(skillsDir, skill);
    const target = join(targetDir, "SKILL.md");

    console.log(`--- ${skill} ---`);

    if (mode === "remove") {
      if (!existsSync(target)) {
        console.log("  Not installed. Nothing to remove.");
      } else {
        unlinkSync(target);
        try {
          rmdirSync(targetDir);
        } catch {
          // directory not empty or already gone
        }
        console.log(`  Removed /${skill} from ${targetDir}`);
      }
      continue;
    }

    if (!existsSync(source)) {
      console.log(`  Source SKILL.md not found at ${source} -- skipping.`);
      continue;
    }

    let content = readFileSync(source, "utf8");
    content = content.replaceAll("{{BOILERPLATE_REMOTE_URL}}", remoteUrl);
    content = content.replaceAll("{{BOILERPLATE_LOCAL_PATH}}", packageDir);

    if (content.includes("{{BOILERPLATE_REMOTE_URL}}")) {
      console.log("  ERROR: Placeholder replacement failed -- skipping.");
      continue;
    }

    if (mode === "check") {
      if (!existsSync(target)) {
        console.log("  Not installed.");
      } else {
        const installed = readFileSync(target, "utf8");
        if (installed === content) {
          console.log("  Already up to date.");
        } else {
          console.log("  Changes detected between installed and current version.");
        }
      }
      continue;
    }

    // Install mode
    if (existsSync(target)) {
      const installed = readFileSync(target, "utf8");
      if (installed === content) {
        console.log("  Already up to date. No changes.");
        continue;
      }
      console.log("  Skill already installed. Updating.");
    }

    mkdirSync(targetDir, { recursive: true });
    writeFileSync(target, content);
    console.log(`  Installed /${skill} to ${target}`);
  }
}

function handleUpdater(mode) {
  const updater = join(skillsDir, ".projd-updater.sh");
  const updaterCache = join(skillsDir, ".projd-cache");

  console.log("--- updater ---");

  if (mode === "remove") {
    if (!existsSync(updater)) {
      console.log("  Not installed. Nothing to remove.");
    } else {
      unlinkSync(updater);
      try {
        rmSync(updaterCache, { recursive: true, force: true });
      } catch {
        // already gone
      }
      console.log(`  Removed ${updater}`);
    }
    return;
  }

  const body = buildUpdaterBody();

  if (mode === "check") {
    if (!existsSync(updater)) {
      console.log("  Not installed.");
    } else {
      const installed = readFileSync(updater, "utf8");
      if (installed === body) {
        console.log("  Already up to date.");
      } else {
        console.log("  Changes detected between installed and current version.");
      }
    }
    return;
  }

  // Install mode
  const alreadyExists = existsSync(updater);
  if (alreadyExists) {
    const installed = readFileSync(updater, "utf8");
    if (installed === body) {
      console.log("  Already up to date. No changes.");
      return;
    }
  }

  writeFileSync(updater, body);
  chmodSync(updater, 0o755);
  console.log(
    alreadyExists ? `  Updated ${updater}` : `  Installed to ${updater}`,
  );
}

function main() {
  const args = process.argv.slice(2);

  if (args.includes("--help") || args.includes("-h")) {
    printHelp();
    process.exit(0);
  }

  let mode = "install";
  for (const arg of args) {
    if (arg === "--check") mode = "check";
    else if (arg === "--remove") mode = "remove";
    else if (!arg.startsWith("-")) continue;
    else {
      console.error(`Unknown flag: ${arg} (try --help)`);
      process.exit(1);
    }
  }

  handleSkills(mode);
  handleUpdater(mode);
}

main();
