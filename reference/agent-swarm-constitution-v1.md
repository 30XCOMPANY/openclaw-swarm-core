# 30X Swarm Constitution v1

Status: Draft v1  
Scope: 30X Swarm orchestration for local coding-agent delivery  
Aligned Source: Elvis OpenClaw + Agent Swarm article (2026-02-23)

## 1) System Intent

The system exists to convert human business intent into deterministic, merge-ready software delivery with minimal human interruption.

Primary objective:
- Maximize delivered value per unit of human attention.

Non-objective:
- Maximizing raw commit count, model usage, or parallel sessions.

## 2) Role Contract (Human / Zoe / Coding Tools)

Human (owner):
- Owns priority, trade-offs, acceptance criteria, and final merge decision.
- Intervenes only at high-leverage points.

Zoe (OpenClaw orchestration layer):
- Owns scoping, context packaging, tool selection, execution routing, monitoring, retries, and notifications.
- Holds business context and historical memory.
- Must not delegate privileged business data directly to execution tools unless required and scoped.

Coding tools (Codex / OpenCode / ClaudeCode / Gemini CLI):
- Own execution in isolated coding environments.
- Follow task prompt + Definition of Done gates.
- Do not make product-priority decisions.

## 3) Hard Invariants

1. Context separation:
- Business context belongs to orchestrator.
- Code context belongs to coding tools.

2. Isolation by default:
- Each attempt runs in its own `worktree + branch + tmux session + log stream`.

3. Deterministic monitoring:
- Monitoring relies on external signals (git, tmux, PR, CI, review states), not chat polling loops.

4. Single source of truth:
- Canonical task state must live in one authority store.
- Any JSON file is projection/compatibility output, not canonical state.

5. Idempotent operations:
- Spawn, retry, monitor, and cleanup must be safe to re-run.

## 4) Canonical Task Lifecycle

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

Rules:
- No state jump to `ready_to_merge` without passing all DoD gates.
- Retry only from `failed`, `ci_failed`, or `review_changes_requested`.
- `merged` and `abandoned` are terminal states.

## 5) Unified Driver Contract (Multi-CLI)

Each execution tool must implement the same contract:
- `preflight(task, env) -> capabilities`
- `launch(run_ctx) -> session_ref`
- `redirect(session_ref, message) -> ack`
- `probe(session_ref) -> alive|exited`
- `collect(run_ctx) -> branch/pr/check artifacts`
- `normalize_error(raw) -> structured failure reason`

Constraint:
- Core orchestration flow cannot branch on tool internals beyond the driver boundary.

## 6) Definition of Done (Gate System)

A task becomes `ready_to_merge` only when all gates pass:
1. Branch pushed.
2. PR created and linked to task.
3. Branch is mergeable against target base.
4. Required CI checks pass.
5. Required AI review checks pass (Codex, Gemini, Claude where configured).
6. If UI-affecting diff is detected, screenshot artifact exists in PR description or attachment set.
7. No unresolved critical review request.

Notification policy:
- Human is notified once when gate status flips to `ready_to_merge`.

## 7) Retry Discipline (Ralph Loop V2)

Retries are evidence-driven, never blind reruns.

For every retry:
1. Capture failure evidence (CI output, review deltas, missing artifacts).
2. Inject evidence into retry prompt.
3. Narrow scope when needed (files/modules/tests).
4. Increment attempt counter.
5. Stop at max attempts and escalate to human.

## 8) Security Boundary

1. Orchestrator may access sensitive context under least-privilege policy.
2. Coding tools must not hold production write credentials.
3. Secrets must be loaded from secure runtime sources, never committed in plain text configs.
4. Review/CI artifacts can flow to tools; raw customer-sensitive records cannot by default.

## 9) Scheduling and Cost Control

1. Monitoring loop interval default: 10 minutes.
2. Cleanup loop interval default: daily.
3. Trigger notifications only for actionable transitions.
4. Avoid conversational polling for machine-checkable signals.

## 10) Seed Protocol (Project Onboarding)

Each new project should be "seeded", not forked:
- Keep one global orchestration core.
- Generate per-project minimal config + logs + compatibility projection only.
- Do not duplicate core swarm scripts per project.

## 11) Non-Goals

- Per-project script forks as long-term architecture.
- Embedding business orchestration logic inside execution drivers.
- Human babysitting terminals for routine status checks.

## 12) Conformance Checklist

A setup is considered conformant only if:
- Role contract is respected.
- Invariants hold.
- Canonical lifecycle is enforced.
- Driver contract supports all configured tools.
- DoD gates are fully automated.
- Retry policy is evidence-driven.
- Seed protocol prevents script drift.

[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
