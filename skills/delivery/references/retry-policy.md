<!--
[INPUT]: agent-swarm-constitution-v1.md section 9, legacy swarm_cli.py retry logic
[OUTPUT]: Evidence-driven retry rules and steering discipline
[POS]: delivery/references retry specification; consumed by SKILL.md and monitor.sh implementation
[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
-->

# Retry Policy

Retries are evidence-driven, never blind reruns. Every retry carries failure
context forward so the driver can address the specific problem.

## Evidence-Driven Retry Protocol

For every retry attempt, the system executes these 5 steps in order:

### Step 1: Capture Failure Evidence

Collect the concrete failure signal:

- **CI failure**: full CI output (truncated to 1800 chars if needed)
- **Review changes requested**: review delta (file-level comments, requested changes)
- **Driver crash**: stderr output, exit code, last known log lines
- **Missing artifact**: which artifact is missing and where it was expected

Evidence is stored in the `task_attempts` table with the attempt record.

### Step 2: Inject Evidence into Retry Prompt

The original task prompt is augmented with a `RETRY_CONTEXT` block:

```
<original prompt>

RETRY_CONTEXT:
Previous attempt failed with evidence:
<captured evidence>

Focus only on files relevant to this failure and complete DoD.
```

The retry prompt preserves the full original intent while narrowing
the driver's attention to the failure.

### Step 3: Narrow Scope When Needed

If the failure is localized (e.g., a single test file, a specific module),
the retry prompt explicitly narrows scope:

- Name the failing files or modules
- Name the failing tests
- Exclude unrelated areas from the driver's attention

Scope narrowing prevents the retry from re-doing work that already passed.

### Step 4: Increment Attempt Counter

Each retry increments the task's attempt counter. The counter is tracked
in SQLite and used to enforce the max attempts limit.

### Step 5: Stop at Max Attempts

When the attempt counter reaches `max_attempts` (default: 3, configured in
`.openclaw/delivery.conf`), the system:

1. Transitions the task to `abandoned`
2. Records the final failure evidence
3. Notifies the human with a summary of all attempts and their failure reasons
4. Does **not** retry again

## Retryable States

Only these states allow transition back to `running`:

| State | Retry Trigger |
|-------|---------------|
| `failed` | Driver execution failed (crash, timeout) |
| `ci_failed` | CI checks failed after PR creation |
| `review_changes_requested` | Reviewer requested changes |

Attempting to retry from any other state is an illegal transition.

## Steering Discipline

When the human sends a correction or clarification mid-flight:

### Rule 1: Preserve Task Identity

The correction is recorded against the **existing** task. A new task is
not created unless the human explicitly requests a fork.

```bash
delivery redirect --repo <path> --task-id <id> --message "..."
```

### Rule 2: Record Against Running Context

The correction message is injected into the running driver session.
If the driver supports redirect (all current drivers do), the message
reaches the driver without restarting the task.

### Rule 3: Prefer Redirect Over Respawn

When safe, use `redirect` to steer the existing task rather than
killing and respawning. Redirect preserves:

- Work already completed
- Branch and worktree state
- Attempt counter and history

Respawn is appropriate only when:
- The task is in a terminal state
- The original prompt was fundamentally wrong
- The human explicitly asks to start over

## Anti-Patterns

| Anti-Pattern | Why It Fails |
|-------------|-------------|
| Blind rerun | Same input produces same failure. No learning. |
| Full scope retry | Re-does passing work. Wastes time and may introduce regressions. |
| Silent respawn | Loses attempt history and failure evidence. Breaks audit trail. |
| Skip evidence capture | Next attempt has no context for what went wrong. |
| Retry from wrong state | Illegal transition. State engine rejects it. |

[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
