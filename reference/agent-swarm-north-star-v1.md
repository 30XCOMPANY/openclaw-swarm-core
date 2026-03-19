<!--
[INPUT]: 依赖 OpenClaw 当前原生能力验证结果，依赖 swarm-core 现有状态机与交付边界
[OUTPUT]: 对外提供 30X Swarm 北极星定义、能力承诺与指标体系
[POS]: reference 的产品定义文档，被 constitution 和 usage 共同引用
[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
-->

# 30X Swarm North Star v1

Status: Active  
Scope: OpenClaw-native conversational delivery system

## 1. System Definition

30X Swarm 不是孤立的脚本集合，也不是单次代码生成器。

系统定义固定为：

**OpenClaw-native conversational control plane + swarm deterministic delivery kernel**

在本仓库中的公开产品面固定为：

- `/coding`
- `/delivery`
- `/swarm`

也就是说，用户通过 skills 进入系统；Swarm 作为确定性内核在这些 skills 背后工作。

一句话北极星：

**让用户只需远程与 OpenClaw 对话，OpenClaw 基于原生会话与工具能力驱动 swarm，把多轮意图稳定收敛为可审查、可追踪、可合并的生产级 PR。**

## 2. Native Ability Anchor

北极星只能建立在今天已经验证存在的 OpenClaw 原生能力之上：

- 多渠道远程对话入口
- 持续会话与会话历史
- 原生 agent 执行能力（`read/edit/write/exec/process`）
- 子会话与任务派生（`sessions_spawn`、`subagents`）
- ACP / coding harness 桥接能力
- 运行中 steering、续聊、状态追问

## 3. Role Split

OpenClaw:
- 面向用户的唯一入口
- 负责会话连续性、多轮澄清、运行中打断、补充约束、状态追问

swarm:
- 负责确定性交付收敛
- 负责 worktree、driver、PR、CI、review、retry、cleanup

coding harness:
- 负责统一执行行为、质量约束、DoD 习惯和 PR 产物格式

## 4. North Star Metric

Primary metric:

**Under ongoing conversation and steering through OpenClaw, maximize production-grade merged deliveries per unit of human attention.**

中文口径：

**在通过 OpenClaw 持续对话、打断和续聊的前提下，用最少的人类注意力，最大化生产级合并交付。**

## 5. Success Metrics

Primary metrics:
- `conversation-to-merge success rate`
- `human steering efficiency`
- `interruption recovery rate`
- `production-grade PR rate`

Guardrails:
- `session drift rate`
- `retry rate`
- `ci failure rate`
- `stuck-without-pr rate`

## 6. Product Contract

系统对外承诺：
- 用户首先接触的是 skills，而不是 runtime 目录结构
- 用户只需要与 OpenClaw 对话，不需要直接操作底层 coding tools
- 用户可以在执行中继续补充约束、打断或要求继续
- 默认产物是可追踪任务状态与 PR，不只是文本回复
- 系统承诺高确定性交付和生产级质量，不承诺绝对零错误

[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
