# templates/
> L2 | 父级: /Users/oogie/.openclaw/workspace/openclaw-swarm-core/swarm-core/AGENTS.md

成员清单
- AGENTS.md: 模板目录地图。
- AGENTS.md.tmpl: 项目 `.openclaw/AGENTS.md` 播种模板。
- spawn-agent.sh.tmpl: 任务启动兼容包装脚本模板。
- redirect-agent.sh.tmpl: 任务纠偏兼容包装脚本模板。
- kill-agent.sh.tmpl: 任务终止兼容包装脚本模板。
- check-agents.sh.tmpl: 确定性巡检入口模板。
- cleanup.sh.tmpl: 终态资源清理入口模板。
- status.sh.tmpl: 状态查询入口模板。
- setup.sh.tmpl: 项目播种入口模板（转发到 `swarm seed`）。
- run-agent.sh.tmpl: 废弃 run-agent 占位模板。

法则
- 模板只负责“薄包装 + 参数适配”，不承载编排业务逻辑。
- 所有执行最终必须转发到全局 `swarm` CLI。

[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
