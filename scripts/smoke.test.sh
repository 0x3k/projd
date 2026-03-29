#!/usr/bin/env bash
set -euo pipefail

# smoke.test.sh -- Tests for scripts/smoke.sh
#
# Creates temporary project directories, copies and modifies smoke.sh,
# then verifies run_check behavior, target filtering, and sub-project
# aggregation.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SMOKE_SH="$SCRIPT_DIR/smoke.sh"
LIB_SH="$SCRIPT_DIR/lib.sh"

TESTS_PASSED=0
TESTS_FAILED=0
TMPDIR_ROOT=""

# -- Helpers --

setup_tmpdir() {
    TMPDIR_ROOT="$(mktemp -d)"
}

cleanup_tmpdir() {
    if [ -n "$TMPDIR_ROOT" ] && [ -d "$TMPDIR_ROOT" ]; then
        rm -rf "$TMPDIR_ROOT"
    fi
    TMPDIR_ROOT=""
}

# Create a minimal project with smoke.sh, optionally appending extra lines.
# Usage: make_project <project_dir> [extra_lines...]
make_project() {
    local project_dir="$1"
    shift
    mkdir -p "$project_dir/scripts"
    cp "$SMOKE_SH" "$project_dir/scripts/smoke.sh"
    cp "$LIB_SH" "$project_dir/scripts/lib.sh"
    chmod +x "$project_dir/scripts/smoke.sh" "$project_dir/scripts/lib.sh"
    # Append any extra run_check lines before the summary block
    if [ $# -gt 0 ]; then
        local extra="$1"
        # Write extra lines to a temp file, then use sed to insert before summary
        local extra_file
        extra_file="$(mktemp)"
        printf '%s\n' "$extra" > "$extra_file"
        local tmp
        tmp="$(mktemp)"
        # Insert contents of extra_file right before the summary comment
        while IFS= read -r line; do
            if [ "$line" = "# --- Summary ---" ]; then
                cat "$extra_file"
                echo ""
            fi
            printf '%s\n' "$line"
        done < "$project_dir/scripts/smoke.sh" > "$tmp"
        mv "$tmp" "$project_dir/scripts/smoke.sh"
        chmod +x "$project_dir/scripts/smoke.sh"
        rm -f "$extra_file"
    fi
}

assert_exit_code() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"
    if [ "$expected" -eq "$actual" ]; then
        echo "[PASS] $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "[FAIL] $test_name (expected exit $expected, got $actual)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

assert_output_contains() {
    local test_name="$1"
    local expected_substring="$2"
    local output="$3"
    if echo "$output" | grep -qF "$expected_substring"; then
        echo "[PASS] $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "[FAIL] $test_name (output missing: '$expected_substring')"
        echo "       actual output: $output"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

assert_output_not_contains() {
    local test_name="$1"
    local unexpected_substring="$2"
    local output="$3"
    if echo "$output" | grep -qF "$unexpected_substring"; then
        echo "[FAIL] $test_name (output unexpectedly contains: '$unexpected_substring')"
        echo "       actual output: $output"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    else
        echo "[PASS] $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    fi
}

# -- Tests --

test_no_active_checks() {
    echo ""
    echo "=== Test: no active checks ==="
    setup_tmpdir
    make_project "$TMPDIR_ROOT/proj"

    local output exit_code=0
    output="$("$TMPDIR_ROOT/proj/scripts/smoke.sh" 2>&1)" || exit_code=$?

    assert_exit_code "no checks -- exits 0" 0 "$exit_code"
    assert_output_contains "no checks -- reports 0 passed 0 failed" \
        "0 passed, 0 failed" "$output"

    cleanup_tmpdir
}

test_one_passing_check() {
    echo ""
    echo "=== Test: one passing check ==="
    setup_tmpdir
    make_project "$TMPDIR_ROOT/proj" 'run_check "mycheck" true'

    local output exit_code=0
    output="$("$TMPDIR_ROOT/proj/scripts/smoke.sh" 2>&1)" || exit_code=$?

    assert_exit_code "one pass -- exits 0" 0 "$exit_code"
    assert_output_contains "one pass -- reports 1 passed" \
        "1 passed, 0 failed" "$output"
    assert_output_contains "one pass -- shows PASS label" \
        "[PASS] mycheck" "$output"

    cleanup_tmpdir
}

test_one_failing_check() {
    echo ""
    echo "=== Test: one failing check ==="
    setup_tmpdir
    make_project "$TMPDIR_ROOT/proj" 'run_check "badcheck" false'

    local output exit_code=0
    output="$("$TMPDIR_ROOT/proj/scripts/smoke.sh" 2>&1)" || exit_code=$?

    assert_exit_code "one fail -- exits 1" 1 "$exit_code"
    assert_output_contains "one fail -- reports 1 failed" \
        "0 passed, 1 failed" "$output"
    assert_output_contains "one fail -- shows FAIL label" \
        "[FAIL] badcheck" "$output"

    cleanup_tmpdir
}

test_mixed_pass_and_fail() {
    echo ""
    echo "=== Test: mixed pass and fail ==="
    setup_tmpdir
    local checks
    checks="$(printf '%s\n%s' 'run_check "good" true' 'run_check "bad" false')"
    make_project "$TMPDIR_ROOT/proj" "$checks"

    local output exit_code=0
    output="$("$TMPDIR_ROOT/proj/scripts/smoke.sh" 2>&1)" || exit_code=$?

    assert_exit_code "mixed -- exits 1" 1 "$exit_code"
    assert_output_contains "mixed -- reports 1 passed 1 failed" \
        "1 passed, 1 failed" "$output"

    cleanup_tmpdir
}

test_target_filter_runs_matching() {
    echo ""
    echo "=== Test: target filter runs matching check ==="
    setup_tmpdir
    local checks
    checks="$(printf '%s\n%s' 'run_check "lint" true' 'run_check "typecheck" false')"
    make_project "$TMPDIR_ROOT/proj" "$checks"

    # Run with target "lint" -- should only run lint (which passes)
    local output exit_code=0
    output="$("$TMPDIR_ROOT/proj/scripts/smoke.sh" lint 2>&1)" || exit_code=$?

    assert_exit_code "filter -- exits 0 (only lint runs)" 0 "$exit_code"
    assert_output_contains "filter -- reports 1 passed" \
        "1 passed, 0 failed" "$output"
    assert_output_contains "filter -- lint ran" \
        "[PASS] lint" "$output"
    assert_output_not_contains "filter -- typecheck skipped" \
        "typecheck" "$output"

    cleanup_tmpdir
}

test_target_filter_runs_failing_match() {
    echo ""
    echo "=== Test: target filter runs failing matching check ==="
    setup_tmpdir
    local checks
    checks="$(printf '%s\n%s' 'run_check "lint" true' 'run_check "typecheck" false')"
    make_project "$TMPDIR_ROOT/proj" "$checks"

    # Run with target "typecheck" -- should only run typecheck (which fails)
    local output exit_code=0
    output="$("$TMPDIR_ROOT/proj/scripts/smoke.sh" typecheck 2>&1)" || exit_code=$?

    assert_exit_code "filter fail -- exits 1" 1 "$exit_code"
    assert_output_contains "filter fail -- reports 1 failed" \
        "0 passed, 1 failed" "$output"
    assert_output_not_contains "filter fail -- lint skipped" \
        "lint" "$output"

    cleanup_tmpdir
}

test_subproject_aggregation_pass() {
    echo ""
    echo "=== Test: sub-project aggregation (all pass) ==="
    setup_tmpdir

    local root="$TMPDIR_ROOT/proj"
    make_project "$root"

    # Create a sub-project with a passing smoke.sh
    local sub="$root/services/api"
    mkdir -p "$sub/scripts"
    cat > "$sub/scripts/smoke.sh" <<'SUBEOF'
#!/usr/bin/env bash
set -euo pipefail
echo "sub-project api smoke ok"
exit 0
SUBEOF
    chmod +x "$sub/scripts/smoke.sh"

    # Create projects.json at root
    cat > "$root/projects.json" <<'PJEOF'
{
  "projects": [
    { "path": "services/api" }
  ]
}
PJEOF

    local output exit_code=0
    output="$("$root/scripts/smoke.sh" 2>&1)" || exit_code=$?

    assert_exit_code "subproject pass -- exits 0" 0 "$exit_code"
    assert_output_contains "subproject pass -- shows sub-project header" \
        "=== services/api ===" "$output"
    assert_output_contains "subproject pass -- reports 1 passed" \
        "1 passed, 0 failed" "$output"

    cleanup_tmpdir
}

test_subproject_aggregation_fail() {
    echo ""
    echo "=== Test: sub-project failure propagates ==="
    setup_tmpdir

    local root="$TMPDIR_ROOT/proj"
    make_project "$root"

    # Create a sub-project with a failing smoke.sh
    local sub="$root/services/broken"
    mkdir -p "$sub/scripts"
    cat > "$sub/scripts/smoke.sh" <<'SUBEOF'
#!/usr/bin/env bash
set -euo pipefail
echo "sub-project broken smoke failed"
exit 1
SUBEOF
    chmod +x "$sub/scripts/smoke.sh"

    # Create projects.json at root
    cat > "$root/projects.json" <<'PJEOF'
{
  "projects": [
    { "path": "services/broken" }
  ]
}
PJEOF

    local output exit_code=0
    output="$("$root/scripts/smoke.sh" 2>&1)" || exit_code=$?

    assert_exit_code "subproject fail -- exits 1" 1 "$exit_code"
    assert_output_contains "subproject fail -- shows sub-project header" \
        "=== services/broken ===" "$output"
    assert_output_contains "subproject fail -- reports 1 failed" \
        "0 passed, 1 failed" "$output"

    cleanup_tmpdir
}

test_subproject_skipped_with_target_filter() {
    echo ""
    echo "=== Test: sub-project aggregation skipped when target is not 'all' ==="
    setup_tmpdir

    local root="$TMPDIR_ROOT/proj"
    local checks='run_check "lint" true'
    make_project "$root" "$checks"

    # Create a sub-project that would fail if run
    local sub="$root/services/api"
    mkdir -p "$sub/scripts"
    cat > "$sub/scripts/smoke.sh" <<'SUBEOF'
#!/usr/bin/env bash
set -euo pipefail
exit 1
SUBEOF
    chmod +x "$sub/scripts/smoke.sh"

    cat > "$root/projects.json" <<'PJEOF'
{
  "projects": [
    { "path": "services/api" }
  ]
}
PJEOF

    # Target filter should skip sub-project aggregation
    local output exit_code=0
    output="$("$root/scripts/smoke.sh" lint 2>&1)" || exit_code=$?

    assert_exit_code "filter skips subproject -- exits 0" 0 "$exit_code"
    assert_output_not_contains "filter skips subproject -- no sub-project header" \
        "=== services/api ===" "$output"
    assert_output_contains "filter skips subproject -- lint passed" \
        "1 passed, 0 failed" "$output"

    cleanup_tmpdir
}

# -- Run all tests --

echo "Running smoke.sh tests..."

test_no_active_checks
test_one_passing_check
test_one_failing_check
test_mixed_pass_and_fail
test_target_filter_runs_matching
test_target_filter_runs_failing_match
test_subproject_aggregation_pass
test_subproject_aggregation_fail
test_subproject_skipped_with_target_filter

echo ""
echo "=== Results: $TESTS_PASSED passed, $TESTS_FAILED failed ==="

if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
fi
