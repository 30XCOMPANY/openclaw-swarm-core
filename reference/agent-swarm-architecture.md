<!--
[INPUT]: OpenClaw native capability verification, delivery CLI implementation in skills/delivery/bin/
[OUTPUT]: 30X Swarm x OpenClaw architecture description and layered chain
[POS]: reference architecture doc, connects north-star, constitution, and usage
[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
-->

# 30X Swarm Architecture

Status: Current
Scope: OpenClaw-native conversational delivery

## 1. Core Framing

The system is a two-layer collaboration:

- **OpenClaw native session layer**: remote entry, ongoing conversation, session history, steering, status queries, sub-session spawning
- **30X Swarm delivery kernel**: task state machine, driver dispatch, PR/CI/review gates, retry, cleanup

Their relationship is division of labor, not substitution:

- OpenClaw owns understanding and continuously receiving human intent
- Swarm ensures the delivery process is controllable, monitorable, and recoverable on the machine side

In this repository, there is one additional packaging fact:

- `skills/` is the user-facing front door
- `skills/delivery/bin/` is the shell runtime embedded inside the delivery skill
- `reference/` is the maintainer documentation layer

The implementation is two skill directories. The product surface is two slash commands: `/coding` and `/delivery`.

## 2. Why This Split Exists

If business intent, multi-turn clarification, history memory, remote messaging, and code execution were all crammed into one executor, two forms of degradation would occur simultaneously:

- The conversation system lacks deterministic delivery constraints, easily stopping at "answered as if complete"
- The code executor lacks conversational continuity, easily treating each follow-up as a new task

After layering:

- OpenClaw preserves conversational continuity and business semantics
- Swarm preserves delivery determinism and machine-verifiable state
- Coding harnesses are responsible only for high-quality execution, not the business control plane

## 3. Native OpenClaw Abilities The Architecture Depends On

The architecture is explicitly built on these verified native OpenClaw capabilities:

- `agent` / `agents`
- `sessions` / `sessions_history` / `sessions_send` / `sessions_yield`
- `session_status`
- `sessions_spawn`
- `subagents`
- `message`
- `acp`
- agent runtime tools: `read/edit/write/exec/process`

The foundation exists today; no future capabilities are assumed.

## 4. Runtime Topology

```
HUMAN -> Channel (Discord / Telegram / Direct)
      -> OpenClaw Native Session Layer
      -> Session / History / Steering
      -> Delegation Boundary
      -> 30X Swarm Delivery Kernel (skills/delivery/bin/)
      -> Driver Layer (codex / claudecode / opencode / gemini-cli)
      -> Coding Harness Execution
      -> GitHub PR / CI / Review
      -> SQLite Task State (single source of truth)
      -> Back to OpenClaw for status reporting
```

## 5. Conversational Delivery Chain

The standard chain is not `spawn -> PR`, but:

`conversation -> clarify -> delegate -> execute -> monitor -> steer/retry -> ready_to_merge -> merge`

Three key points:

1. **Conversation is primary**
- The user sees an OpenClaw conversation, not `tmux`

2. **Delegation is explicit**
- OpenClaw delegates intent to Swarm, rather than exposing Swarm as the user product surface

3. **Delivery is artifact-backed**
- Delivery completion is marked by PR/gates/state, not by the agent saying "I'm done"

Direct requirements for repo organization:

- README leads with skills, then runtime
- `skills/` is the first thing users see
- `reference/` does not replace skills as the onboarding entry

## 6. Responsibility Split

### OpenClaw
- Receive remote requirements
- Maintain conversational context
- Support multi-turn supplements, interruptions, continuation
- Answer task status queries
- Decide when to delegate to Swarm

### Swarm (delivery CLI)
- Create isolated execution contexts (worktree + branch + tmux session)
- Select and drive coding harnesses
- Establish PR artifact chain
- Monitor and retry via external signals
- Provide queryable delivery state to OpenClaw

### Coding Harness
- Follow prompt and DoD
- Execute implementation in isolated workspace
- Generate commits, branches, PRs, and required artifacts

## 7. Why Swarm Still Matters

Even with OpenClaw's native coding tool delegation, Swarm has independent value:

- It makes execution behavior a stable protocol
- It makes PR/CI/review/screenshot gates a deterministic state machine
- It makes failure retry an evidence-driven loop
- It unifies different coding harnesses behind a single delivery interface

Swarm's moat is not "can invoke a CLI", but:

**Stably converging business intent from ongoing conversation into production-grade PRs.**

## 8. Architectural Consequences

This architecture means:

- Do not mistake more CLI support for the north star
- Do not downgrade OpenClaw to a mere message gateway
- Do not treat each follow-up as a brand new independent task
- Prioritize building stable mapping between OpenClaw sessions and Swarm tasks
- Prioritize building formal paths for interruption / continue / status query

[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
