# reference/
> L2 | 父级: /Users/oogie/.openclaw/workspace/openclaw-swarm-core/AGENTS.md

成员清单
- AGENTS.md: `reference/` 模块地图，定义本目录文档边界与维护协议。
- agent-swarm-architecture.md: 30X Swarm 当前架构说明，定义 OpenClaw 原生会话层与 swarm 交付内核如何协同。
- agent-swarm-constitution-v1.md: 30X Swarm 系统宪法，定义北极星、角色契约、状态机、会话到任务映射与多 CLI 驱动边界。
- agent-swarm-north-star-v1.md: 30X Swarm 北极星说明书，固定产品定义、能力承诺与指标体系。

架构边界
- 本目录只存放 30X Swarm 的静态参考与治理文档，不承载运行时代码，也不是用户第一入口。
- 操作性内容优先下沉到 `skills/*/references/`；本目录只保留系统级文档。
- 本目录默认服务维护者、架构设计和发布校对；首次上手用户应先看 `skills/`。
- 代码实现与本文档必须同构：状态机、角色边界、DoD 规则不得背离。

依赖关系
- 输入依赖: 仓库根 `AGENTS.md`（发布规则）、`swarm-core/` 实际实现（事实来源）。
- 输出影响: 编排层设计、脚本接口约束、控制面字段与状态定义。

[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
