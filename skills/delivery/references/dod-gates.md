<!--
[INPUT]: agent-swarm-constitution-v1.md section 8, legacy swarm_cli.py gate checks
[OUTPUT]: 7 Definition of Done gates and notification policy
[POS]: delivery/references DoD specification; consumed by SKILL.md and monitor.sh implementation
[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
-->

# Definition of Done Gates

A task becomes `ready_to_merge` only when **all 7 gates** pass.
No gate can be skipped. No premature readiness claims.

## The 7 Gates

### Gate 1: Branch Pushed

The task branch exists on the remote and contains at least one commit
beyond the base branch.

### Gate 2: PR Created and Linked

A pull request is open on GitHub, linked to the task record in SQLite.
The PR description references the task ID.

### Gate 3: Branch Mergeable

The branch has no merge conflicts against the target base branch.
If conflicts exist, the task cannot be considered ready — it must be
rebased or have conflicts resolved first.

### Gate 4: Required CI Checks Pass

All required CI checks configured in the repository must report a
passing status. Pending checks block the gate. Failed checks transition
the task to `ci_failed`.

### Gate 5: Required AI Review Checks Pass

Where configured, AI review tools (Codex review, Gemini review,
Claude review) must report passing status. This gate is only evaluated
if the repository has AI review checks configured — if none are configured,
the gate passes by default.

### Gate 6: UI Screenshot Present (Conditional)

If the diff touches UI-affecting files (detected by file extension and
path heuristics), a screenshot artifact must be present in the PR
description or attachment set.

UI-affecting extensions: `.tsx`, `.jsx`, `.css`, `.scss`, `.sass`, `.less`,
`.html`, `.vue`, `.svelte`.

UI path hints: `/client/`, `/web/`, `/frontend/`, `/ui/`, `/components/`,
`/pages/`, `/styles/`.

If no UI-affecting files are in the diff, this gate passes automatically.

### Gate 7: No Unresolved Critical Review Request

No open review thread marked as critical or change-requested remains
unresolved. Resolved or dismissed threads do not block this gate.

## Gate Evaluation Order

Gates are evaluated in order 1-7. Evaluation stops at the first failing
gate. The failing gate is recorded as the reason the task is not yet ready.

## Notification Policy

- The human is notified **once** when gate status flips to `ready_to_merge`.
- The system must **never** report readiness before all gates pass.
- Intermediate status queries are answered honestly with current state,
  but must not include language like "almost ready" or "should be ready soon."
- The system does not auto-merge. The human makes the final merge decision.

## Gate Failure Recovery

| Failing Gate | Recovery Path |
|-------------|---------------|
| Gate 1 (branch) | Driver must push commits. Usually resolves on first run. |
| Gate 2 (PR) | Driver or git-ops creates PR. Usually resolves on first run. |
| Gate 3 (mergeable) | Rebase against base branch. May require human intervention for complex conflicts. |
| Gate 4 (CI) | Evidence-driven retry with CI output. State transitions to `ci_failed`. |
| Gate 5 (AI review) | Evidence-driven retry with review feedback. |
| Gate 6 (screenshot) | Retry with instruction to capture screenshot. |
| Gate 7 (review) | Evidence-driven retry with review delta. State transitions to `review_changes_requested`. |

[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
