<!--
[INPUT]: OpenClaw Gateway ACP bridge implementation, acpx CLI tool
[OUTPUT]: Complete ACP operations reference for agents operating coding harnesses
[POS]: /coding reference doc; authoritative source for ACP bridge model, session routing, and CLI usage
[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
-->

# ACP Operations Guide

## What ACP Is (In This Context)

ACP in OpenClaw is a **Gateway-backed ACP bridge**, not a full ACP-native runtime. It provides:

- **Session routing** — map ACP sessions to Gateway session keys
- **Prompt delivery** — send prompts to coding harnesses through the bridge
- **Basic streaming** — receive streamed responses from harnesses

It does NOT provide a full ACP runtime with per-session MCP servers, client filesystem access, or session plans. See the "Not Supported" section below for the complete boundary.

## Session Model

### Session Keys

Each ACP session maps to a single Gateway session key. The key format is agent-scoped:

```
agent:main:main
```

ACP does not pick agents directly. It routes by Gateway session key. The Gateway resolves the session key to the appropriate agent and harness.

### Session Lifecycle

1. **Initialize** — establish connection to Gateway
2. **New Session** — create a session with a key
3. **Prompt** — send coding tasks through the session
4. **Cancel** — cancel an in-progress prompt
5. **List Sessions** — enumerate active sessions

## acpx Usage

The `acpx` tool is the CLI interface to the ACP bridge.

### One-Shot Execution

```bash
acpx openclaw --url <gateway-url> --token <token> "your prompt here"
```

### Persistent Session

```bash
# Start a session
acpx openclaw --url <gateway-url> --token <token> --session my-session "initial prompt"

# Continue in the same session
acpx openclaw --url <gateway-url> --token <token> --session my-session "follow-up prompt"

# Reset a session (clear history, keep the key)
acpx openclaw --url <gateway-url> --token <token> --session my-session --reset-session "fresh start"
```

## CLI Flags

| Flag | Purpose | Example |
|------|---------|---------|
| `--url` | Gateway URL | `--url https://gateway.openclaw.dev` |
| `--token` | Gateway token (inline) | `--token sk-xxx` |
| `--token-file` | Gateway token (from file) | `--token-file ~/.openclaw/token` |
| `--password` | Gateway password (inline) | `--password mypass` |
| `--password-file` | Gateway password (from file) | `--password-file ~/.openclaw/password` |
| `--session` | Named session key | `--session agent:main:main` |
| `--session-label` | Human-readable session label | `--session-label "Fix auth bug"` |
| `--reset-session` | Clear session history before prompt | `--reset-session` |
| `--verbose` | Enable debug output | `--verbose` |

### Authentication Priority

1. `--token` / `--token-file` (if provided)
2. `OPENCLAW_GATEWAY_TOKEN` environment variable
3. `--password` / `--password-file` (fallback)
4. `OPENCLAW_GATEWAY_PASSWORD` environment variable

## Environment Variables

| Variable | Purpose |
|----------|---------|
| `OPENCLAW_GATEWAY_TOKEN` | Default Gateway authentication token |
| `OPENCLAW_GATEWAY_PASSWORD` | Fallback Gateway password |

These are used when `--token` / `--password` flags are not provided on the command line.

## Supported ACP Operations

### Fully Supported

| Operation | Description |
|-----------|-------------|
| `initialize` | Establish ACP connection to Gateway |
| `newSession` | Create a new ACP session mapped to a Gateway session key |
| `prompt` | Send a prompt and receive streamed response |
| `cancel` | Cancel an in-progress prompt |
| `listSessions` | List active ACP sessions |
| Slash commands | Forward `/command` invocations through the bridge |

### Partially Supported

| Operation | What Works | What Does Not |
|-----------|-----------|---------------|
| `loadSession` | Resuming a session by key | Full session state restoration |
| Prompt content | Text prompts | Structured multi-part content (images, files) |
| Session modes | Default mode | Custom session mode switching |
| Session info | Basic metadata | Full capability negotiation |
| Tool streaming | Basic tool call results | Real-time tool execution streaming |

### Not Supported

These ACP features are NOT available through the Gateway bridge:

| Feature | Why |
|---------|-----|
| Per-session MCP servers | Gateway does not manage per-session MCP lifecycle |
| Client filesystem methods | Bridge does not expose client filesystem to harness |
| Client terminal methods | Bridge does not expose client terminal to harness |
| Session plans | Gateway does not support ACP session planning |
| Thought streaming | Gateway does not relay internal reasoning traces |

## Session Routing

ACP does not pick agents directly. The routing chain is:

```
acpx prompt
  -> ACP bridge
    -> Gateway session key lookup
      -> Resolved agent + harness
        -> Coding harness execution
```

The agent and harness are determined by the Gateway session key configuration, not by the ACP client. To target a specific harness, configure the appropriate Gateway session key.

## Error Handling

| Error | Cause | Resolution |
|-------|-------|------------|
| Authentication failed | Invalid token or password | Check `OPENCLAW_GATEWAY_TOKEN` or `--token` value |
| Session not found | Invalid session key | Use `listSessions` to find valid keys, or create a new session |
| Prompt timeout | Harness did not respond | Retry with `--reset-session` if session state is corrupted |
| Connection refused | Gateway unreachable | Verify `--url` and network connectivity |

## Usage Patterns

### Pattern: One-Shot Coding Task

```bash
acpx openclaw \
  --url "$OPENCLAW_GATEWAY_URL" \
  --token "$OPENCLAW_GATEWAY_TOKEN" \
  "Refactor the auth module to use JWT tokens instead of session cookies"
```

### Pattern: Multi-Turn Session

```bash
# First turn
acpx openclaw --session coding-auth --token "$OPENCLAW_GATEWAY_TOKEN" \
  "Add JWT authentication to the Express app"

# Follow-up
acpx openclaw --session coding-auth --token "$OPENCLAW_GATEWAY_TOKEN" \
  "Now add refresh token rotation"

# Course correction
acpx openclaw --session coding-auth --token "$OPENCLAW_GATEWAY_TOKEN" \
  "Use RS256 instead of HS256 for signing"
```

### Pattern: Reset and Retry

```bash
acpx openclaw --session coding-auth --reset-session \
  --token "$OPENCLAW_GATEWAY_TOKEN" \
  "Start over. Implement JWT auth with RS256 signing and refresh rotation"
```
