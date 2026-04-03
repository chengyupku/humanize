---
description: "Consult Codex with a one-shot question or review task"
argument-hint: "[--codex-model MODEL:EFFORT] [--codex-timeout SECONDS] [question or task]"
allowed-tools:
  - "Bash(./scripts/ask-codex.sh:*)"
  - "Read"
---

# Ask Codex

Send a one-shot question or task to Codex and return the result.

## Usage

Run:

```bash
"./scripts/ask-codex.sh" "$ARGUMENTS"
```

## Notes

- Keep free-form user text quoted when passing it to the shell.
- If the user supplies flags such as `--codex-model` or `--codex-timeout`, preserve them as separate shell arguments and pass the remaining free-form question as one quoted final argument.
- Report non-zero exits directly instead of guessing.
