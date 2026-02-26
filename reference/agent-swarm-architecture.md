# 30X Swarm Architecture - Elvis's OpenClaw Setup

Source: https://x.com/elvissun/status/2025920521871716562
Date: 2026-02-23
Author: Elvis (@elvissun)

## 核心理念

**两层架构**：
- **编排层（OpenClaw）**：持有业务上下文（客户数据、会议笔记、历史决策、成功/失败案例）
- **执行层（Coding Agents）**：专注代码实现，不需要业务上下文

**为什么分层**：
- Context window 是零和游戏
- 填满代码 → 没空间放业务上下文
- 填满业务上下文 → 没空间放代码库
- 通过上下文专业化，而非不同模型

## 数据指标

- **生产力**：94 commits/天（最高），平均 50 commits/天
- **速度**：7 PRs/30分钟，idea to production 极快
- **成本**：Claude $100/月 + Codex $90/月（可以 $20 起步）
- **成功率**：小到中等任务几乎都能一次成功，无需人工干预
- **瓶颈**：RAM（16GB Mac Mini 最多 4-5 agents，买了 128GB Mac Studio）

## 完整工作流（8步）

### Step 1: 客户需求 → Scoping
- 会议笔记自动同步到 Obsidian vault
- 与 Zoe（编排 agent）讨论需求，零解释成本
- Zoe 做三件事：
  1. Top up credits（有 admin API access）
  2. 从 prod DB 拉客户配置（只读权限，coding agents 永远不给）
  3. Spawn Codex agent（带详细 prompt + 所有上下文）

### Step 2: Spawn Agent
- 每个 agent 独立 worktree（隔离分支）+ tmux session
- 用 tmux 而非 `codex exec` 或 `claude -p`
- **tmux 优势**：可以中途重定向 agent
  - Agent 走错方向？不要 kill，直接发新指令
  - `tmux send-keys -t <session> "Stop. Focus on X first." Enter`

```bash
# 创建 worktree + spawn agent
git worktree add ../feat-custom-templates -b feat/custom-templates origin/main
cd ../feat-custom-templates && pnpm install

tmux new-session -d -s "codex-templates" \
  -c "/path/to/worktree" \
  "$HOME/.codex-agent/run-agent.sh templates gpt-5.3-codex high"
```

- 任务追踪：`.clawdbot/active-tasks.json`

```json
{
  "id": "feat-custom-templates",
  "tmuxSession": "codex-templates",
  "agent": "codex",
  "description": "Custom email templates for agency customer",
  "repo": "medialyst",
  "worktree": "feat-custom-templates",
  "branch": "feat/custom-templates",
  "startedAt": 1740268800000,
  "status": "running",
  "notifyOnComplete": true
}
```

### Step 3: 监控循环（改进版 Ralph Loop）
- Cron 每 10 分钟检查所有 agents
- **不直接 poll agents**（太贵），而是读 JSON registry 检查：
  - tmux sessions 是否 alive
  - 是否有 open PRs
  - CI 状态（via `gh cli`）
  - 自动 respawn 失败的 agents（最多 3 次）
- 100% 确定性，极省 token
- 只在需要人工注意时才 alert

**关键区别**：
- 传统 Ralph Loop：每次用同样的 prompt
- 这个系统：Zoe 看失败原因 + 业务上下文，写更好的 prompt
  - Agent 超出 context？"只关注这三个文件"
  - Agent 走错方向？"客户要的是 X，不是 Y。这是会议记录"
  - Agent 需要澄清？"这是客户邮件和他们公司做什么"

### Step 4: Agent 创建 PR
- Agent commit、push、开 PR：`gh pr create --fill`
- **此时不通知人类** — PR 本身不算完成

**Definition of Done**（agent 必须知道）：
- PR created
- Branch synced to main（无冲突）
- CI passing（lint/types/unit tests/E2E）
- Codex review passed
- Claude Code review passed
- Gemini review passed
- Screenshots included（如果有 UI 改动）

### Step 5: 自动 Code Review（3 个 AI）
- **Codex Reviewer**：最彻底，擅长边界情况、逻辑错误、错误处理、竞态条件。误报率低
- **Gemini Code Assist Reviewer**：免费且超有用。抓安全问题、可扩展性问题。给具体修复建议
- **Claude Code Reviewer**：基本没用 — 过度谨慎，很多"consider adding..."建议都是过度工程。只看标记为 critical 的

所有三个都直接在 PR 上评论

### Step 6: 自动测试
CI pipeline：
- Lint + TypeScript checks
- Unit tests
- E2E tests
- Playwright tests（preview 环境，与 prod 一致）

**新规则**：UI 改动必须在 PR description 带截图，否则 CI fail
- 大幅缩短 review 时间 — 直接看截图，不用点 preview

### Step 7: 人工 Review
- 现在才收到 Telegram 通知："PR #341 ready for review"
- 此时：CI passed、3 个 AI reviewers approved、截图显示 UI 改动、所有边界情况都在 review comments 里
- **人工 review 只需 5-10 分钟**
- 很多 PR 不读代码直接 merge — 截图告诉我一切

### Step 8: Merge
- PR merge
- Daily cron job 清理孤立的 worktrees 和 task registry json

## Agent 选择策略

### Codex（主力，90% 任务）
- 后端逻辑
- 复杂 bugs
- 多文件重构
- 需要跨代码库推理的任何事
- 更慢但彻底

### Claude Code（前端 + git）
- 更快，更擅长前端工作
- 权限问题少，适合 git 操作
- （注：Codex 5.3 现在更好更快了，用得少了）

### Gemini（设计感）
- 美观 UI 的超能力
- 先让 Gemini 生成 HTML/CSS spec
- 再交给 Claude Code 在组件系统里实现
- Gemini 设计，Claude 构建

**Zoe 负责**：为每个任务选对的 agent，在它们之间路由输出

## 主动工作发现

Zoe 不等任务分配，主动找活干：
- **早上**：扫 Sentry → 发现 4 个新错误 → spawn 4 agents 调查修复
- **会后**：扫会议笔记 → 标记 3 个功能请求 → spawn 3 Codex agents
- **晚上**：扫 git log → spawn Claude Code 更新 changelog 和客户文档

散步回来，Telegram："7 PRs ready for review. 3 features, 4 bug fixes."

## 奖励信号

成功标志：
- CI passing
- 所有三个 code reviews passing
- Human merge

任何失败触发循环。随着时间推移，Zoe 写更好的 prompt，因为她记得什么 shipped 了

成功模式被记录：
- "这个 prompt 结构对 billing features 有效"
- "Codex 需要提前给 type definitions"
- "总是包含 test file paths"

## 实现方式

**最简单方法**：
把整篇文章复制给 OpenClaw，说："Implement this agent swarm setup for my codebase."

它会：
- 读架构
- 创建脚本
- 设置目录结构
- 配置 cron 监控

10 分钟搞定。

## 关键脚本

### `.clawdbot/check-agents.sh`
- 检查 tmux sessions 是否 alive
- 检查 tracked branches 是否有 open PRs
- 通过 `gh cli` 检查 CI 状态
- 自动 respawn 失败的 agents（最多 3 次）
- 只在需要人工注意时 alert

### Agent 启动脚本
```bash
# Codex
codex --model gpt-5.3-codex \
  -c "model_reasoning_effort=high" \
  --dangerously-bypass-approvals-and-sandbox \
  "Your prompt here"

# Claude Code  
claude --model claude-opus-4.5 \
  --dangerously-skip-permissions \
  -p "Your prompt here"
```

## 硬件需求

**瓶颈**：RAM
- 每个 agent 需要独立 worktree
- 每个 worktree 需要独立 `node_modules`
- 每个 agent 跑 builds、type checks、tests
- 5 agents 同时 = 5 个并行 TypeScript compilers + 5 个 test runners + 5 套依赖加载到内存

**实际经验**：
- 16GB Mac Mini：最多 4-5 agents（还得祈祷它们不同时 build）
- 解决方案：128GB Mac Studio M4 Max ($3,500)

## 愿景

2026 年会看到大量一人百万美元公司。关键是理解如何构建递归自我改进的 agents。

架构：
- AI 编排器作为你的延伸（像 Zoe 对 Elvis）
- 委派工作给专门的 agents 处理不同业务功能
- Engineering、Customer support、Ops、Marketing
- 每个 agent 专注擅长的事
- 你保持激光聚焦和完全控制

下一代创业者不会雇 10 人团队做一个人用对的系统能做的事。他们会这样构建 — 保持小规模、快速移动、每日发布。

## Elvis 的项目

**Agentic PR**：一人公司挑战企业 PR 巨头
- Agents 帮助 startups 获得媒体报道
- 无需 $10k/月 retainer
- 真实客户、真实收入、真实 commits 发到 production

---

## 可操作的下一步

1. **立即可做**：
   - 设置 `.clawdbot/` 目录结构
   - 创建 `active-tasks.json` 追踪系统
   - 写 `check-agents.sh` 监控脚本
   - 配置 cron 每 10 分钟检查

2. **需要实验**：
   - tmux session 管理
   - worktree 工作流
   - 3-model code review pipeline
   - 自动截图要求

3. **需要优化**：
   - Prompt 模板（针对不同任务类型）
   - 失败模式识别和 respawn 策略
   - 奖励信号收集和学习循环

4. **硬件考虑**：
   - 评估当前 RAM 是否够用
   - 如果经常跑 >5 agents，考虑升级
