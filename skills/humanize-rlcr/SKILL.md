---
name: humanize-rlcr
description: Start RLCR (Ralph-Loop with Codex Review) with hook-equivalent enforcement from skill mode by reusing the existing stop-hook logic.
type: flow
user-invocable: false
disable-model-invocation: true
---

# Humanize-codex RLCR Loop (Hook-Equivalent)

Use this flow to run RLCR in environments without native hooks.  
Do not re-implement review logic manually. Always call the RLCR stop gate wrapper:

```bash
"{{HUMANIZE_RUNTIME_ROOT}}/scripts/rlcr-stop-gate.sh"
```

The wrapper executes `hooks/loop-codex-stop-hook.sh`, so skill-mode behavior stays aligned with hook-mode behavior.

## Runtime Root

The installer hydrates this skill with an absolute runtime root path:

```bash
{{HUMANIZE_RUNTIME_ROOT}}
```

All commands below assume `{{HUMANIZE_RUNTIME_ROOT}}`.

## Required Sequence

### 1. Setup

Start the loop with the setup script:

```bash
"{{HUMANIZE_RUNTIME_ROOT}}/scripts/setup-rlcr-loop.sh" $ARGUMENTS
```

If setup exits non-zero, stop and report the error.

As a convenience wrapper, you may also use:

```bash
"{{HUMANIZE_RUNTIME_ROOT}}/scripts/start-or-resume-rlcr.sh" $ARGUMENTS
```

This wrapper starts a new loop when no active RLCR loop exists, or resumes the active loop automatically when one is already in progress. It keeps cycling through:
- run Codex on the current round/finalize prompt
- run `rlcr-stop-gate.sh`
- continue until the loop completes or an infrastructure error occurs

If you only want to inspect the active loop without executing it, use:

```bash
"{{HUMANIZE_RUNTIME_ROOT}}/scripts/start-or-resume-rlcr.sh" --print-only
```

### 1.5 Resume After Interruption

If Codex is interrupted mid-loop, do **not** run setup again. Resume the existing loop from the active state directory.

1. Find the active loop directory:

```bash
loop_dir="$(ls -dt .humanize/rlcr/* 2>/dev/null | head -1)"
test -n "$loop_dir" || { echo "No RLCR loop found"; exit 1; }
echo "$loop_dir"
```

2. Check the loop state:
- If `"$loop_dir/state.md"` exists, resume the current round.
- If `"$loop_dir/finalize-state.md"` exists, resume Finalize Phase.
- If only `cancel-state.md`, `complete-state.md`, or another terminal `*-state.md` exists, do **not** resume; the loop is already closed.

3. Resume a normal round:

```bash
round="$(sed -n 's/^current_round: //p' "$loop_dir/state.md" | head -1 | tr -d ' ')"
sed -n '1,240p' "$loop_dir/round-${round}-prompt.md"
```

Then:
- continue the implementation work
- update `"$loop_dir/round-${round}-summary.md"`
- run the gate again:

```bash
GATE_CMD=("{{HUMANIZE_RUNTIME_ROOT}}/scripts/rlcr-stop-gate.sh")
[[ -n "${CODEX_SESSION_ID:-}" ]] && GATE_CMD+=(--session-id "$CODEX_SESSION_ID")
[[ -n "${CODEX_TRANSCRIPT_PATH:-}" ]] && GATE_CMD+=(--transcript-path "$CODEX_TRANSCRIPT_PATH")
"${GATE_CMD[@]}"
```

4. Resume Finalize Phase:
- read `"$loop_dir/finalize-state.md"` for context
- update `"$loop_dir/finalize-summary.md"`
- run the same gate command above

5. Never:
- rerun `setup-rlcr-loop.sh` while an active loop exists
- rerun `start-or-resume-rlcr.sh` expecting it to force a new loop while one is already active
- manually edit `state.md` or `finalize-state.md`
- skip directly to a later round file

### 2. Work Round

For each round:

1. Read current loop prompt from `.humanize/rlcr/<timestamp>/round-<N>-prompt.md` (or `finalize` prompt files when in finalize phase).
2. Implement required changes.
3. Commit changes.
4. Write required summary file:
   - Normal phase: `.humanize/rlcr/<timestamp>/round-<N>-summary.md`
   - Finalize phase: `.humanize/rlcr/<timestamp>/finalize-summary.md`
5. Run gate command:

```bash
GATE_CMD=("{{HUMANIZE_RUNTIME_ROOT}}/scripts/rlcr-stop-gate.sh")
[[ -n "${CODEX_SESSION_ID:-}" ]] && GATE_CMD+=(--session-id "$CODEX_SESSION_ID")
[[ -n "${CODEX_TRANSCRIPT_PATH:-}" ]] && GATE_CMD+=(--transcript-path "$CODEX_TRANSCRIPT_PATH")
"${GATE_CMD[@]}"
GATE_EXIT=$?
```

6. Handle gate result:
   - `0`: loop is allowed to exit (done).
   - `10`: blocked by RLCR logic. Follow returned instructions exactly, continue next round.
   - `20`: infrastructure error (wrapper/hook/runtime). Report error, do not fake completion.

## What This Enforces

By routing through the stop-hook logic, this skill enforces:

- state/schema validation (`current_round`, `max_iterations`, `review_started`, `base_branch`, etc.)
- branch consistency checks
- plan-file integrity checks (when applicable)
- incomplete Task/Todo blocking
- git-clean requirement before exit
- `--push-every-round` unpushed-commit blocking
- summary presence checks
- max-iteration handling
- full-alignment rounds (`--full-review-round`)
- strict `COMPLETE`/`STOP` marker handling
- review-phase transition guard (`.review-phase-started` marker)
- code-review gating on `[P0-9]` markers
- hard blocking on codex review failure or empty output
- open-question handling when `ask_codex_question=true`

## Critical Rules

1. Never manually edit `state.md` or `finalize-state.md`.
2. Never skip a blocked gate result by declaring completion manually.
3. Never run ad-hoc `codex exec` / `codex review` in place of the gate for phase transitions.
4. Always use files generated by the loop (`round-*-prompt.md`, `round-*-review-result.md`) as source of truth.

## Options

Pass these through `setup-rlcr-loop.sh`:

| Option | Description | Default |
|--------|-------------|---------|
| `path/to/plan.md` | Plan file path | Required unless `--skip-impl` |
| `--plan-file <path>` | Explicit plan path | - |
| `--track-plan-file` | Enforce tracked plan immutability | false |
| `--max N` | Maximum iterations | 42 |
| `--codex-model MODEL:EFFORT` | Codex model and effort for `codex exec` | gpt-5.4:high |
| `--codex-timeout SECONDS` | Codex timeout | 5400 |
| `--base-branch BRANCH` | Base for review phase | auto-detect |
| `--full-review-round N` | Full alignment interval | 5 |
| `--skip-impl` | Start directly in review path | false |
| `--push-every-round` | Require push each round | false |
| `--codex-answer-review` | Let Codex answer open questions directly | false |
| `--agent-teams` | Enable agent teams mode | false |
| `--yolo` | Skip quiz and enable --codex-answer-review | false |
| `--skip-quiz` | Skip Plan Understanding Quiz (implicit in skill mode) | false |

Review phase `codex review` runs with `gpt-5.4:high`.

## Usage

```bash
# Start with plan file
/flow:humanize-rlcr path/to/plan.md

# Review-only mode
/flow:humanize-rlcr --skip-impl

# Load skill without auto-execution
/skill:humanize-rlcr
```

## Cancel

```bash
"{{HUMANIZE_RUNTIME_ROOT}}/scripts/cancel-rlcr-loop.sh"
```
