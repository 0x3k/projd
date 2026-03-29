# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## Template Guard

**If the Project Name below is still `my-project`, this is the uninitialized projd template -- not a real project.** Do NOT follow the session conventions, feature workflow, or agent controls in `.claude/CLAUDE.md`. They are meant for initialized projects and will not work here.

Instead, help the user get started. There are two paths:

1. **Create a new project from this template** (recommended): The user should copy this directory to a new location and run setup there. Walk them through it:
   ```
   cp -r <this-directory> ~/repos/<project-name>
   cd ~/repos/<project-name>
   rm -rf .git && git init
   ./setup.sh
   ```
   Or, if the `/projd-create` skill is installed, they can run that from any session and it handles everything.

2. **Use this directory as the project**: If the user wants to turn this copy into their project directly, run `./setup.sh` here. It will prompt for a name, language, and description, then configure everything.

After setup completes, this guard no longer applies -- the project name will have been replaced and the rest of this file becomes active.

**Stop here and help the user. Do not read further until the project is initialized.**

---

## Project Overview

**Name**: my-project
**Language**: <!-- e.g., TypeScript, Go, Python, Swift -->
**Purpose**: <!-- One-line description -->

## Build & Dev Commands

```bash
# Install dependencies
# npm install / pip install -r requirements.txt / go mod download

# Development
# npm run dev / python main.py / go run ./cmd/server

# Build
# npm run build / go build -o server ./cmd/server

# Lint
# npm run lint / ruff check . / go vet ./...

# Type check
# npm run type-check / tsc --noEmit / mypy .

# Test
# npm test / pytest / go test ./...
```

## Architecture

## Environment Variables

| Variable | Required | Default | Purpose |
|----------|----------|---------|---------|
| `EXAMPLE_VAR` | yes | - | Example description |

## Key Patterns

## Code Conventions
