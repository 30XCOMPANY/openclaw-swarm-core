# drivers/
> L2 | 父级: /Users/oogie/.openclaw/workspace/openclaw-swarm-core/swarm-core/AGENTS.md

成员清单
- AGENTS.md: `drivers/` 子模块地图，定义驱动实现边界。
- base.py: 驱动协议与共享类型。
- codex.py: Codex CLI 驱动。
- claudecode.py: Claude Code CLI 驱动。
- opencode.py: OpenCode CLI 驱动。
- gemini_cli.py: Gemini CLI 驱动。

法则
- 驱动只处理 CLI 差异，不承载业务状态机。
- 新增执行工具必须先实现 `BaseDriver` 契约再注册。

[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
