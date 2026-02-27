# 30X Swarm 使用说明书（2026-02-25 对齐版）

## 1. 目标

把人类业务意图稳定转译为可验收 PR 交付  
系统默认遵循两层分工
- 编排层（OpenClaw）负责上下文 选型 监控 重试 通知
- 执行层（coding CLI）负责在隔离工作区完成代码与 PR

## 2. 当前能力状态

已启用执行驱动
- `codex`（默认 driver）
- `claudecode`（你当前环境已配置）
- `opencode`
- `gemini-cli`

兼容提示
- 旧项目若历史配置为 `[drivers.gemini-cli] enabled = false`，需改为 `true` 才能调度 Gemini

## 3. 落地架构（当前实现）

```text
Global control plane
/Users/oogie/.openclaw/swarm-core/
├── swarm                      # 全局 CLI 入口
├── swarm_cli.py               # 状态机 + 监控 + 重试 + DoD gate + 通知
├── drivers/                   # codex / claudecode / opencode / gemini-cli
└── templates/                 # 项目播种模板

Per project thin layer
<repo>/.openclaw/
├── project.toml               # 项目配置（driver/通知/base branch）
├── swarm.db                   # 真相源（SQLite）
├── active-tasks.json          # 兼容投影（非真相源）
├── logs/
├── spawn-agent.sh             # 薄包装 -> swarm task spawn
├── redirect-agent.sh          # 薄包装 -> swarm task redirect
├── kill-agent.sh              # 薄包装 -> swarm task kill
├── check-agents.sh            # 薄包装 -> swarm monitor tick
├── cleanup.sh                 # 薄包装 -> swarm cleanup tick
└── status.sh                  # 薄包装 -> swarm status
```

核心原则
- 任务状态以 `swarm.db` 为唯一真相源
- `active-tasks.json` 只做兼容输出
- 监控按确定性外部信号运行（tmux/git/PR/CI/review）

## 4. 一次性初始化（每个项目）

```bash
/Users/oogie/.openclaw/swarm-core/swarm seed --repo /abs/path/to/repo
```

`seed` 会自动生成项目 `.openclaw/` 薄包装与默认 `project.toml`

## 5. 启动任务

推荐（兼容入口）
```bash
cd /abs/path/to/repo
./.openclaw/spawn-agent.sh \
  --id "fix-login-timeout-$(date +%s)" \
  --agent claudecode \
  --prompt "Fix login timeout and add tests"
```

直接调用全局 CLI（等价）
```bash
/Users/oogie/.openclaw/swarm-core/swarm task spawn \
  --repo /abs/path/to/repo \
  --task-id fix-login-timeout-$(date +%s) \
  --driver claudecode \
  --prompt "Fix login timeout and add tests"
```

可选驱动
- `auto`
- `codex`
- `claudecode`（`claude` 会被兼容映射）
- `opencode`
- `gemini-cli`

模型格式注意
- 默认行为：若未显式配置 `model`，所有 driver 都沿用各自 CLI 本机默认模型。
- `codex` / `claudecode` / `gemini-cli`：显式配置时使用裸模型名。
- `opencode`：显式配置时使用 `provider/model`（示例：`default/gpt-5.3-codex`）。
- 历史值 `openai/gpt-5.3-codex` 会自动归一化为 `default/gpt-5.3-codex`。

## 6. 监控与操作

状态查看
```bash
./.openclaw/status.sh
./.openclaw/status.sh --json
```

单次巡检（确定性 tick）
```bash
./.openclaw/check-agents.sh
```

中途纠偏
```bash
./.openclaw/redirect-agent.sh <task-id> "Focus API first then UI"
```

终止任务
```bash
./.openclaw/kill-agent.sh <task-id>
```

清理终态资源
```bash
./.openclaw/cleanup.sh
```

## 7. cron 建议

监控循环（每 10 分钟）
```bash
openclaw cron add \
  --name "swarm-monitor" \
  --schedule "*/10 * * * *" \
  --command "cd /abs/path/to/repo && ./.openclaw/check-agents.sh"
```

清理循环（每日）
```bash
openclaw cron add \
  --name "swarm-cleanup" \
  --schedule "0 2 * * *" \
  --command "cd /abs/path/to/repo && ./.openclaw/cleanup.sh"
```

## 8. 状态机（实现口径）

允许状态
- `queued`
- `running`
- `pr_created`
- `ci_failed`
- `ci_passed`
- `review_changes_requested`
- `ready_to_merge`
- `merged`
- `failed`
- `abandoned`

终态
- `merged`
- `abandoned`

重试入口
- 仅 `failed` `ci_failed` `review_changes_requested`

## 9. DoD Gate（ready_to_merge 判定）

全部通过才会进入 `ready_to_merge`
- `checks.prCreated`
- `checks.branchMergeable`
- `checks.ciPassed`
- `checks.reviewCodexPassed`（若配置要求）
- `checks.reviewClaudePassed`（若配置要求）
- `checks.reviewGeminiPassed`（若配置要求）
- `checks.uiScreenshotPresent`（UI 变更时必需）

## 10. 通知（已接入 OpenClaw 原生）

通知由 `swarm-core` 直接调用 `openclaw message send` 完成  
默认走 Discord（按 `project.toml` 的 `[notifications]`）

示例配置
```toml
[notifications]
provider = "openclaw"
enabled = false
channel = "discord"
target = ""
account = ""
silent = false
dry_run = false
events = ["ready_to_merge", "merged"]
allow_failure_events = false
```

说明
- 发送成功会写入 `task_notifications` 去重
- 发送失败会记事件 不中断状态机
- 每轮 `monitor tick` 会补偿尝试未发送状态通知
- 只有在 `enabled=true` 且 `target` 明确配置时才会发消息，避免跨频道误发
- 若 `spawn` 能推断来源会话（如 `agent:main:discord:channel:<id>`），优先回发到该任务来源频道

## 11. 日常排障

确认 CLI 可用
```bash
which codex
which claude
which opencode
```

查看任务日志
```bash
ls .openclaw/logs
tail -n 200 .openclaw/logs/<task-id>.log
```

检查数据库记录
```bash
sqlite3 .openclaw/swarm.db "select id,status,driver,attempt_count,pr_number from tasks order by created_at desc limit 20;"
sqlite3 .openclaw/swarm.db "select task_id,status,channel,target,sent_at from task_notifications order by sent_at desc limit 20;"
```

查看 tmux 会话
```bash
tmux ls
tmux attach -t <session-name>
```

非重试失败（会直接 `abandoned`）
- `non_retryable_remote`: 远端不支持 `gh pr create`（例如本地裸仓库）
- `non_retryable_auth_missing`: Gemini 鉴权缺失
- `non_retryable_model_not_found`: 驱动模型在当前 provider 不可用

## 12. 推荐执行策略

- 后端逻辑与复杂重构优先 `codex`
- 前端改动和快速迭代优先 `claudecode`
- 需要 OpenCode 生态时用 `opencode`
- 优先用 `auto` 让编排层选驱动 只在你有明确意图时手选

---

参考
- 架构理念: `agent-swarm-architecture.md`
- 系统宪法: `agent-swarm-constitution-v1.md`
