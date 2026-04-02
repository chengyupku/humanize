#!/bin/bash
#
# Check bot reactions on PRs.
#
# Detects:
# - Codex +1 (thumbs-up) reaction on PR body (first round approval)
#
# Usage:
#   check-bot-reactions.sh codex-thumbsup <pr_number> [--after <timestamp>]
#
# Exit codes:
#   0 - Reaction found
#   1 - Reaction not found
#   2 - Error (API failure, missing arguments, etc.)

set -euo pipefail

GH_TIMEOUT=30

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$SCRIPT_DIR/portable-timeout.sh"

show_help() {
    cat << 'EOF'
check-bot-reactions.sh - Detect bot reactions on GitHub PRs

USAGE:
  check-bot-reactions.sh codex-thumbsup <pr_number> [--after <timestamp>]

COMMANDS:
  codex-thumbsup    Check for Codex +1 reaction on PR body
                    Returns reaction created_at timestamp if found
                    --after: Only count reaction if created after this timestamp

EXIT CODES:
  0 - Reaction found (outputs JSON with reaction info)
  1 - Reaction not found
  2 - Error (API failure, etc.)
EOF
    exit 0
}

COMMAND="${1:-}"
shift || true

if [[ -z "$COMMAND" ]] || [[ "$COMMAND" == "-h" ]] || [[ "$COMMAND" == "--help" ]]; then
    show_help
fi

case "$COMMAND" in
    codex-thumbsup)
        PR_NUMBER=""
        AFTER_TIMESTAMP=""

        while [[ $# -gt 0 ]]; do
            case $1 in
                --after)
                    AFTER_TIMESTAMP="${2:-}"
                    shift 2
                    ;;
                -*)
                    echo "Error: Unknown option for codex-thumbsup: $1" >&2
                    exit 2
                    ;;
                *)
                    if [[ -z "$PR_NUMBER" ]]; then
                        PR_NUMBER="$1"
                    else
                        echo "Error: Multiple PR numbers specified" >&2
                        exit 2
                    fi
                    shift
                    ;;
            esac
        done

        if [[ -z "$PR_NUMBER" ]]; then
            echo "Error: PR number is required for codex-thumbsup" >&2
            exit 2
        fi

        CURRENT_REPO=$(run_with_timeout "$GH_TIMEOUT" gh repo view --json owner,name \
            -q '.owner.login + "/" + .name' 2>/dev/null) || CURRENT_REPO=""

        PR_BASE_REPO=""
        if [[ -n "$CURRENT_REPO" ]]; then
            if run_with_timeout "$GH_TIMEOUT" gh pr view "$PR_NUMBER" --repo "$CURRENT_REPO" --json number -q .number >/dev/null 2>&1; then
                PR_BASE_REPO="$CURRENT_REPO"
            fi
        fi

        if [[ -z "$PR_BASE_REPO" ]]; then
            PARENT_REPO=$(run_with_timeout "$GH_TIMEOUT" gh repo view --json parent \
                -q '.parent.owner.login + "/" + .parent.name' 2>/dev/null) || PARENT_REPO=""
            if [[ -n "$PARENT_REPO" && "$PARENT_REPO" != "null/" && "$PARENT_REPO" != "/" ]]; then
                if run_with_timeout "$GH_TIMEOUT" gh pr view "$PR_NUMBER" --repo "$PARENT_REPO" --json number -q .number >/dev/null 2>&1; then
                    PR_BASE_REPO="$PARENT_REPO"
                fi
            fi
        fi

        if [[ -z "$PR_BASE_REPO" ]]; then
            PR_BASE_REPO="$CURRENT_REPO"
        fi

        REACTIONS=$(run_with_timeout "$GH_TIMEOUT" gh api "repos/$PR_BASE_REPO/issues/$PR_NUMBER/reactions" \
            --paginate --jq '[.[] | {user: .user.login, content: .content, created_at: .created_at}]' 2>/dev/null \
            | jq -s 'add // []') || {
            echo "Error: Failed to fetch PR reactions" >&2
            exit 2
        }

        CODEX_REACTION=$(echo "$REACTIONS" | jq -r '
            [.[] | select(.user == "chatgpt-codex-connector[bot]" and .content == "+1")] | .[0] // empty
        ')

        if [[ "$CODEX_REACTION" == "null" ]] || [[ -z "$CODEX_REACTION" ]]; then
            exit 1
        fi

        REACTION_AT=$(echo "$CODEX_REACTION" | jq -r '.created_at')
        if [[ -n "$AFTER_TIMESTAMP" && "$REACTION_AT" < "$AFTER_TIMESTAMP" ]]; then
            exit 1
        fi

        echo "$CODEX_REACTION"
        exit 0
        ;;
    *)
        echo "Error: Unknown command: $COMMAND" >&2
        show_help
        ;;
esac
