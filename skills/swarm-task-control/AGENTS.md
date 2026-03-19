# swarm-task-control/
> L2 | 父级: /Users/oogie/.openclaw/workspace/openclaw-swarm-core/skills/AGENTS.md

成员清单
- AGENTS.md: `swarm-task-control` 模块地图。
- SKILL.md: Swarm 任务控制规则，负责已进入 delivery 模式后的 task 操作。
- agents/openai.yaml: UI 元数据与默认 prompt。
- references/swarm-cli-cheatsheet.md: 最小命令速查。
- references/swarm-state-interpretation.md: 状态解读与操作建议。

法则
- 只控制已存在的 Swarm task。
- 不负责决定是否进入 delivery。
- 优先读状态，再执行 redirect、kill、monitor 或 cleanup。

[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
