#!/usr/bin/env bash
set -euo pipefail

# validate.test.sh -- Tests for scripts/validate.sh
#
# Creates temporary project structures and runs validate.sh against them,
# verifying that it correctly detects valid and invalid configurations.

TESTS_PASSED=0
TESTS_FAILED=0
TEMP_DIRS=()

# -- Helpers ------------------------------------------------------------------

cleanup() {
    for d in "${TEMP_DIRS[@]+"${TEMP_DIRS[@]}"}"; do
        rm -rf "$d"
    done
}
trap cleanup EXIT

make_temp_project() {
    local dir
    dir="$(mktemp -d)"
    TEMP_DIRS+=("$dir")
    echo "$dir"
}

# Build a minimal valid project inside the given directory.
# validate.sh resolves PROJECT_DIR from its own SCRIPT_DIR, so the script
# must live at <project>/scripts/validate.sh.
setup_valid_project() {
    local dir="$1"

    # CLAUDE.md -- configured (no <!-- e.g. placeholders)
    cat > "$dir/CLAUDE.md" <<'CLEOF'
# CLAUDE.md

## Project Overview

**Name**: test-project
**Language**: Bash
**Purpose**: A test project for validate.sh

## Build & Dev Commands

```bash
# nothing
```
CLEOF

    # agent.json
    cat > "$dir/agent.json" <<'AJEOF'
{
  "git": {
    "branch_prefix": "agent/",
    "protected_branches": ["main"],
    "allow_push": "feature",
    "allow_force_push": false,
    "auto_commit": true
  }
}
AJEOF

    # lefthook.yml -- must have no placeholder: lines, must have an indented command
    cat > "$dir/lefthook.yml" <<'LHEOF'
pre-push:
  commands:
    smoke:
        run: ./scripts/smoke.sh
LHEOF

    # scripts/
    mkdir -p "$dir/scripts"

    # smoke.sh -- must be executable, must have a run_check line
    cat > "$dir/scripts/smoke.sh" <<'SSEOF'
#!/usr/bin/env bash
set -euo pipefail
run_check "echo ok"
SSEOF
    chmod +x "$dir/scripts/smoke.sh"

    # init.sh -- must be executable
    cat > "$dir/scripts/init.sh" <<'IEOF'
#!/usr/bin/env bash
echo "init"
IEOF
    chmod +x "$dir/scripts/init.sh"

    # status.sh -- must be executable
    cat > "$dir/scripts/status.sh" <<'STEOF'
#!/usr/bin/env bash
echo "status"
STEOF
    chmod +x "$dir/scripts/status.sh"

    # Copy the real validate.sh and lib.sh into the temp project
    local src_dir
    src_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    cp "$src_dir/validate.sh" "$dir/scripts/validate.sh"
    cp "$src_dir/lib.sh" "$dir/scripts/lib.sh"
    chmod +x "$dir/scripts/validate.sh" "$dir/scripts/lib.sh"

    # progress/ with a real feature file
    mkdir -p "$dir/progress"
    cat > "$dir/progress/001-feature.json" <<'FJEOF'
{
  "id": "001-feature",
  "name": "Test feature",
  "status": "pending",
  "acceptance_criteria": ["It works"]
}
FJEOF
}

# Run validate.sh in a project directory and capture output + exit code.
# Sets: VALIDATE_OUTPUT, VALIDATE_EXIT
run_validate() {
    local dir="$1"
    shift
    VALIDATE_EXIT=0
    VALIDATE_OUTPUT="$("$dir/scripts/validate.sh" "$@" 2>&1)" || VALIDATE_EXIT=$?
}

assert_exit() {
    local expected="$1"
    local test_name="$2"
    if [ "$VALIDATE_EXIT" -eq "$expected" ]; then
        echo "  [PASS] $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "  [FAIL] $test_name (expected exit $expected, got $VALIDATE_EXIT)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

assert_output_contains() {
    local pattern="$1"
    local test_name="$2"
    if echo "$VALIDATE_OUTPUT" | grep -qF "$pattern"; then
        echo "  [PASS] $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "  [FAIL] $test_name (output missing: $pattern)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

assert_output_not_contains() {
    local pattern="$1"
    local test_name="$2"
    if echo "$VALIDATE_OUTPUT" | grep -qF "$pattern"; then
        echo "  [FAIL] $test_name (output unexpectedly contains: $pattern)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    else
        echo "  [PASS] $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    fi
}

# -- Tests --------------------------------------------------------------------

echo "=== validate.sh test suite ==="
echo ""

# Test 1: Fully valid project passes with exit 0
echo "Test 1: Fully valid project"
DIR="$(make_temp_project)"
setup_valid_project "$DIR"
run_validate "$DIR"
assert_exit 0 "exits 0"
assert_output_contains "[PASS]" "has PASS lines"
assert_output_not_contains "[FAIL]" "has no FAIL lines"
assert_output_contains "0 failed" "summary shows 0 failed"
echo ""

# Test 2: Missing CLAUDE.md
echo "Test 2: Missing CLAUDE.md"
DIR="$(make_temp_project)"
setup_valid_project "$DIR"
rm "$DIR/CLAUDE.md"
run_validate "$DIR"
assert_exit 1 "exits 1"
assert_output_contains "[FAIL] file exists" "reports CLAUDE.md missing"
echo ""

# Test 3: Unconfigured CLAUDE.md (has <!-- e.g. placeholder)
echo "Test 3: Unconfigured CLAUDE.md"
DIR="$(make_temp_project)"
setup_valid_project "$DIR"
cat > "$DIR/CLAUDE.md" <<'EOF'
# CLAUDE.md

## Project Overview

**Name**: my-project
**Language**: <!-- e.g., TypeScript, Go, Python, Swift -->
**Purpose**: Something
EOF
run_validate "$DIR"
assert_exit 1 "exits 1"
assert_output_contains "[FAIL] project overview configured" "reports unconfigured overview"
echo ""

# Test 4: CLAUDE.md with <!-- Replace placeholder (warning, not failure)
echo "Test 4: CLAUDE.md with remaining placeholder sections"
DIR="$(make_temp_project)"
setup_valid_project "$DIR"
cat >> "$DIR/CLAUDE.md" <<'EOF'

## Architecture
<!-- Replace with architecture description -->
EOF
run_validate "$DIR"
assert_exit 0 "exits 0 (warn, not fail)"
assert_output_contains "[WARN] all sections filled in" "reports sections warn"
echo ""

# Test 5: Invalid agent.json (bad JSON)
echo "Test 5: Invalid agent.json"
DIR="$(make_temp_project)"
setup_valid_project "$DIR"
echo "not valid json {{{" > "$DIR/agent.json"
run_validate "$DIR"
assert_exit 1 "exits 1"
assert_output_contains "[FAIL] valid JSON" "reports invalid JSON"
echo ""

# Test 6: Missing agent.json
echo "Test 6: Missing agent.json"
DIR="$(make_temp_project)"
setup_valid_project "$DIR"
rm "$DIR/agent.json"
run_validate "$DIR"
assert_exit 1 "exits 1"
assert_output_contains "[FAIL] file exists" "reports agent.json missing"
echo ""

# Test 7: agent.json without protected_branches
echo "Test 7: agent.json without protected_branches"
DIR="$(make_temp_project)"
setup_valid_project "$DIR"
echo '{"git": {"branch_prefix": "agent/"}}' > "$DIR/agent.json"
run_validate "$DIR"
assert_exit 0 "exits 0 (warn, not fail)"
assert_output_contains "[WARN] protected branches defined" "reports missing protected_branches as warn"
echo ""

# Test 8: Missing progress directory
echo "Test 8: Missing progress directory"
DIR="$(make_temp_project)"
setup_valid_project "$DIR"
rm -rf "$DIR/progress"
run_validate "$DIR"
assert_exit 1 "exits 1"
assert_output_contains "[FAIL] directory exists" "reports progress/ missing"
echo ""

# Test 9: Progress with only example-* files
echo "Test 9: Progress with only example files"
DIR="$(make_temp_project)"
setup_valid_project "$DIR"
rm -f "$DIR/progress/001-feature.json"
cat > "$DIR/progress/example-feature.json" <<'EOF'
{
  "id": "example-feature",
  "name": "Example",
  "status": "pending",
  "acceptance_criteria": ["Example"]
}
EOF
run_validate "$DIR"
assert_exit 1 "exits 1"
assert_output_contains "[FAIL] has real feature files" "reports no real feature files"
echo ""

# Test 10: Invalid feature file (missing required fields)
echo "Test 10: Invalid feature file (missing required fields)"
DIR="$(make_temp_project)"
setup_valid_project "$DIR"
cat > "$DIR/progress/002-bad.json" <<'EOF'
{
  "id": "002-bad",
  "description": "missing name and acceptance_criteria"
}
EOF
run_validate "$DIR"
assert_exit 1 "exits 1"
assert_output_contains "[FAIL] 002-bad.json: valid schema" "reports invalid schema"
# The valid file should still pass
assert_output_contains "[PASS] 001-feature.json: valid schema" "valid file still passes"
echo ""

# Test 11: Missing lefthook.yml
echo "Test 11: Missing lefthook.yml"
DIR="$(make_temp_project)"
setup_valid_project "$DIR"
rm "$DIR/lefthook.yml"
run_validate "$DIR"
assert_exit 1 "exits 1"
assert_output_contains "[FAIL] file exists" "reports lefthook.yml missing"
echo ""

# Test 12: lefthook.yml with placeholder command
echo "Test 12: lefthook.yml with placeholder command"
DIR="$(make_temp_project)"
setup_valid_project "$DIR"
cat > "$DIR/lefthook.yml" <<'EOF'
pre-push:
  commands:
    placeholder:
        run: echo placeholder
EOF
run_validate "$DIR"
assert_exit 1 "exits 1"
assert_output_contains "[FAIL] placeholder command removed" "reports placeholder not removed"
echo ""

# Test 13: lefthook.yml with no active hook commands
echo "Test 13: lefthook.yml with no active hook commands"
DIR="$(make_temp_project)"
setup_valid_project "$DIR"
cat > "$DIR/lefthook.yml" <<'EOF'
# empty config
pre-push:
EOF
run_validate "$DIR"
assert_exit 1 "exits 1"
assert_output_contains "[FAIL] has active hook commands" "reports no active hooks"
echo ""

# Test 14: smoke.sh missing
echo "Test 14: Missing smoke.sh"
DIR="$(make_temp_project)"
setup_valid_project "$DIR"
rm "$DIR/scripts/smoke.sh"
run_validate "$DIR"
assert_exit 1 "exits 1"
assert_output_contains "[FAIL] file exists" "reports smoke.sh missing"
echo ""

# Test 15: smoke.sh not executable
echo "Test 15: smoke.sh not executable"
DIR="$(make_temp_project)"
setup_valid_project "$DIR"
chmod -x "$DIR/scripts/smoke.sh"
run_validate "$DIR"
assert_exit 1 "exits 1"
assert_output_contains "[FAIL] is executable" "reports smoke.sh not executable"
echo ""

# Test 16: smoke.sh without run_check
echo "Test 16: smoke.sh without active run_check"
DIR="$(make_temp_project)"
setup_valid_project "$DIR"
cat > "$DIR/scripts/smoke.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "no checks here"
EOF
chmod +x "$DIR/scripts/smoke.sh"
run_validate "$DIR"
assert_exit 1 "exits 1"
assert_output_contains "[FAIL] has active checks" "reports no active checks"
echo ""

# Test 17: init.sh not executable
echo "Test 17: init.sh not executable"
DIR="$(make_temp_project)"
setup_valid_project "$DIR"
chmod -x "$DIR/scripts/init.sh"
run_validate "$DIR"
assert_exit 1 "exits 1"
assert_output_contains "[FAIL] is executable" "reports init.sh not executable"
echo ""

# Test 18: status.sh not executable
echo "Test 18: status.sh not executable"
DIR="$(make_temp_project)"
setup_valid_project "$DIR"
chmod -x "$DIR/scripts/status.sh"
run_validate "$DIR"
assert_exit 1 "exits 1"
assert_output_contains "[FAIL] is executable" "reports status.sh not executable"
echo ""

# Test 19: Multiple feature files, all valid
echo "Test 19: Multiple valid feature files"
DIR="$(make_temp_project)"
setup_valid_project "$DIR"
cat > "$DIR/progress/002-second.json" <<'EOF'
{
  "id": "002-second",
  "name": "Second feature",
  "status": "pending",
  "acceptance_criteria": ["Works too"]
}
EOF
run_validate "$DIR"
assert_exit 0 "exits 0"
assert_output_contains "[PASS] 001-feature.json: valid schema" "first feature valid"
assert_output_contains "[PASS] 002-second.json: valid schema" "second feature valid"
echo ""

# Test 20: Example file coexists with real file (example is still validated for schema)
echo "Test 20: Example file alongside real file"
DIR="$(make_temp_project)"
setup_valid_project "$DIR"
cat > "$DIR/progress/example-demo.json" <<'EOF'
{
  "id": "example-demo",
  "name": "Example demo",
  "status": "pending",
  "acceptance_criteria": ["demo"]
}
EOF
run_validate "$DIR"
assert_exit 0 "exits 0"
assert_output_contains "[PASS] has real feature files" "real feature files found"
assert_output_contains "[PASS] example-demo.json: valid schema" "example file schema also checked"
echo ""

# -- Summary ------------------------------------------------------------------

echo "=== Test results: $TESTS_PASSED passed, $TESTS_FAILED failed ==="

if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
fi
