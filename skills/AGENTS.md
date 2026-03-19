# skills/
> L2 | Parent: AGENTS.md

Public product surface — the only user-facing entry layer. Each subdirectory is a slash command.

Member list:
- coding/: `/coding` — pure text ACP operations guide. No executables; tells the agent what coding harnesses exist and how to operate them.
- delivery/: `/delivery` — self-contained delivery skill with embedded CLI and shell runtime. Owns the complete delivery lifecycle: spawn, monitor, status, redirect, kill, cleanup.

Rules:
- Skills are the public front door; runtime internals must not displace them.
- Each skill directory name matches its slash command exactly.
- `coding/` is pure text (no executables); `delivery/` is self-contained (text + shell CLI in `bin/`).
- No other top-level skill directories should be created without updating this manifest.

[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
