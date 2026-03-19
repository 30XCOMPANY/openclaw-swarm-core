# .archive/
> L2 | 父级: /Users/oogie/.openclaw/workspace/openclaw-swarm-core/AGENTS.md

成员清单
- AGENTS.md: `.archive/` 模块地图，定义历史材料与已退役文档的边界。
- agent-swarm-usage.md: 已归档的旧操作手册；其操作性内容已由 `skills/*/references/` 接管。

架构边界
- `.archive/` 只存放历史材料、被替代文档和旧叙事，不承载当前产品入口。
- 当前生效的操作规则必须回到 `skills/` 或 `reference/`，不能继续依赖 `.archive/`。

依赖关系
- 输入依赖: 仓库演化历史。
- 输出影响: 历史追溯、迁移说明、旧文档保留。

[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
