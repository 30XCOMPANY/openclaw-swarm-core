# reference/
> L2 | 父级: /Users/oogie/.openclaw/workspace/openclaw-swarm-core/AGENTS.md

成员清单
- AGENTS.md: `reference/` 模块地图，定义本目录文档边界与维护协议。
- agent-swarm-architecture.md: 原始架构材料与理念拆解，解释两层架构为何成立。
- agent-swarm-usage.md: 对齐当前实现的操作手册，覆盖 `swarm` CLI/薄包装/SQLite 真相源/通知链路。
- agent-swarm-constitution-v1.md: 系统宪法，定义角色契约、状态机、DoD gate 与多 CLI 驱动边界。

架构边界
- 本目录只存放 Agent Swarm 的静态参考与治理文档，不承载运行时代码。
- 任何流程变更先更新宪法，再更新使用说明，最后校对架构文档描述一致性。
- 代码实现与本文档必须同构：状态机、角色边界、DoD 规则不得背离。

依赖关系
- 输入依赖: 仓库根 `AGENTS.md`（发布规则）、`swarm-core/` 实际实现（事实来源）。
- 输出影响: 编排层设计、脚本接口约束、控制面字段与状态定义。

[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
