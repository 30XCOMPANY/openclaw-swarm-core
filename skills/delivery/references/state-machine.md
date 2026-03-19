<!--
[INPUT]: delivery bin/lib/state.sh transition map, legacy swarm_cli.py STATE_TRANSITIONS
[OUTPUT]: Authoritative state machine documentation — states, transitions, terminal/retryable classification, interpretation guide
[POS]: delivery/references canonical state machine spec; consumed by SKILL.md and monitor logic
[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
-->

# Delivery State Machine

Authoritative specification for the 10-state delivery lifecycle.

## States

| State | Description |
|-------|-------------|
| `queued` | Task record created in SQLite. Driver has not launched yet. |
| `running` | Driver is executing inside an isolated tmux session + worktree. |
| `pr_created` | Code pushed to branch, pull request opened. Awaiting CI and review. |
| `ci_failed` | One or more required CI checks failed. Eligible for evidence-driven retry. |
| `ci_passed` | All required CI checks passed. Review evaluation pending. |
| `review_changes_requested` | A reviewer requested changes. Eligible for evidence-driven retry. |
| `ready_to_merge` | All 7 DoD gates passed. Human has been notified. Awaiting merge decision. |
| `merged` | PR merged into target branch. **Terminal** — no further transitions. |
| `failed` | Driver execution failed (crash, timeout, unrecoverable error). Eligible for retry. |
| `abandoned` | Task killed by operator or max retries exceeded. **Terminal** — no further transitions. |

## Transition Map

```
queued               -> { running, abandoned }
running              -> { pr_created, failed, abandoned }
pr_created           -> { ci_failed, ci_passed, review_changes_requested,
                          ready_to_merge, merged, abandoned }
ci_failed            -> { running, abandoned }
ci_passed            -> { review_changes_requested, ready_to_merge, merged,
                          ci_failed, abandoned }
review_changes_requested -> { running, ready_to_merge, abandoned }
ready_to_merge       -> { merged, review_changes_requested, ci_failed, abandoned }
failed               -> { running, abandoned }
merged               -> { }   (terminal)
abandoned            -> { }   (terminal)
```

## ASCII Diagram

```
                              +-------------------------------------+
                              |                                     v
queued --> running --> pr_created --> ci_passed --> ready_to_merge --> merged
               |           |    |         |    |          |
               |           |    |         |    +-> ci_failed (regression)
               |           |    |         +-> review_changes_requested
               |           |    +-> ci_failed                |
               |           |    +-> review_changes_requested |
               |           +-> ready_to_merge ---------------+
               |           +-> merged (fast path)            |
               v                                             |
           failed --> running (retry with evidence)          |
               |                                             |
               +-----------------> abandoned <---------------+
                                (from any non-terminal state)
```

## Terminal States

- **`merged`** — Success. The PR was merged. Cleanup can remove worktree and branch.
- **`abandoned`** — Dead end. Task was killed or exceeded max retries. Cleanup can remove artifacts.

No transitions out of terminal states. Any attempt to transition from a terminal
state is an illegal operation and will be rejected by the state engine.

## Retryable States

These states allow a transition back to `running` via evidence-driven retry:

- **`failed`** — Driver crashed or timed out. Retry with failure evidence injected.
- **`ci_failed`** — CI checks failed. Retry with CI output as evidence.
- **`review_changes_requested`** — Reviewer asked for changes. Retry with review delta as evidence.

Retries are never blind reruns. See `retry-policy.md` for the full retry protocol.

## State Classification

| Category | States |
|----------|--------|
| Terminal | `merged`, `abandoned` |
| Retryable | `failed`, `ci_failed`, `review_changes_requested` |
| Active | `running`, `pr_created`, `ci_failed`, `ci_passed`, `review_changes_requested`, `ready_to_merge` |
| Waiting | `queued` |

## Agent State Interpretation Guide

When reporting task status to a human, use these interpretations:

### queued
> "Task is queued and will start shortly."

The task record exists but the driver has not launched. This is a transient state —
`delivery monitor` or the spawn flow will advance it to `running`.

### running
> "Task is actively being worked on by [driver]."

The coding harness is executing inside an isolated tmux session. Do not interrupt
unless the user explicitly asks to redirect or kill.

### pr_created
> "A pull request has been created. Waiting for CI and review."

The driver finished its coding work and pushed a branch with a PR. The system is
now watching for CI results and review feedback.

### ci_failed
> "CI checks failed. The system will attempt an evidence-driven retry."

CI output is captured as evidence. If retries remain, the monitor loop will
re-run the driver with the failure evidence injected into the prompt.

### ci_passed
> "CI checks passed. Waiting for review evaluation."

All required CI checks are green. The system is now evaluating review status
(AI reviews, human reviews if configured).

### review_changes_requested
> "A reviewer requested changes. The system will attempt to address them."

Review deltas are captured as evidence. If retries remain, the monitor loop
will re-run the driver with the review feedback injected into the prompt.

### ready_to_merge
> "All gates passed. Ready for your merge decision."

All 7 DoD gates are satisfied. The human has been notified. The system does
not auto-merge — the human makes the final call.

### merged
> "Done. PR merged successfully."

Terminal state. Cleanup can proceed.

### failed
> "Driver execution failed. The system will retry with failure evidence."

The driver process exited with an error or timed out. If retries remain,
the system will inject the error output into a retry prompt.

### abandoned
> "Task was abandoned (killed or max retries exceeded)."

Terminal state. No further action. Cleanup can proceed.

## Transition Validation

Every state transition is validated against the transition map before being
persisted. An attempt to make an illegal transition (e.g., `merged` -> `running`)
will be rejected with a non-zero exit code. This ensures the state machine
cannot be corrupted by buggy monitor logic or race conditions.

[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
