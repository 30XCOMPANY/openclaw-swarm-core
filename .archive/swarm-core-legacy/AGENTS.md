# swarm-core/
> L2 | 父级: /Users/oogie/.openclaw/workspace/openclaw-swarm-core/AGENTS.md

成员清单
- AGENTS.md: `swarm-core` 模块地图，定义控制平面边界与维护协议。
- swarm: 全局 CLI 入口脚本，转发到 Python 控制平面实现。
- swarm_cli.py: 核心编排器，负责状态机、SQLite 真相源、任务生命周期与投影。
- templates/: 项目播种模板目录，`swarm seed` 用它自动生成项目 `.openclaw` 薄包装脚本与文档。
- drivers/base.py: 统一驱动契约定义（preflight/launch/probe/collect/normalize_error）。
- drivers/codex.py: Codex 执行驱动实现。
- drivers/claudecode.py: ClaudeCode 执行驱动实现。
- drivers/opencode.py: OpenCode 执行驱动实现。
- drivers/gemini_cli.py: Gemini CLI 执行驱动实现。

架构边界
- `swarm-core` 是 30X Swarm 的内部控制平面，不是用户主入口；用户入口固定在 `skills/`。
- 项目目录只保留薄配置和兼容投影。
- 任务状态唯一真相源是每项目 `.openclaw/swarm.db` 的 SQLite。
- `active-tasks.json` 仅作为兼容投影，不允许被业务逻辑直接当主存。
- `swarm seed` 负责播种 `.openclaw` 兼容脚本，并在缺失时补种项目根 `AGENTS.md`。

依赖关系
- 输入依赖: git/tmux/gh 与各执行 CLI（codex/claude/opencode/gemini）。
- 输出影响: 项目 `.openclaw` 包装脚本、兼容投影文件、cron 监控链路。

[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
