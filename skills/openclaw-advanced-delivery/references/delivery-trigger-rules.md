<!--
[INPUT]: 依赖 direct coding 与 advanced delivery 的边界定义
[OUTPUT]: 对外提供进入 delivery 模式的触发规则
[POS]: openclaw-advanced-delivery 的触发参考，被 `SKILL.md` 按需引用
[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
-->

# Delivery Trigger Rules

Choose advanced delivery when the task needs one or more of these:

- branch + PR artifact
- CI checks
- review gates
- screenshot gate for UI work
- status that can be queried later
- retries with evidence
- cleanup after completion

Choose direct coding when the task is mostly:

- immediate
- synchronous
- exploratory
- low-risk
- easy to finish inside the current conversation

Good user-facing rule:

- "Do it now" -> direct coding
- "Take this to PR / merge-ready" -> advanced delivery
