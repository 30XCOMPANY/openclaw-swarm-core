<!--
[INPUT]: 依赖 OpenClaw 当前原生会话能力，依赖 swarm-core CLI 和项目薄包装模板
[OUTPUT]: 对外提供 30X Swarm x OpenClaw 的使用手册、操作路径与排障口径
[POS]: reference 的操作文档，被 README 和人工运维流程引用
[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
-->

# 30X Swarm Usage Guide

## 1. Goal

Convert requirements expressed through ongoing OpenClaw conversation into reviewable PR delivery.

The system uses a three-layer split:
- OpenClaw: remote entrypoint, ongoing conversation, steering, status replies
- swarm: deterministic delivery kernel and gate system
- coding harness: isolated code execution

## 2. Current Capability State

Verified OpenClaw-native abilities:
- multi-channel remote messaging
- `sessions` / `sessions_history` / `sessions_send` / `sessions_yield`
- `session_status`
- `sessions_spawn` / `subagents`
- native `agent` turn execution
- `acp` and bundled coding-agent skill

Enabled execution drivers:
- `codex`
- `claudecode`
- `opencode`
- `gemini-cli`

## 3. Current Runtime Shape

```text
User-facing conversational plane
OpenClaw session/channel
├── receive requirement
├── clarify / steer / interrupt / continue
├── delegate into swarm
└── answer status from swarm task state

Global delivery kernel
/Users/oogie/.openclaw/swarm-core/
├── swarm
├── swarm_cli.py
├── drivers/
└── templates/

Per-project thin layer
<repo>/.openclaw/
├── project.toml
├── swarm.db
├── active-tasks.json
├── logs/
├── spawn-agent.sh
├── redirect-agent.sh
├── kill-agent.sh
├── check-agents.sh
├── cleanup.sh
└── status.sh
```

Core rules:
- `swarm.db` is the canonical truth
- `active-tasks.json` is compatibility output only
- monitoring uses deterministic external signals
- users interact with OpenClaw, not directly with `tmux`

## 4. Recommended Operating Model

The recommended flow is:

1. User starts through OpenClaw
2. OpenClaw scopes and packages context
3. OpenClaw delegates into swarm
4. User continues steering through the same conversation
5. swarm converges the evolving intent into one task context
6. result returns as PR + task state

Direct `.openclaw/*.sh` use remains a valid operator/debug path, not the ideal end-user surface.

## 5. One-Time Project Bootstrap

```bash
swarm seed --repo /abs/path/to/repo
```

## 6. Manual Task Control

Recommended compatibility entrypoint:

```bash
cd /abs/path/to/repo
./.openclaw/spawn-agent.sh \
  --id "fix-login-timeout-$(date +%s)" \
  --agent claudecode \
  --prompt "Fix login timeout and add tests"
```

Equivalent global CLI:

```bash
swarm task spawn \
  --repo /abs/path/to/repo \
  --task-id fix-login-timeout-$(date +%s) \
  --driver claudecode \
  --prompt "Fix login timeout and add tests"
```

Mid-flight correction:

```bash
./.openclaw/redirect-agent.sh <task-id> "Focus API first then UI"
```

Interpretation:
- `redirect` is the operator-facing compatibility primitive for steering
- the ideal product path is OpenClaw mapping follow-up conversation into that task context

## 7. Status and Cleanup

```bash
./.openclaw/status.sh
./.openclaw/status.sh --json
./.openclaw/check-agents.sh
./.openclaw/kill-agent.sh <task-id>
./.openclaw/cleanup.sh
```

## 8. Lifecycle

Allowed states:
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

Constraints:
- no DoD bypass into `ready_to_merge`
- steering should default to the existing task, not silently fork

## 9. DoD Gates

All must pass before `ready_to_merge`:
- `checks.prCreated`
- `checks.branchMergeable`
- `checks.ciPassed`
- `checks.reviewCodexPassed`
- `checks.reviewClaudePassed`
- `checks.reviewGeminiPassed`
- `checks.uiScreenshotPresent` when UI changed

## 10. Notification Path

Notifications are sent through `openclaw message send`.

This means OpenClaw is both:
- the user-facing conversation layer
- the status delivery layer

## 11. Capability Contract

Correct promises:
- start coding work through OpenClaw
- continue steering during execution
- interrupt or continue without dropping out of the conversation model
- return PR-backed delivery artifacts rather than only text

Incorrect promises:
- absolute zero-error execution
- pure chat polling replacing deterministic monitors
- every follow-up message automatically mapping perfectly without explicit task-state integration

## 12. Operator Debugging

```bash
which codex
which claude
which opencode
which gemini

ls .openclaw/logs
tail -n 200 .openclaw/logs/<task-id>.log

sqlite3 .openclaw/swarm.db "select id,status,driver,attempt_count,pr_number from tasks order by created_at desc limit 20;"
tmux ls
```

## 13. Driver Strategy

- `codex` for backend logic and complex refactors
- `claudecode` for frontend changes and quick iteration
- `opencode` for OpenCode-native flows
- `auto` when the orchestrator should choose

Read together with:
- `agent-swarm-north-star-v1.md`
- `agent-swarm-architecture.md`
- `agent-swarm-constitution-v1.md`
