<!--
[INPUT]: 依赖 OpenClaw 当前原生会话能力，依赖 swarm-core 状态机与驱动实现
[OUTPUT]: 对外提供 30X Swarm 宪法、角色边界、生命周期和交付约束
[POS]: reference 的治理核心文档，约束 architecture 和 usage 的口径
[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
-->

# 30X Swarm Constitution v1

Status: Active v1  
Scope: OpenClaw-native conversational delivery using swarm deterministic execution  
Aligned Source: Current OpenClaw runtime + current swarm-core implementation

## 1) System Intent

The system exists to let a human steer software delivery through OpenClaw conversation while swarm deterministically converges that intent into production-grade, merge-ready pull requests.

Primary objective:
- Maximize production-grade merged deliveries per unit of human attention under ongoing conversation and steering.

Non-objective:
- Maximizing raw commit count, model usage, parallel sessions, or CLI variety.

## 2) Product Definition

The system is:
- `OpenClaw-native conversational control plane`
- `swarm deterministic delivery kernel`
- `coding harness execution substrate`
- `skills-first product surface exposing /coding, /delivery, and /swarm`

The system is not:
- A standalone swarm product detached from OpenClaw sessions
- A one-shot code generator that stops at code snippets
- A promise of absolute zero-error execution

## 3) Role Contract (Human / OpenClaw / swarm / Coding Harness)

Human (owner):
- Owns priority, trade-offs, acceptance criteria, and final merge decision.
- Can steer, interrupt, clarify, or continue work through the same OpenClaw conversation.

OpenClaw:
- Owns remote entrypoints, conversation continuity, steering, status replies, and task delegation.
- Uses native session, agent, spawn, and messaging capabilities as the user-facing control plane.
- Must preserve the conversational thread as the authority for evolving business intent.

swarm:
- Owns deterministic task realization after delegation.
- Manages worktree isolation, driver launch, PR creation, CI/review monitoring, retries, and cleanup.
- Must expose task state in a way OpenClaw can query and report without guessing.

Coding harnesses (Codex / ClaudeCode / OpenCode / Gemini CLI / ACP-backed runtimes):
- Own execution inside the delegated coding environment.
- Follow task prompt + Definition of Done gates.
- Do not make product-priority decisions.

## 4) Hard Invariants

1. Conversational ownership:
- User-visible task intent belongs to the OpenClaw session.
- swarm is the execution kernel behind that conversation, not a separate product surface.

1a. Public entry discipline:
- The repo's public entry surface is the skills layer.
- `/coding`, `/delivery`, and `/swarm` are the stable user-facing entrypoints.
- Runtime internals and governance docs must not displace that entry path.

2. Context separation:
- Business context, steering history, and user corrections belong to OpenClaw.
- Code context and isolated execution belong to swarm + coding harness.

3. Stable delegation:
- Every swarm task must be attributable to an originating OpenClaw session or source channel context.
- A follow-up message must update the same delivery context, not create silent parallel intent by default.

4. Isolation by default:
- Each attempt runs in its own `worktree + branch + tmux session + log stream`.

5. Deterministic monitoring:
- Monitoring relies on external signals (git, tmux, PR, CI, review states), not chat polling loops.

6. Single source of truth:
- Canonical task state must live in one authority store.
- Any JSON file is projection/compatibility output, not canonical state.

7. Idempotent operations:
- Spawn, redirect, retry, monitor, and cleanup must be safe to re-run.

## 5) Conversational Delivery Contract

The system must support:
- starting a new coding task from an OpenClaw conversation
- continuing the same task with additional requirements
- interrupting and redirecting a running task
- asking for status without opening terminals
- converging to a PR-backed delivery artifact

The system must not assume:
- the user will manage `tmux` manually
- each clarification is a brand new task
- text completion alone counts as delivery completion

## 6) Canonical Task Lifecycle

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
- Conversational redirection must preserve task identity unless the operator explicitly forks the work.

## 7) Unified Driver Contract (Multi-CLI)

Each execution tool must implement the same contract:
- `preflight(task, env) -> capabilities`
- `launch(run_ctx) -> session_ref`
- `redirect(session_ref, message) -> ack`
- `probe(session_ref) -> alive|exited`
- `collect(run_ctx) -> branch/pr/check artifacts`
- `normalize_error(raw) -> structured failure reason`

Constraint:
- Core orchestration flow cannot branch on tool internals beyond the driver boundary.
- Driver diversity is allowed only when it preserves predictable delivery quality.

## 8) Definition of Done (Gate System)

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
- OpenClaw may answer intermediate status questions, but must not report readiness before gates pass.

## 9) Retry and Steering Discipline

Retries are evidence-driven, never blind reruns.

For every retry:
1. Capture failure evidence (CI output, review deltas, missing artifacts).
2. Inject evidence into retry prompt.
3. Narrow scope when needed (files/modules/tests).
4. Increment attempt counter.
5. Stop at max attempts and escalate to human.

For every steering event:
1. Preserve originating task identity unless intentionally forked.
2. Record the correction against the running delivery context.
3. Prefer redirect/continue over discard-and-respawn when safe.

## 10) Security Boundary

1. OpenClaw may access sensitive context under least-privilege policy.
2. Coding harnesses must not hold production write credentials.
3. Secrets must be loaded from secure runtime sources, never committed in plain text configs.
4. Review/CI artifacts can flow to tools; raw customer-sensitive records cannot by default.

## 11) Scheduling and Cost Control

1. Monitoring loop interval default: 10 minutes.
2. Cleanup loop interval default: daily.
3. Trigger notifications only for actionable transitions.
4. Avoid conversational polling for machine-checkable signals.
5. Prefer deterministic state reads over token-expensive status conversations.

## 12) Seed Protocol (Project Onboarding)

Each new project should be "seeded", not forked:
- Keep one global orchestration core.
- Generate per-project minimal config + logs + compatibility projection only.
- Do not duplicate core swarm scripts per project.
- Preserve an execution surface that OpenClaw can delegate into uniformly across repos.

## 13) Success Metrics

Primary metrics:
- `conversation-to-merge success rate`
- `human steering efficiency`
- `interruption recovery rate`
- `production-grade PR rate`

Guardrails:
- `session drift rate`
- `retry rate`
- `ci failure rate`
- `stuck-without-pr rate`

## 14) Non-Goals

- Per-project script forks as long-term architecture.
- Embedding business orchestration logic inside execution drivers.
- Human babysitting terminals for routine status checks.
- Treating "supports more tools" as a success proxy by itself.

## 15) Conformance Checklist

A setup is considered conformant only if:
- OpenClaw remains the user-facing conversational control plane.
- swarm remains the deterministic delivery kernel.
- Role contract is respected.
- Invariants hold.
- Canonical lifecycle is enforced.
- Driver contract supports all configured tools.
- DoD gates are fully automated.
- Retry and steering policy is evidence-driven.
- Seed protocol prevents script drift.

[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
