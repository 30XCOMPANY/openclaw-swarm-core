<!--
[INPUT]: 依赖当前 Swarm CLI 和项目包装脚本接口
[OUTPUT]: 对外提供最小命令速查
[POS]: swarm-task-control 的命令参考，被 `SKILL.md` 按需引用
[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
-->

# Swarm CLI Cheatsheet

Core commands:

```bash
swarm task spawn --repo /abs/path/to/repo --task-id <id> --driver <driver> --prompt "<text>"
swarm task redirect --repo /abs/path/to/repo --task-id <id> --message "<text>"
swarm task kill --repo /abs/path/to/repo --task-id <id>
swarm monitor tick --repo /abs/path/to/repo
swarm cleanup tick --repo /abs/path/to/repo
swarm status --repo /abs/path/to/repo --format json
```

Retry note:

- there is no standalone `swarm task retry`
- evidence-driven retries are launched by `swarm monitor tick`
- retryable states are `failed`, `ci_failed`, and `review_changes_requested`

Project wrapper equivalents:

```bash
./.openclaw/spawn-agent.sh ...
./.openclaw/redirect-agent.sh <task-id> "<message>"
./.openclaw/kill-agent.sh <task-id>
./.openclaw/check-agents.sh
./.openclaw/cleanup.sh
./.openclaw/status.sh --json
```

Wrapper note:

- `./.openclaw/check-agents.sh` is the project-level monitor entrypoint and therefore also the retry trigger
