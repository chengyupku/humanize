#!/bin/bash
#
# Start a new RLCR loop, or resume and run an interrupted active one.
#
# Behavior:
# - If no active RLCR loop exists, start one with setup-rlcr-loop.sh.
# - If an active RLCR loop exists, resume it from the current round/finalize prompt.
# - By default this script continues running Codex + gate cycles until the loop completes
#   or an infrastructure/runtime error occurs.
#
# Usage:
#   start-or-resume-rlcr.sh [path/to/plan.md | --plan-file path/to/plan.md] [setup options...]
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="${CODEX_PROJECT_DIR:-$(pwd)}"
LOOP_BASE_DIR="$PROJECT_ROOT/.humanize/rlcr"
PRINT_ONLY="false"

source "$SCRIPT_DIR/../hooks/lib/loop-common.sh"

show_help() {
    cat <<'EOF'
start-or-resume-rlcr - Start a new RLCR loop, or resume and run an interrupted active one

USAGE:
  start-or-resume-rlcr.sh [path/to/plan.md | --plan-file path/to/plan.md] [OPTIONS]

BEHAVIOR:
  - If no active RLCR loop exists, this script forwards all arguments to setup-rlcr-loop.sh.
  - If an active RLCR loop exists, this script resumes it automatically from the current prompt.
  - After each Codex execution, this script runs rlcr-stop-gate.sh and keeps looping until:
    * the loop completes successfully, or
    * an infrastructure/runtime error occurs.

NOTES:
  - Active loop states are state.md or finalize-state.md.
  - Terminal loop states such as cancel-state.md or complete-state.md are not resumed.
  - Use --print-only if you only want the resume context without executing Codex.

EXAMPLES:
  start-or-resume-rlcr.sh docs/plan.md
  start-or-resume-rlcr.sh --plan-file docs/plan.md --max 20
  start-or-resume-rlcr.sh --print-only docs/plan.md
  start-or-resume-rlcr.sh --help
EOF
}

SETUP_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        --print-only)
            PRINT_ONLY="true"
            shift
            ;;
        *)
            SETUP_ARGS+=("$1")
            shift
            ;;
    esac
done

build_codex_exec_args() {
    local model="$1"
    local effort="$2"
    local force_bypass="${3:-false}"
    local -a args=("-m" "$model")
    if [[ -n "$effort" ]]; then
        args+=("-c" "model_reasoning_effort=${effort}")
    fi

    local auto_flag="--full-auto"
    if [[ "$force_bypass" == "true" ]] || [[ "${HUMANIZE_CODEX_BYPASS_SANDBOX:-}" == "true" ]] || [[ "${HUMANIZE_CODEX_BYPASS_SANDBOX:-}" == "1" ]]; then
        auto_flag="--dangerously-bypass-approvals-and-sandbox"
    fi

    args+=("$auto_flag" "-C" "$PROJECT_ROOT")
    printf '%s\0' "${args[@]}"
}

run_codex_on_prompt() {
    local prompt_file="$1"
    local model="$2"
    local effort="$3"
    local force_bypass="${4:-false}"

    if [[ ! -f "$prompt_file" ]]; then
        echo "Error: Prompt file not found: $prompt_file" >&2
        return 1
    fi

    if ! command -v codex >/dev/null 2>&1; then
        echo "Error: 'codex' command is not installed or not in PATH" >&2
        return 1
    fi

    local -a exec_args=()
    while IFS= read -r -d '' arg; do
        exec_args+=("$arg")
    done < <(build_codex_exec_args "$model" "$effort" "$force_bypass")

    local stdout_log stderr_log
    stdout_log="$(mktemp)"
    stderr_log="$(mktemp)"
    trap 'rm -f "$stdout_log" "$stderr_log"' RETURN

    if [[ "$force_bypass" == "true" ]]; then
        echo "Running Codex on prompt without sandbox: $prompt_file" >&2
    else
        echo "Running Codex on prompt: $prompt_file" >&2
    fi

    if printf '%s' "$(cat "$prompt_file")" | codex exec "${exec_args[@]}" \
        > >(tee "$stdout_log") \
        2> >(tee "$stderr_log" >&2); then
        return 0
    fi

    if [[ "$force_bypass" != "true" ]] && \
       [[ "${HUMANIZE_CODEX_BYPASS_SANDBOX:-}" != "true" ]] && \
       [[ "${HUMANIZE_CODEX_BYPASS_SANDBOX:-}" != "1" ]] && \
       grep -qE 'bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted|Codex\(Sandbox\(Denied' "$stderr_log"; then
        echo "Codex sandbox failed with a bubblewrap/network-namespace error. Retrying without sandbox..." >&2
        run_codex_on_prompt "$prompt_file" "$model" "$effort" "true"
        return $?
    fi

    return 1
}

print_resume_context() {
    local active_loop_dir="$1"
    local active_state_file="$2"
    local current_round="$3"
    local review_started="$4"

    echo "RESUME_ACTIVE_LOOP"
    echo "loop_dir: $active_loop_dir"
    echo "state_file: $active_state_file"

    if [[ "$active_state_file" == *"/finalize-state.md" ]]; then
        local finalize_prompt_file="$active_loop_dir/finalize-prompt.md"
        local finalize_summary_file="$active_loop_dir/finalize-summary.md"
        local latest_review_result
        latest_review_result=$(ls -1 "$active_loop_dir"/round-*-review-result.md 2>/dev/null | sort -V | tail -1 || true)

        echo "phase: finalize"
        echo "current_round: $current_round"
        echo "prompt_file: $finalize_prompt_file"
        echo "summary_file: $finalize_summary_file"
        if [[ -n "$latest_review_result" ]]; then
            echo "latest_review_result: $latest_review_result"
        fi
        return
    fi

    local prompt_file="$active_loop_dir/round-${current_round}-prompt.md"
    local summary_file="$active_loop_dir/round-${current_round}-summary.md"
    local review_result_file="$active_loop_dir/round-${current_round}-review-result.md"

    echo "phase: implementation_or_review"
    echo "current_round: $current_round"
    echo "review_started: $review_started"
    echo "prompt_file: $prompt_file"
    echo "summary_file: $summary_file"
    if [[ -f "$review_result_file" ]]; then
        echo "review_result_file: $review_result_file"
    fi
}

resolve_resume_prompt_file() {
    local active_loop_dir="$1"
    local active_state_file="$2"
    local current_round="$3"

    if [[ "$active_state_file" == *"/finalize-state.md" ]]; then
        echo "$active_loop_dir/finalize-prompt.md"
    else
        echo "$active_loop_dir/round-${current_round}-prompt.md"
    fi
}

ACTIVE_LOOP_DIR=$(find_active_loop "$LOOP_BASE_DIR")

if [[ -z "$ACTIVE_LOOP_DIR" ]]; then
    "$SCRIPT_DIR/setup-rlcr-loop.sh" "${SETUP_ARGS[@]}"
    ACTIVE_LOOP_DIR=$(find_active_loop "$LOOP_BASE_DIR")
    if [[ -z "$ACTIVE_LOOP_DIR" ]]; then
        echo "Error: RLCR setup completed but no active loop was found." >&2
        exit 1
    fi
fi

while true; do
    ACTIVE_STATE_FILE=$(resolve_active_state_file "$ACTIVE_LOOP_DIR")
    if [[ -z "$ACTIVE_STATE_FILE" ]]; then
        echo "Error: Active RLCR loop found, but no active state file is readable." >&2
        echo "  Loop directory: $ACTIVE_LOOP_DIR" >&2
        exit 1
    fi

    if ! parse_state_file "$ACTIVE_STATE_FILE"; then
        echo "Error: Failed to parse RLCR state file." >&2
        echo "  State file: $ACTIVE_STATE_FILE" >&2
        exit 1
    fi

    CURRENT_ROUND="${STATE_CURRENT_ROUND:-0}"
    REVIEW_STARTED="${STATE_REVIEW_STARTED:-false}"
    CODEX_MODEL="${STATE_CODEX_MODEL:-$DEFAULT_CODEX_MODEL}"
    CODEX_EFFORT="${STATE_CODEX_EFFORT:-$DEFAULT_CODEX_EFFORT}"

    print_resume_context "$ACTIVE_LOOP_DIR" "$ACTIVE_STATE_FILE" "$CURRENT_ROUND" "$REVIEW_STARTED"

    if [[ "$PRINT_ONLY" == "true" ]]; then
        exit 0
    fi

    PROMPT_FILE=$(resolve_resume_prompt_file "$ACTIVE_LOOP_DIR" "$ACTIVE_STATE_FILE" "$CURRENT_ROUND")
    if [[ ! -f "$PROMPT_FILE" ]]; then
        echo "Error: Resume prompt file not found: $PROMPT_FILE" >&2
        echo "Use --print-only to inspect the loop manually." >&2
        exit 1
    fi

    run_codex_on_prompt "$PROMPT_FILE" "$CODEX_MODEL" "$CODEX_EFFORT"

    GATE_OUTPUT=""
    GATE_EXIT=0
    GATE_OUTPUT=$("$SCRIPT_DIR/rlcr-stop-gate.sh" --json) || GATE_EXIT=$?

    case "$GATE_EXIT" in
        0)
            echo "RLCR loop completed."
            exit 0
            ;;
        10)
            echo "RLCR gate blocked; continuing with the updated loop state." >&2
            ACTIVE_LOOP_DIR=$(find_active_loop "$LOOP_BASE_DIR")
            if [[ -z "$ACTIVE_LOOP_DIR" ]]; then
                echo "Error: Gate blocked, but no active RLCR loop remained afterwards." >&2
                printf '%s\n' "$GATE_OUTPUT" >&2
                exit 1
            fi
            ;;
        *)
            echo "Error: rlcr-stop-gate.sh failed with exit code $GATE_EXIT" >&2
            [[ -n "$GATE_OUTPUT" ]] && printf '%s\n' "$GATE_OUTPUT" >&2
            exit "$GATE_EXIT"
            ;;
    esac
done
