# skills/
> L2 | 父级: /Users/oogie/.openclaw/workspace/openclaw-swarm-core/AGENTS.md

成员清单
- AGENTS.md: `skills/` 模块地图，定义公开 skill 层的边界与维护协议。
- openclaw-direct-coding/: 直接 coding 模式 skill，要求先明确 coding harness，再执行短平快任务。
- openclaw-advanced-delivery/: 进阶交付模式 skill，把复杂任务升级到 Swarm 收敛路径。
- swarm-task-control/: Swarm 任务控制 skill，负责已进入 delivery 模式后的状态查询与操控。

架构边界
- `skills/` 是公开给 agent 的操作层，不承载 runtime 内核实现。
- skill 必须反映 `OpenClaw direct coding` 与 `Swarm advanced delivery mode` 的边界，不能重新发明产品结构。
- 引用规则、决策表与命令速查放在各 skill 的 `references/`，保持 `SKILL.md` 短而硬。

依赖关系
- 输入依赖: `README.md`、`reference/`、`swarm-core/` 当前实现。
- 输出影响: agent 使用路径、用户入口口径、Swarm 触发和控制方式。

[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
