# openclaw-direct-coding/
> L2 | 父级: /Users/oogie/.openclaw/workspace/openclaw-swarm-core/skills/AGENTS.md

成员清单
- AGENTS.md: `openclaw-direct-coding` 模块地图。
- SKILL.md: 直接 coding 模式规则，要求先选 harness，再做直接执行。
- agents/openai.yaml: UI 元数据与默认 prompt。
- references/harness-selection.md: harness 选择规则与推荐口径。
- references/direct-coding-escalation.md: 从 direct coding 升级到 delivery 的触发规则。

法则
- 先判断用户是不是其实要 `/delivery`；只有留在 direct coding 时才问 harness。
- 先问 harness，再执行。
- 默认不进入 Swarm。
- 遇到 PR、CI、异步推进、merge-ready 诉求时，引导切换到 advanced delivery。

[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
