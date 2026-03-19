---
name: coding
description: Use when the user wants direct coding execution through a chosen coding harness instead of Swarm delivery mode. Trigger on requests like "/coding", "use Codex", "use Claude Code", "use OpenCode", "use Gemini CLI", "direct coding", "just fix this now", or any short, synchronous coding task that should not enter PR/gate/retry orchestration.
user-invocable: true
argument-hint: "[task and optional harness]"
---

<!--
[INPUT]: 依赖 OpenClaw direct coding 定位，依赖 harness 选择规则与升级规则引用
[OUTPUT]: 对外提供 `/coding` 的触发、问询、执行与升级准则
[POS]: 公开 skill 层的 direct coding 入口，被 agent 用来决定何时直接走 coding harness
[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
-->

# OpenClaw Direct Coding

Use this skill for the default `/coding` path.

## Core Rule

`/coding` means:

- direct harness execution
- conversation-bound execution in the current thread
- no Swarm task lifecycle by default
- no PR/gate/retry/status-later contract by default

If the real ask is PR-backed delivery, do not keep the user in `/coding`. Route to `/delivery`.

## Required Interaction

If the user has not already picked a coding harness, ask:

`你要用哪个 coding harness？Codex / Claude Code / OpenCode / Gemini CLI`

Do not skip this. Harness choice is required for `/coding`.

If the user already named a harness, use it and continue.

If the request is actually about PRs, review gates, retries, or "I will check back later", switch to `/delivery` instead of asking for a harness first.

## When To Use

Use direct coding when the task is:

- short or medium in scope
- synchronous
- exploratory
- easy to steer in the current conversation
- not explicitly asking for PR-backed delivery

## When Not To Use

Do not stay in direct coding when the user clearly wants:

- a PR
- CI/review gates
- merge-ready delivery
- asynchronous progress
- retry/cleanup behavior
- a task that can be checked later by status

In that case, recommend switching to `/delivery`.

## Workflow

1. Confirm or ask for the coding harness.
2. Restate the task briefly in direct execution terms.
3. Execute through the chosen harness.
4. Report concrete results.
5. If the task grows into delivery work, escalate to `/delivery`.

## Harness Selection

Read `references/harness-selection.md` when the user asks which harness to use or seems unsure.

## Escalation

Read `references/direct-coding-escalation.md` when you need to decide whether the task should leave `/coding` and enter delivery mode.
