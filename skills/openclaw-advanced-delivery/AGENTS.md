# openclaw-advanced-delivery/
> L2 | 父级: /Users/oogie/.openclaw/workspace/openclaw-swarm-core/skills/AGENTS.md

成员清单
- AGENTS.md: `openclaw-advanced-delivery` 模块地图。
- SKILL.md: 进阶交付模式规则，定义何时进入 Swarm 与如何描述这种模式。
- agents/openai.yaml: UI 元数据与默认 prompt。
- references/delivery-trigger-rules.md: direct coding 与 advanced delivery 的分界规则。
- references/delivery-workflow.md: delivery 模式的最小工作流与用户可见承诺。

法则
- 这是 `/delivery`，不是普通 coding。
- 以交付收敛为中心，不以 harness 选择为中心。
- 只有任务真正需要 PR/gate/retry/status 时才进入。

[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
