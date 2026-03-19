<!--
[INPUT]: 依赖当前 Swarm 状态机语义
[OUTPUT]: 对外提供状态解释与下一步建议
[POS]: swarm-task-control 的状态参考，被 `SKILL.md` 按需引用
[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
-->

# Swarm State Interpretation

Use these simple interpretations:

- `queued`: task accepted but not yet running
- `running`: harness is executing inside worktree/tmux
- `pr_created`: PR exists; waiting for checks and reviews
- `ci_failed`: CI failed; retryable via monitor if attempts remain
- `ci_passed`: CI passed; still waiting on remaining gates
- `review_changes_requested`: review asked for changes; retryable via monitor if attempts remain
- `ready_to_merge`: all configured gates passed
- `merged`: terminal success
- `failed`: execution failed before successful convergence; retryable via monitor if attempts remain
- `abandoned`: terminal stop condition

Recommended guidance:

- if `running`, talk about progress and next gate
- if `ci_failed`, `review_changes_requested`, or `failed`, talk about the monitor-driven retry/fix path
- if `ready_to_merge`, say it is ready for merge, not merely "looks good"
- if terminal, explain whether cleanup is still pending
