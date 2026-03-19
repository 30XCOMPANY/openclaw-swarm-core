---
name: delivery
description: Use when the user wants advanced delivery instead of direct coding. Trigger on requests like "/delivery", "make this a PR", "ship this", "take it to merge-ready", "I will check back later", "run CI and review gates", or any task that needs Swarm's worktree, task state, retry, cleanup, and production-grade convergence.
user-invocable: true
argument-hint: "[delivery task]"
---

<!--
[INPUT]: 依赖 Swarm advanced delivery mode 定位，依赖触发规则与工作流引用
[OUTPUT]: 对外提供 `/delivery` 的触发、承诺与升级准则
[POS]: 公开 skill 层的 advanced delivery 入口，被 agent 用来决定何时进入 Swarm
[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
-->

# OpenClaw Advanced Delivery

Use this skill for the `/delivery` path.

## Core Rule

`/delivery` means:

- enter Swarm advanced delivery mode
- create a task object, not just a transient execution
- converge toward PR-backed, merge-ready delivery

Unlike `/coding`, `/delivery` is not primarily about choosing a harness. It is about choosing the tracked delivery path.

Do not force a harness-selection question at the start of `/delivery` unless the operator explicitly asks for a specific driver. Auto driver selection is acceptable.

## Use This When

The user wants:

- a PR
- merge-ready output
- CI/review gates
- asynchronous progress
- task status they can ask about later
- retry and cleanup discipline

## Do Not Use This When

Do not enter delivery mode for:

- quick code edits
- exploratory debugging
- small synchronous requests
- tasks better handled in one direct harness turn

In those cases, use `/coding`.

## Workflow

1. Confirm the task belongs in advanced delivery mode.
2. Frame the result as delivery, not just execution.
3. Enter Swarm mode and create a task.
4. Keep user-facing updates centered on task state, PR, and gates.
5. Route in-flight control to `/swarm`.

## Trigger Guidance

Read `references/delivery-trigger-rules.md` when you need a precise keep-in-direct-coding vs escalate-to-delivery decision.

## User Contract

Read `references/delivery-workflow.md` when you need the right language for explaining what delivery mode will do.
