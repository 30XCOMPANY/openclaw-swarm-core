<!--
[INPUT]: Coding harness CLI binaries (codex, claude, opencode, gemini) and their flag sets
[OUTPUT]: Per-harness capability matrix with exact CLI invocation patterns
[POS]: /coding reference doc; authoritative source for harness CLI flags and execution modes
[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
-->

# Harness Capabilities

Exact CLI invocation patterns for each coding harness. These flags are derived from the proven driver implementations.

## Codex

**Binary:** `codex`
**Subcommand:** `exec`

### Invocation Pattern

```bash
codex exec \
  --model <model> \
  -c "model_reasoning_effort=<effort>" \
  --dangerously-bypass-approvals-and-sandbox \
  "<prompt>"
```

### Flags

| Flag | Purpose | Required |
|------|---------|----------|
| `exec` | Execute in non-interactive mode | Yes |
| `--model <model>` | Override the default model | No (omit to use Codex default) |
| `-c "model_reasoning_effort=<effort>"` | Set reasoning effort level (low, medium, high) | No (recommended) |
| `--dangerously-bypass-approvals-and-sandbox` | Skip interactive approval prompts for autonomous execution | Yes for headless |

### Notes

- Model names should strip provider prefix: `openai/gpt-5` becomes `gpt-5`
- The `-c` flag accepts config key=value pairs; `model_reasoning_effort` controls thinking depth
- Default reasoning effort: `high`
- Supports output redirection

### Example

```bash
codex exec --model o4-mini -c "model_reasoning_effort=high" \
  --dangerously-bypass-approvals-and-sandbox \
  "Fix the race condition in the connection pool"
```

---

## Claude Code

**Binary:** `claude`

### Invocation Pattern

```bash
claude \
  --model <model> \
  --dangerously-skip-permissions \
  -p "<prompt>"
```

### Flags

| Flag | Purpose | Required |
|------|---------|----------|
| `--model <model>` | Override the default model | No (omit to use Claude default) |
| `--dangerously-skip-permissions` | Skip interactive permission prompts for autonomous execution | Yes for headless |
| `-p "<prompt>"` | Pass prompt directly (non-interactive mode) | Yes for headless |

### Notes

- Model names should strip provider prefix: `anthropic/claude-sonnet` becomes `claude-sonnet`
- The `-p` flag triggers non-interactive single-prompt mode
- Without `-p`, Claude Code enters interactive REPL mode (not suitable for autonomous execution)
- Supports output redirection

### Example

```bash
claude --model claude-sonnet-4-20250514 \
  --dangerously-skip-permissions \
  -p "Build a responsive dashboard component with Tailwind CSS"
```

---

## OpenCode

**Binary:** `opencode`
**Subcommand:** `run`

### Invocation Pattern

```bash
opencode run \
  --model <model> \
  --variant <effort> \
  "<prompt>"
```

### Flags

| Flag | Purpose | Required |
|------|---------|----------|
| `run` | Execute in non-interactive run mode | Yes |
| `--model <model>` | Override the default model | No (omit to use OpenCode default) |
| `--variant <effort>` | Reasoning effort variant (low, medium, high) | No (defaults to high) |

### Notes

- Model names need provider prefix: `gpt-5` becomes `default/gpt-5`
- Special case: `openai/gpt-5.3-codex` maps to `default/gpt-5.3-codex`
- The `--variant` flag controls reasoning depth, similar to Codex's `-c model_reasoning_effort=`
- Default variant: `high`
- Supports output redirection

### Example

```bash
opencode run --model default/o4-mini --variant high \
  "Migrate the database schema to add soft deletes"
```

---

## Gemini CLI

**Binary:** `gemini`

### Invocation Pattern

```bash
gemini \
  --model <model> \
  --approval-mode yolo \
  --prompt "<prompt>"
```

### Flags

| Flag | Purpose | Required |
|------|---------|----------|
| `--model <model>` | Override the default model | No (omit to use Gemini default) |
| `--approval-mode yolo` | Skip interactive approval prompts for autonomous execution | Yes for headless |
| `--prompt "<prompt>"` | Pass prompt directly (non-interactive mode) | Yes for headless |

### Notes

- Model names should strip provider prefix: `google/gemini-2.5-pro` becomes `gemini-2.5-pro`
- `--approval-mode yolo` enables fully autonomous execution without confirmation prompts
- Supports output redirection

### Example

```bash
gemini --model gemini-2.5-pro \
  --approval-mode yolo \
  --prompt "Write unit tests for the payment processing module"
```

---

## Capability Matrix

| Capability | Codex | Claude Code | OpenCode | Gemini CLI |
|------------|-------|-------------|----------|------------|
| Non-interactive mode | `exec` | `-p` | `run` | `--prompt` |
| Model override | `--model` | `--model` | `--model` | `--model` |
| Reasoning effort | `-c model_reasoning_effort=` | N/A | `--variant` | N/A |
| Sandbox bypass | `--dangerously-bypass-approvals-and-sandbox` | `--dangerously-skip-permissions` | N/A | `--approval-mode yolo` |
| Output redirect | Yes | Yes | Yes | Yes |
| Model prefix rule | Strip provider | Strip provider | Add `default/` | Strip provider |

## Model Name Normalization

When passing model names to harnesses, normalize them:

| Harness | Rule | Input | Output |
|---------|------|-------|--------|
| Codex | Strip provider prefix | `openai/gpt-5` | `gpt-5` |
| Claude Code | Strip provider prefix | `anthropic/claude-sonnet` | `claude-sonnet` |
| OpenCode | Add provider prefix if missing | `gpt-5` | `default/gpt-5` |
| Gemini CLI | Strip provider prefix | `google/gemini-2.5-pro` | `gemini-2.5-pro` |
