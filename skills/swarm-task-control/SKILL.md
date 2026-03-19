---
name: swarm
description: Use when a task is already in Swarm advanced delivery mode and the user wants to inspect, redirect, continue, monitor, clean up, or terminate it. Trigger on requests like "check swarm status", "redirect this task", "monitor it", "cleanup", "kill task", or "what state is this delivery in".
user-invocable: true
argument-hint: "[status | redirect | cleanup | kill | task id]"
---

<!--
[INPUT]: 依赖当前 Swarm CLI 与状态机语义，依赖命令速查与状态解读引用
[OUTPUT]: 对外提供已进入 Swarm 后的任务控制准则
[POS]: 公开 skill 层的 Swarm 控制入口，被 agent 用来解释与操控 delivery task
[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
-->

# Swarm Task Control

Use this skill only after a task has already entered advanced delivery mode.

## Core Rule

This skill controls existing Swarm tasks. It does not decide whether a task should enter Swarm.

## Primary Actions

- read task state
- explain task state
- redirect a running task
- run monitor
- clean terminal tasks
- kill a task when explicitly requested

## Workflow

1. Read current task state first.
2. Explain the state in delivery terms.
3. Apply the requested control action.
4. Re-check state if needed.

## Use This When

The user asks:

- what is the task doing
- is it ready
- can we redirect it
- can we retry or monitor it
- can we clean it up
- can we stop it

## References

Read `references/swarm-cli-cheatsheet.md` for the command surface.

Read `references/swarm-state-interpretation.md` for how to describe statuses and next actions.
