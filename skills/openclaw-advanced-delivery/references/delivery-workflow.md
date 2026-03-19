<!--
[INPUT]: 依赖 advanced delivery 模式的用户承诺与最小工作流
[OUTPUT]: 对外提供 delivery 话术与执行语义
[POS]: openclaw-advanced-delivery 的用户口径参考，被 `SKILL.md` 按需引用
[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
-->

# Delivery Workflow

Use this language when explaining `/delivery`:

- "This enters advanced delivery mode."
- "The task will be tracked as a Swarm task."
- "The goal is PR-backed, merge-ready convergence."
- "You can come back later and ask `/swarm` for status or control."

What delivery mode should imply:

1. isolated execution context
2. tracked task state
3. PR-oriented progression
4. gate checking
5. retries when evidence supports another attempt
6. cleanup at the end

Do not describe it as magic autonomy. Describe it as deterministic delivery infrastructure.

Do not frame `/delivery` as "pick a harness and code". Frame it as "enter tracked delivery mode".
