#!/usr/bin/env bash
set -euo pipefail

# Test suite for check-git-policy.sh
# Run: bash .claude/hooks/check-git-policy.test.sh
# Make executable: chmod +x .claude/hooks/check-git-policy.test.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/check-git-policy.sh"

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

# Create a temp git repo with an initial commit and a .projd/agent.json.
# Usage: create_repo [branch_to_checkout]
# Sets REPO_DIR to the created directory.
create_repo() {
    local branch="${1:-}"
    REPO_DIR="$TMPDIR_ROOT/repo-${TOTAL}"
    mkdir -p "$REPO_DIR/.projd"
    git -C "$REPO_DIR" init -q
    git -C "$REPO_DIR" config user.email "test@test.com"
    git -C "$REPO_DIR" config user.name "Test"

    # Write default .projd/agent.json
    cat > "$REPO_DIR/.projd/agent.json" <<'AGENT'
{
  "git": {
    "branch_prefix": "agent/",
    "protected_branches": ["main", "master"],
    "allow_push": "feature",
    "allow_force_push": false,
    "auto_commit": true
  }
}
AGENT

    # Initial commit so HEAD exists and we are on main
    git -C "$REPO_DIR" add .projd/agent.json
    git -C "$REPO_DIR" commit -q -m "initial commit"

    if [ -n "$branch" ]; then
        git -C "$REPO_DIR" checkout -q -b "$branch"
    fi
}

# Build the JSON payload and pipe it to the hook.
# Usage: run_hook <cwd> <command>
# Sets HOOK_EXIT, HOOK_OUT.
run_hook() {
    local cwd="$1"
    local command="$2"
    local payload
    payload=$(jq -n --arg cmd "$command" --arg cwd "$cwd" '{
        tool_input: { command: $cmd },
        cwd: $cwd
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

echo "Running check-git-policy.sh tests..."
echo ""

# ---- 1. Non-git command passes through ----
echo "Test group: non-git commands"
create_repo
run_hook "$REPO_DIR" "npm install"
assert_allowed "non-git command passes through"

run_hook "$REPO_DIR" "echo hello"
assert_allowed "echo command passes through"

# ---- 2. Git command with no .projd/agent.json passes through ----
echo ""
echo "Test group: no .projd/agent.json"
create_repo
rm "$REPO_DIR/.projd/agent.json"
run_hook "$REPO_DIR" "git push origin main"
assert_allowed "git push with no .projd/agent.json passes through"

# ---- 3. Force push blocked when allow_force_push=false ----
echo ""
echo "Test group: force push"
create_repo "agent/feat"
run_hook "$REPO_DIR" "git push --force origin agent/feat"
assert_denied "force push --force blocked" "Force push blocked"

run_hook "$REPO_DIR" "git push -f origin agent/feat"
assert_denied "force push -f blocked" "Force push blocked"

# ---- 4. Force push allowed when allow_force_push=true ----
create_repo "agent/feat"
cat > "$REPO_DIR/.projd/agent.json" <<'AGENT'
{
  "git": {
    "branch_prefix": "agent/",
    "protected_branches": ["main", "master"],
    "allow_push": "feature",
    "allow_force_push": true,
    "auto_commit": true
  }
}
AGENT
run_hook "$REPO_DIR" "git push --force origin agent/feat"
assert_allowed "force push allowed when allow_force_push=true"

# ---- 5. Push blocked when allow_push=false ----
echo ""
echo "Test group: push policies"
create_repo "agent/feat"
cat > "$REPO_DIR/.projd/agent.json" <<'AGENT'
{
  "git": {
    "branch_prefix": "agent/",
    "protected_branches": ["main", "master"],
    "allow_push": false,
    "allow_force_push": false,
    "auto_commit": true
  }
}
AGENT
run_hook "$REPO_DIR" "git push origin agent/feat"
assert_denied "push blocked when allow_push=false" "Push blocked"

# ---- 6. Push allowed on feature branch when allow_push=feature ----
create_repo "agent/my-feature"
run_hook "$REPO_DIR" "git push origin agent/my-feature"
assert_allowed "push allowed on feature branch with correct prefix"

# ---- 7. Push blocked on non-prefixed branch when allow_push=feature ----
create_repo "my-branch"
run_hook "$REPO_DIR" "git push origin my-branch"
assert_denied "push blocked on non-prefixed branch" "does not start with prefix"

# ---- 8. Push to protected branch name blocked ----
create_repo "agent/feat"
run_hook "$REPO_DIR" "git push origin agent/feat:main"
assert_denied "push to protected branch via refspec blocked" "protected branch"

run_hook "$REPO_DIR" "git push origin main"
assert_denied "push to protected branch name as arg blocked" "protected branch"

# ---- 9. Push allowed when allow_push=true ----
create_repo "random-branch"
cat > "$REPO_DIR/.projd/agent.json" <<'AGENT'
{
  "git": {
    "branch_prefix": "agent/",
    "protected_branches": ["main", "master"],
    "allow_push": true,
    "allow_force_push": false,
    "auto_commit": true
  }
}
AGENT
run_hook "$REPO_DIR" "git push origin random-branch"
assert_allowed "push allowed when allow_push=true"

# ---- 10. Commit on protected branch blocked ----
echo ""
echo "Test group: commit on protected branch"
create_repo  # stays on main
run_hook "$REPO_DIR" "git commit -m 'some change'"
assert_denied "commit on main blocked" "Cannot commit directly to protected branch"

# ---- 11. Commit on feature branch allowed ----
create_repo "agent/feat"
run_hook "$REPO_DIR" "git commit -m 'some change'"
assert_allowed "commit on feature branch allowed"

# ---- 12. Branch creation without prefix blocked (checkout -b) ----
echo ""
echo "Test group: branch creation prefix"
create_repo
run_hook "$REPO_DIR" "git checkout -b my-feature"
assert_denied "checkout -b without prefix blocked" "Branch must use prefix"

# ---- 13. Branch creation with prefix allowed (checkout -b) ----
create_repo
run_hook "$REPO_DIR" "git checkout -b agent/my-feature"
assert_allowed "checkout -b with prefix allowed"

# ---- 14. git branch <name> without prefix blocked ----
create_repo
run_hook "$REPO_DIR" "git branch my-feature"
assert_denied "git branch without prefix blocked" "Branch must use prefix"

# Branch creation with prefix via git branch allowed
run_hook "$REPO_DIR" "git branch agent/my-feature"
assert_allowed "git branch with prefix allowed"

# ---- 15. Merge into protected branch blocked ----
echo ""
echo "Test group: merge policies"
create_repo  # on main
run_hook "$REPO_DIR" "git merge agent/feat"
assert_denied "merge into main blocked" "Cannot merge into protected branch"

# ---- 16. Merge on feature branch allowed ----
create_repo "agent/feat"
run_hook "$REPO_DIR" "git merge some-other-branch"
assert_allowed "merge on feature branch allowed"

# ---- 17. Git command after shell operator still caught ----
echo ""
echo "Test group: git after shell operators"
create_repo  # on main
run_hook "$REPO_DIR" "echo foo && git commit -m 'sneaky'"
assert_denied "git commit after && on protected branch blocked" "Cannot commit directly to protected branch"

create_repo "agent/feat"
cat > "$REPO_DIR/.projd/agent.json" <<'AGENT'
{
  "git": {
    "branch_prefix": "agent/",
    "protected_branches": ["main", "master"],
    "allow_push": false,
    "allow_force_push": false,
    "auto_commit": true
  }
}
AGENT
run_hook "$REPO_DIR" "ls -la; git push origin agent/feat"
assert_denied "git push after ; still caught" "Push blocked"

# ---- Additional: switch -c without prefix blocked ----
echo ""
echo "Test group: switch -c branch creation"
create_repo
run_hook "$REPO_DIR" "git switch -c my-feature"
assert_denied "switch -c without prefix blocked" "Branch must use prefix"

run_hook "$REPO_DIR" "git switch -c agent/my-feature"
assert_allowed "switch -c with prefix allowed"

# ---------------------------------------------------------------------------
# Results
# ---------------------------------------------------------------------------

echo ""
echo "============================================"
echo "Results: $PASS passed, $FAIL failed, $TOTAL total"
echo "============================================"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi

echo "All tests passed."
exit 0
