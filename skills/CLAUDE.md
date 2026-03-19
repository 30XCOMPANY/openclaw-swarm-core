# skills/
> L2 | Parent: AGENTS.md

Public product surface — the only user-facing entry layer. Each subdirectory is a slash command.

## Members

- `coding/`: `/coding` — pure text skill for direct coding through ACP-connected harnesses
- `delivery/`: `/delivery` — shell-based delivery CLI with tracked task orchestration

## Rules

- Skills are the public front door; runtime internals must not displace them
- Each skill directory name matches its slash command exactly
- `coding/` is pure text (no executables); `delivery/` is self-contained (text + shell CLI)

[PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
