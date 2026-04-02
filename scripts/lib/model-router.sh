#!/bin/bash
#
# model-router.sh - Shared model routing helpers
#

# Source guard: prevent double-sourcing
[[ -n "${_MODEL_ROUTER_LOADED:-}" ]] && return 0 2>/dev/null || true
_MODEL_ROUTER_LOADED=1

detect_provider() {
    local model_name="${1:-}"

    if [[ -z "$model_name" ]]; then
        echo "Error: Model name must be non-empty." >&2
        return 1
    fi

    if [[ "$model_name" == gpt-* ]] || [[ "$model_name" == o[0-9]* ]]; then
        echo "codex"
        return 0
    fi

    echo "Error: Unknown model name '$model_name'. Expected a Codex model name such as gpt-* or o[N]-*." >&2
    return 1
}

check_provider_dependency() {
    local provider="${1:-}"
    local binary=""

    case "$provider" in
        codex)
            binary="codex"
            ;;
        *)
            echo "Error: Unknown provider '$provider'. Expected 'codex'." >&2
            return 1
            ;;
    esac

    if command -v "$binary" >/dev/null 2>&1; then
        return 0
    fi

    echo "Error: Required binary '$binary' was not found in PATH for provider '$provider'." >&2
    echo "Install: https://github.com/openai/codex" >&2
    return 1
}

map_effort() {
    local effort="${1:-}"
    local target_provider="${2:-}"

    if [[ "$target_provider" != "codex" ]]; then
        echo "Error: Unknown target provider '$target_provider'. Expected 'codex'." >&2
        return 1
    fi

    case "$effort" in
        xhigh|high|medium|low)
            ;;
        *)
            echo "Error: Unknown effort '$effort'. Expected one of: xhigh, high, medium, low." >&2
            return 1
            ;;
    esac

    echo "$effort"
}
