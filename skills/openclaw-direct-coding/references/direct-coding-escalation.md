<!--
[INPUT]: 依赖 direct coding 与 advanced delivery 的边界定义
[OUTPUT]: 对外提供 direct coding 升级到 delivery 的判断规则
[POS]: openclaw-direct-coding 的升级判断参考，被 `SKILL.md` 按需引用
[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
-->

# Direct Coding Escalation Rules

Leave direct coding and switch to `$delivery` when one or more are true:

- the user wants a PR
- the user wants merge-ready output
- the task should survive across time without watching the current conversation
- CI or review gates matter
- worktree isolation is needed
- the user wants later status checks
- the task is large enough that retry and cleanup matter

Stay in direct coding when the user mainly wants immediate execution, explanation, or a patch in the current conversation.
