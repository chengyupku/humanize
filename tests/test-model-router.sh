#!/bin/bash
# Tests for model-router.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"
source "$PROJECT_ROOT/scripts/lib/model-router.sh"

SAFE_BASE_PATH="/usr/bin:/bin:/usr/sbin:/sbin"

echo "=========================================="
echo "Model Router Tests"
echo "=========================================="
echo ""

create_mock_binary() {
    local bin_dir="$1"
    local binary_name="$2"

    mkdir -p "$bin_dir"
    cat > "$bin_dir/$binary_name" <<EOF
#!/bin/bash
exit 0
EOF
    chmod +x "$bin_dir/$binary_name"
}

assert_detects_codex() {
    local model_name="$1"
    local label="$2"
    local result=""
    local exit_code=0

    result=$(detect_provider "$model_name" 2>/dev/null) || exit_code=$?
    if [[ $exit_code -eq 0 ]] && [[ "$result" == "codex" ]]; then
        pass "$label"
    else
        fail "$label" "exit 0 + codex" "exit=$exit_code, output=$result"
    fi
}

echo "--- Test 1: Codex model routing ---"
echo ""
assert_detects_codex "gpt-5.3-codex" "detect_provider: gpt-5.3-codex returns codex"
assert_detects_codex "gpt-4o" "detect_provider: gpt-4o returns codex"
assert_detects_codex "o3-mini" "detect_provider: o3-mini returns codex"
assert_detects_codex "o1-pro" "detect_provider: o1-pro returns codex"
assert_detects_codex "o4-mini" "detect_provider: o4-mini returns codex"

echo ""
echo "--- Test 2: Unsupported models fail ---"
echo ""

exit_code=0
stderr_out=$(detect_provider "haiku" 2>&1 >/dev/null) || exit_code=$?
if [[ $exit_code -ne 0 ]] && echo "$stderr_out" | grep -qiE "codex model|unknown model|error"; then
    pass "detect_provider: non-Codex model fails with helpful error"
else
    fail "detect_provider: non-Codex model fails with helpful error" "non-zero exit + helpful error" "exit=$exit_code, stderr=$stderr_out"
fi

exit_code=0
stderr_out=$(detect_provider "unknown-xyz" 2>&1 >/dev/null) || exit_code=$?
if [[ $exit_code -ne 0 ]] && echo "$stderr_out" | grep -qiE "unknown|error"; then
    pass "detect_provider: unknown model exits non-zero with error"
else
    fail "detect_provider: unknown model exits non-zero with error" "non-zero exit + error message" "exit=$exit_code, stderr=$stderr_out"
fi

exit_code=0
stderr_out=$(detect_provider "" 2>&1 >/dev/null) || exit_code=$?
if [[ $exit_code -ne 0 ]] && echo "$stderr_out" | grep -qiE "non-empty|error"; then
    pass "detect_provider: empty model exits non-zero with error"
else
    fail "detect_provider: empty model exits non-zero with error" "non-zero exit + error message" "exit=$exit_code, stderr=$stderr_out"
fi

echo ""
echo "--- Test 3: Codex dependency checks ---"
echo ""

setup_test_dir
BIN_DIR="$TEST_DIR/bin"
create_mock_binary "$BIN_DIR" "codex"

if PATH="$BIN_DIR:$SAFE_BASE_PATH" check_provider_dependency "codex" >/dev/null 2>&1; then
    pass "check_provider_dependency: codex succeeds when mock codex is in PATH"
else
    fail "check_provider_dependency: codex succeeds when mock codex is in PATH" "exit 0" "non-zero exit"
fi

exit_code=0
stderr_out=$(PATH="$SAFE_BASE_PATH" check_provider_dependency "codex" 2>&1 >/dev/null) || exit_code=$?
if [[ $exit_code -ne 0 ]] && echo "$stderr_out" | grep -qi "codex"; then
    pass "check_provider_dependency: codex fails when codex is missing"
else
    fail "check_provider_dependency: codex fails when codex is missing" "non-zero exit + codex in stderr" "exit=$exit_code, stderr=$stderr_out"
fi

echo ""
echo "--- Test 4: Effort mapping is Codex-only passthrough ---"
echo ""

for effort in xhigh high medium low; do
    result=""
    exit_code=0
    result=$(map_effort "$effort" "codex" 2>/dev/null) || exit_code=$?
    if [[ $exit_code -eq 0 ]] && [[ "$result" == "$effort" ]]; then
        pass "map_effort: $effort passes through for codex"
    else
        fail "map_effort: $effort passes through for codex" "exit 0 + $effort" "exit=$exit_code, output=$result"
    fi
done

exit_code=0
stderr_out=$(map_effort "ultra" "codex" 2>&1 >/dev/null) || exit_code=$?
if [[ $exit_code -ne 0 ]] && echo "$stderr_out" | grep -qiE "unknown effort|error"; then
    pass "map_effort: unknown codex effort exits non-zero with error"
else
    fail "map_effort: unknown codex effort exits non-zero with error" "non-zero exit + error message" "exit=$exit_code, stderr=$stderr_out"
fi

exit_code=0
stderr_out=$(map_effort "high" "claude" 2>&1 >/dev/null) || exit_code=$?
if [[ $exit_code -ne 0 ]] && echo "$stderr_out" | grep -qiE "expected 'codex'|unknown target provider|error"; then
    pass "map_effort: non-codex target provider exits non-zero with error"
else
    fail "map_effort: non-codex target provider exits non-zero with error" "non-zero exit + error message" "exit=$exit_code, stderr=$stderr_out"
fi

print_test_summary "Model Router Test Summary"
