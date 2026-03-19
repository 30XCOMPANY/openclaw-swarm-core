---
name: delivery
description: "Tracked delivery through Swarm runtime. Spawn tasks, monitor progress, redirect, inspect status, kill, and cleanup. Converges toward PR-backed merge-ready output."
user-invocable: true
argument-hint: "[spawn <task> | status | redirect <id> <msg> | monitor | kill <id> | cleanup]"
metadata: {"openclaw":{"requires":{"bins":["delivery"]}}}
---

<!--
[INPUT]: delivery CLI (bin/delivery), state-machine.md, driver-matrix.md, dod-gates.md, retry-policy.md, notification.md
[OUTPUT]: Complete /delivery skill guidance — trigger rules, command cheatsheet, state machine overview, escalation boundaries
[POS]: /delivery skill entrypoint; the only user-facing surface for tracked delivery operations
[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
-->

# /delivery

Tracked delivery through the Swarm runtime. Every task is a deterministic
state machine that converges toward a PR-backed, merge-ready output.

There is no separate `/swarm` command. All control operations — spawn, status,
redirect, monitor, kill, cleanup — live here.

## When to Enter Delivery Mode

Use `/delivery` when **any** of the following is true:

1. The task requires a **pull request** with CI gates and review checks.
2. The task should be **tracked asynchronously** — you will not babysit it.
3. The task may **fail and need evidence-driven retry**.
4. Multiple tasks should run in **parallel** with independent state.
5. The user explicitly says: "tracked delivery", "PR workflow", "monitored task",
   "spawn", "deliver", "ship it", or mentions gates, retries, or merge readiness.
6. The task scope is large enough that isolated worktree execution is safer than
   in-session editing.

### When NOT to Use /delivery

Use `/coding` instead when:

- The task is **synchronous and conversational** — the user is in the loop.
- It is a quick fix, one-file change, or exploratory prototyping.
- No PR/CI/review orchestration is needed.
- The user wants direct ACP harness interaction, not background execution.

Rule of thumb: if the user will wait for the result in the current conversation
turn, use `/coding`. If the task should run in the background and report back
when done, use `/delivery`.

## Command Cheatsheet

### delivery spawn

Start a new tracked task.

```bash
delivery spawn \
  --repo <path> \
  --task-id <id> \
  --driver <auto|codex|claudecode|claude|opencode|gemini-cli> \
  --prompt "..." \
  [--prompt-file <path>] \
  [--source-session-key <key>] \
  [--notify-channel <ch>] \
  [--notify-target <target>] \
  [--notify-account <acct>] \
  [--progress-every <min>] \
  [--no-progress]
```

- `--prompt` and `--prompt-file` are mutually exclusive.
- `--driver claude` is an alias for `claudecode`.
- `--driver auto` selects a driver automatically (see [driver-matrix.md](references/driver-matrix.md)).
- Notification flags override project-level defaults for this task only.
- `--progress-every <min>` sets progress update cadence. `--no-progress` disables it entirely.

### delivery status

Inspect current task state.

```bash
delivery status --repo <path> [--format json|text] [--task-id <id>]
```

- Without `--task-id`, shows all tasks in the repo.
- `--format json` produces machine-readable output for external consumers.

### delivery redirect

Send a correction or clarification to a running task.

```bash
delivery redirect --repo <path> --task-id <id> --message "..."
```

The message is injected into the running driver session. The task identity is
preserved — this is not a respawn.

### delivery monitor

Run the deterministic inspection loop once.

```bash
delivery monitor --repo <path>
```

Checks tmux session liveness, git/PR state, CI status, and review state.
Drives state transitions and triggers evidence-driven retries where applicable.
Typically run via cron (see [notification.md](references/notification.md)).

### delivery kill

Terminate a running task.

```bash
delivery kill --repo <path> --task-id <id>
```

Kills the tmux session, transitions state to `abandoned`.

### delivery cleanup

Remove artifacts of terminated tasks.

```bash
delivery cleanup --repo <path>
```

Cleans up worktrees, branches, and tmux sessions for tasks in terminal states
(`merged` or `abandoned`).

### delivery init

Initialize delivery infrastructure for a repo.

```bash
delivery init --repo <path>
```

Creates `.openclaw/swarm.db` (SQLite database). Does not seed any scripts into
the project. Called automatically on first `spawn` if the database does not exist.

## State Machine Overview

Every task moves through a deterministic state machine. The 10 states are:

| State | Meaning |
|-------|---------|
| `queued` | Task created, waiting for driver launch |
| `running` | Driver is executing in a tmux session |
| `pr_created` | Code pushed, PR opened, awaiting CI/review |
| `ci_failed` | CI checks failed — eligible for retry |
| `ci_passed` | CI checks passed, review pending |
| `review_changes_requested` | Reviewer requested changes — eligible for retry |
| `ready_to_merge` | All DoD gates passed — human notified |
| `merged` | PR merged (terminal) |
| `failed` | Driver execution failed — eligible for retry |
| `abandoned` | Task killed or max retries exceeded (terminal) |

Terminal states: `merged`, `abandoned`. No further transitions.

Retryable states: `failed`, `ci_failed`, `review_changes_requested`.

See [state-machine.md](references/state-machine.md) for the full transition map,
ASCII diagram, and agent interpretation guide.

## Reference Documents

| Document | Purpose |
|----------|---------|
| [state-machine.md](references/state-machine.md) | Full state definitions, transition map, ASCII diagram, agent interpretation |
| [driver-matrix.md](references/driver-matrix.md) | Four drivers, auto-selection heuristics, model normalization |
| [dod-gates.md](references/dod-gates.md) | 7 Definition of Done gates, notification policy |
| [retry-policy.md](references/retry-policy.md) | Evidence-driven retry rules and steering discipline |
| [notification.md](references/notification.md) | OpenClaw notification config, routing, progress updates, cron setup |
