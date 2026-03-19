<!--
[INPUT]: delivery bin/lib/drivers.sh, legacy swarm_cli.py driver registry and auto-selection logic
[OUTPUT]: Driver capability matrix, auto-selection heuristics, model normalization rules
[POS]: delivery/references driver specification; consumed by SKILL.md and drivers.sh implementation
[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
-->

# Driver Matrix

Four coding harness drivers, unified behind a single dispatch interface.

## Drivers

| Driver | Binary | Primary Use | Default Model |
|--------|--------|-------------|---------------|
| `codex` | `codex` | Backend, debugging, multi-file reasoning | Inherit Codex CLI default |
| `claudecode` | `claude` | Frontend, rapid iteration, UI work | Inherit Claude CLI default |
| `opencode` | `opencode` | OpenCode-native workflows | Inherit OpenCode CLI default |
| `gemini-cli` | `gemini` | Gemini CLI execution | Inherit Gemini CLI default |

Default driver: `codex`.

## Alias

`claude` is an alias for `claudecode`. Both resolve to the same driver
and invoke the `claude` binary.

## Auto-Selection Heuristics

When `--driver auto` is specified, selection follows this logic:

### Step 1: Frontend Keyword Detection

Scan the prompt (case-insensitive) for frontend keywords:

```
frontend, ui, css, tailwind, component, layout, style
```

If any keyword is found **and** `claudecode` is available and enabled,
select `claudecode`.

### Step 2: Fallback Priority

If no frontend keyword matched, or the preferred driver is unavailable,
fall through this priority order:

```
codex > claudecode > opencode > gemini-cli
```

The first driver that is both **enabled** (in `delivery.conf`) and
**available** (binary found on `PATH`) wins.

### Step 3: Failure

If no driver is available, `delivery spawn` exits with an error.

## Driver Command Templates

Each driver maps to a specific CLI invocation pattern:

### codex
```bash
codex exec [--model <model>] -c "model_reasoning_effort=<effort>" \
  --dangerously-bypass-approvals-and-sandbox "<prompt>"
```

### claudecode
```bash
claude [--model <model>] --dangerously-skip-permissions -p "<prompt>"
```

### opencode
```bash
opencode run [--model <model>] --variant <effort> "<prompt>"
```

### gemini-cli
```bash
gemini [--model <model>] --approval-mode yolo --prompt "<prompt>"
```

## Model Normalization

Different CLIs expect different model identifier formats. The delivery runtime
normalizes model strings per driver before passing them through:

### codex, claudecode, gemini-cli

Strip provider prefix. These CLIs expect plain model IDs.

```
openai/gpt-5      ->  gpt-5
anthropic/sonnet   ->  sonnet
gpt-5              ->  gpt-5   (no change)
```

### opencode

Add `default/` prefix if no provider is present. OpenCode expects `provider/model` format.

```
gpt-5              ->  default/gpt-5
default/gpt-5      ->  default/gpt-5   (no change)
openai/gpt-5.3-codex -> default/gpt-5.3-codex  (special case)
```

## Driver Enable/Disable

Drivers can be individually enabled or disabled in `.openclaw/delivery.conf`:

```bash
driver_codex_enabled=true
driver_claudecode_enabled=true
driver_opencode_enabled=true
driver_gemini_cli_enabled=false
```

Disabled drivers are skipped during auto-selection and rejected when
explicitly requested.

## Reasoning Effort

Each driver supports a per-driver reasoning effort setting in
`.openclaw/delivery.conf`:

```bash
reasoning_codex=high
reasoning_claudecode=
reasoning_opencode=high
reasoning_gemini_cli=
```

Empty values inherit the driver's CLI default. The reasoning effort
is passed through the driver command template.

[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
