#!/bin/bash
# Tests for bitlesson-select.sh Codex routing
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"
BITLESSON_SELECT="$PROJECT_ROOT/scripts/bitlesson-select.sh"
SAFE_BASE_PATH="/usr/bin:/bin:/usr/sbin:/sbin"

echo "=========================================="
echo "Bitlesson Select Routing Tests"
echo "=========================================="
echo ""

create_mock_bitlesson() {
    local dir="$1"
    mkdir -p "$dir/.humanize"
    cat > "$dir/.humanize/bitlesson.md" <<'EOF'
# BitLesson Knowledge Base
## Entries
<!-- placeholder -->
EOF
}

create_mock_codex() {
    local bin_dir="$1"
    mkdir -p "$bin_dir"
    cat > "$bin_dir/codex" <<'EOF'
#!/bin/bash
if [[ "${*: -1}" != "-" ]]; then
    echo "mock codex expected trailing '-' to read prompt from stdin" >&2
    exit 9
fi

stdin_content=$(cat)
if [[ -z "$stdin_content" ]]; then
    echo "mock codex expected non-empty stdin prompt" >&2
    exit 10
fi

cat <<'OUT'
LESSON_IDS: NONE
RATIONALE: No matching lessons found (mock codex).
OUT
EOF
    chmod +x "$bin_dir/codex"
}

create_recording_mock_codex() {
    local bin_dir="$1"
    local stdin_file="$2"
    mkdir -p "$bin_dir"
    cat > "$bin_dir/codex" <<EOF
#!/bin/bash
if [[ "\${*: -1}" != "-" ]]; then
    echo "mock codex expected trailing '-' to read prompt from stdin" >&2
    exit 9
fi

cat > "$stdin_file"
if [[ ! -s "$stdin_file" ]]; then
    echo "mock codex expected non-empty stdin prompt" >&2
    exit 10
fi

cat <<'OUT'
LESSON_IDS: NONE
RATIONALE: No matching lessons found (mock codex).
OUT
EOF
    chmod +x "$bin_dir/codex"
}

echo "--- Test 1: Codex model routes to codex ---"
echo ""

setup_test_dir
create_mock_bitlesson "$TEST_DIR"
BIN_DIR="$TEST_DIR/bin"
create_mock_codex "$BIN_DIR"
mkdir -p "$TEST_DIR/.humanize"
printf '{"bitlesson_model": "gpt-4o"}' > "$TEST_DIR/.humanize/config.json"

result=""
exit_code=0
result=$(CODEX_PROJECT_DIR="$TEST_DIR" XDG_CONFIG_HOME="$TEST_DIR/no-user" \
    PATH="$BIN_DIR:$PATH" \
    bash "$BITLESSON_SELECT" \
    --task "Fix a bug" \
    --paths "scripts/bitlesson-select.sh" \
    --bitlesson-file "$TEST_DIR/.humanize/bitlesson.md" 2>/dev/null) || exit_code=$?

if [[ $exit_code -eq 0 ]] && echo "$result" | grep -q "LESSON_IDS:"; then
    pass "Codex model routes to codex"
else
    fail "Codex model routes to codex" "LESSON_IDS: in output (exit 0)" "exit=$exit_code, output=$result"
fi

echo ""
echo "--- Test 2: Selector passes prompt via stdin with trailing '-' ---"
echo ""

setup_test_dir
create_mock_bitlesson "$TEST_DIR"
BIN_DIR="$TEST_DIR/bin"
STDIN_FILE="$TEST_DIR/codex-stdin.txt"
create_recording_mock_codex "$BIN_DIR" "$STDIN_FILE"
mkdir -p "$TEST_DIR/.humanize"
printf '{"bitlesson_model": "gpt-4o"}' > "$TEST_DIR/.humanize/config.json"

result=""
exit_code=0
result=$(CODEX_PROJECT_DIR="$TEST_DIR" XDG_CONFIG_HOME="$TEST_DIR/no-user" \
    PATH="$BIN_DIR:$PATH" \
    bash "$BITLESSON_SELECT" \
    --task "Fix a bug" \
    --paths "scripts/bitlesson-select.sh" \
    --bitlesson-file "$TEST_DIR/.humanize/bitlesson.md" 2>/dev/null) || exit_code=$?

if [[ $exit_code -eq 0 ]] \
    && [[ -s "$STDIN_FILE" ]] \
    && grep -q "Sub-task description:" "$STDIN_FILE" \
    && grep -q "Fix a bug" "$STDIN_FILE"; then
    pass "Selector passes trailing '-' and prompt content through stdin"
else
    fail "Selector passes trailing '-' and prompt content through stdin" \
        "exit=0 with recorded stdin prompt" \
        "exit=$exit_code, output=$result, stdin=$(cat "$STDIN_FILE" 2>/dev/null || true)"
fi

echo ""
echo "--- Test 3: Unsupported model exits non-zero ---"
echo ""

setup_test_dir
create_mock_bitlesson "$TEST_DIR"
mkdir -p "$TEST_DIR/.humanize"
printf '{"bitlesson_model": "haiku"}' > "$TEST_DIR/.humanize/config.json"

exit_code=0
stderr_out=$(CODEX_PROJECT_DIR="$TEST_DIR" XDG_CONFIG_HOME="$TEST_DIR/no-user" \
    bash "$BITLESSON_SELECT" \
    --task "Fix a bug" \
    --paths "scripts/bitlesson-select.sh" \
    --bitlesson-file "$TEST_DIR/.humanize/bitlesson.md" 2>&1 >/dev/null) || exit_code=$?

if [[ $exit_code -ne 0 ]] && echo "$stderr_out" | grep -qiE "codex model|unknown model|error"; then
    pass "Unsupported model exits non-zero with clear error message"
else
    fail "Unsupported model exits non-zero with clear error message" "non-zero exit + error message" "exit=$exit_code, stderr=$stderr_out"
fi

echo ""
echo "--- Test 4: Missing codex binary exits non-zero ---"
echo ""

setup_test_dir
create_mock_bitlesson "$TEST_DIR"
mkdir -p "$TEST_DIR/.humanize"
printf '{"bitlesson_model": "gpt-4o"}' > "$TEST_DIR/.humanize/config.json"

exit_code=0
stderr_out=$(CODEX_PROJECT_DIR="$TEST_DIR" XDG_CONFIG_HOME="$TEST_DIR/no-user" \
    PATH="$SAFE_BASE_PATH" \
    bash "$BITLESSON_SELECT" \
    --task "Fix a bug" \
    --paths "scripts/bitlesson-select.sh" \
    --bitlesson-file "$TEST_DIR/.humanize/bitlesson.md" 2>&1 >/dev/null) || exit_code=$?

if [[ $exit_code -ne 0 ]] && echo "$stderr_out" | grep -qi "codex"; then
    pass "Missing codex binary exits non-zero with informative error"
else
    fail "Missing codex binary exits non-zero with informative error" "non-zero exit + 'codex' in stderr" "exit=$exit_code, stderr=$stderr_out"
fi

print_test_summary "Bitlesson Select Routing Test Summary"
