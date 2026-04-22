#!/usr/bin/env bash
set -euo pipefail

# Test suite for check-worktree-isolation.sh
# Run: bash .claude/hooks/check-worktree-isolation.test.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/check-worktree-isolation.sh"

PASS=0
FAIL=0
TOTAL=0

TMPDIR_ROOT=""

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

setup_tmpdir() {
    TMPDIR_ROOT=$(mktemp -d)
}

cleanup_tmpdir() {
    if [ -n "$TMPDIR_ROOT" ] && [ -d "$TMPDIR_ROOT" ]; then
        rm -rf "$TMPDIR_ROOT"
    fi
}

trap cleanup_tmpdir EXIT

# Create a temp "repo" with a worktree skeleton.
# Usage: create_repo
# Sets REPO_DIR (main repo root) and WT_DIR (active worktree) globals.
create_repo() {
    REPO_DIR="$TMPDIR_ROOT/repo-${TOTAL}"
    mkdir -p "$REPO_DIR/internal/api"
    mkdir -p "$REPO_DIR/.claude/worktrees/agent-foo/internal/api"
    mkdir -p "$REPO_DIR/.claude/worktrees/agent-bar"
    WT_DIR="$REPO_DIR/.claude/worktrees/agent-foo"
}

# Build the JSON payload and pipe it to the hook.
# Usage: run_hook <tool> <cwd> <file_path>
# Sets HOOK_EXIT, HOOK_OUT.
run_hook() {
    local tool="$1"
    local cwd="$2"
    local file_path="$3"
    local payload
    payload=$(jq -n \
        --arg tool "$tool" \
        --arg cwd "$cwd" \
        --arg fp "$file_path" \
        '{
            tool_name: $tool,
            cwd: $cwd,
            tool_input: { file_path: $fp }
        }')
    HOOK_OUT=$(echo "$payload" | bash "$HOOK" 2>&1) && HOOK_EXIT=0 || HOOK_EXIT=$?
}

assert_allowed() {
    local label="$1"
    TOTAL=$((TOTAL + 1))
    if [ "$HOOK_EXIT" -eq 0 ] && [ -z "$HOOK_OUT" ]; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: $label (expected allow, got exit=$HOOK_EXIT, output='$HOOK_OUT')"
    fi
}

assert_denied() {
    local label="$1"
    local reason_fragment="${2:-}"
    TOTAL=$((TOTAL + 1))
    if [ "$HOOK_EXIT" -eq 0 ] && echo "$HOOK_OUT" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' &>/dev/null; then
        if [ -n "$reason_fragment" ]; then
            if echo "$HOOK_OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason' | grep -qF "$reason_fragment"; then
                PASS=$((PASS + 1))
                echo "  PASS: $label"
            else
                FAIL=$((FAIL + 1))
                local actual_reason
                actual_reason=$(echo "$HOOK_OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason')
                echo "  FAIL: $label (denied, but reason missing '$reason_fragment'; got '$actual_reason')"
            fi
        else
            PASS=$((PASS + 1))
            echo "  PASS: $label"
        fi
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: $label (expected deny, got exit=$HOOK_EXIT, output='$HOOK_OUT')"
    fi
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

setup_tmpdir

echo "Running check-worktree-isolation.sh tests..."
echo ""

# ---- 1. Non-guarded tools pass through ----
echo "Test group: non-guarded tools"
create_repo
run_hook "Bash" "$WT_DIR" "$REPO_DIR/internal/api/x.go"
assert_allowed "Bash tool passes through even from worktree CWD"

run_hook "Read" "$WT_DIR" "$REPO_DIR/internal/api/x.go"
assert_allowed "Read tool passes through (not a write)"

# ---- 2. Session not in a worktree is a no-op ----
echo ""
echo "Test group: non-worktree session"
create_repo
run_hook "Write" "$REPO_DIR" "$REPO_DIR/internal/api/x.go"
assert_allowed "Write from main repo CWD to main repo path"

run_hook "Edit" "$REPO_DIR" "/tmp/somefile.go"
assert_allowed "Edit from main repo CWD to /tmp"

# ---- 3. Writes inside the active worktree are allowed ----
echo ""
echo "Test group: writes inside active worktree"
create_repo
run_hook "Write" "$WT_DIR" "$WT_DIR/internal/api/new.go"
assert_allowed "Write to absolute path inside worktree"

run_hook "Edit" "$WT_DIR" "internal/api/new.go"
assert_allowed "Edit to relative path inside worktree"

run_hook "Write" "$WT_DIR/internal/api" "new.go"
assert_allowed "Write to bare filename relative to nested worktree dir"

# ---- 4. Writes outside the project tree are allowed ----
echo ""
echo "Test group: writes outside project tree"
create_repo
run_hook "Write" "$WT_DIR" "/tmp/scratch.go"
assert_allowed "Write to /tmp from worktree session"

run_hook "Edit" "$WT_DIR" "$HOME/.claude/memory/note.md"
assert_allowed "Edit to ~/.claude from worktree session"

# ---- 5. Writes into the main repo tree are denied ----
echo ""
echo "Test group: main-repo leaks (should deny)"
create_repo
run_hook "Write" "$WT_DIR" "$REPO_DIR/internal/api/leaked.go"
assert_denied "Write to absolute path in main repo" "outside the active worktree"

run_hook "Edit" "$WT_DIR" "$REPO_DIR/internal/api/leaked.go"
assert_denied "Edit to absolute path in main repo" "outside the active worktree"

# ---- 6. Traversal back to main repo via `..` is denied ----
echo ""
echo "Test group: traversal escapes (should deny)"
create_repo
run_hook "Write" "$WT_DIR" "../../../internal/api/leaked.go"
assert_denied "Relative traversal back to main repo" "outside the active worktree"

# ---- 7. Sibling-worktree writes are denied ----
echo ""
echo "Test group: sibling worktree writes (should deny)"
create_repo
run_hook "Write" "$WT_DIR" "$REPO_DIR/.claude/worktrees/agent-bar/x.go"
assert_denied "Write into sibling worktree" "outside the active worktree"

# ---- 8. Missing anchors -> allow (conservative) ----
echo ""
echo "Test group: missing anchors"
create_repo
rm -rf "$WT_DIR"
# CWD references a now-removed worktree; hook should fail-open rather than block legit work.
run_hook "Write" "$WT_DIR" "$REPO_DIR/internal/api/x.go"
assert_allowed "Allow when worktree anchor is missing"

# ---- 9. NotebookEdit is guarded like Write/Edit ----
echo ""
echo "Test group: NotebookEdit"
create_repo
run_hook "NotebookEdit" "$WT_DIR" "$WT_DIR/nb.ipynb"
assert_allowed "NotebookEdit inside worktree"

run_hook "NotebookEdit" "$WT_DIR" "$REPO_DIR/nb.ipynb"
assert_denied "NotebookEdit leak to main repo" "outside the active worktree"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "======================================="
echo "Total: $TOTAL, Passed: $PASS, Failed: $FAIL"
echo "======================================="

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
