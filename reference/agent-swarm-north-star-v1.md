<!--
[INPUT]: OpenClaw native capability verification, delivery CLI implementation in skills/delivery/bin/
[OUTPUT]: 30X Swarm north star definition, capability commitments, and metrics
[POS]: reference product definition doc, referenced by constitution and architecture
[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
-->

# 30X Swarm North Star v1

Status: Active
Scope: OpenClaw-native conversational delivery system

## 1. System Definition

30X Swarm is not an isolated script collection, nor a one-shot code generator.

System definition:

**OpenClaw-native conversational control plane + swarm deterministic delivery kernel**

The public product surface in this repository:

- `/coding` — direct coding through ACP harnesses
- `/delivery` — tracked delivery with PR gates, retries, cleanup

Users enter through skills; Swarm works as the deterministic kernel behind those skills. The delivery runtime lives inside the skill at `skills/delivery/bin/`.

One-line north star:

**Let the user simply converse remotely with OpenClaw, while OpenClaw drives Swarm using native session and tool capabilities to stably converge multi-turn intent into auditable, trackable, mergeable production-grade PRs.**

## 2. Native Ability Anchor

The north star is built on verified, existing OpenClaw native capabilities:

- Multi-channel remote conversation entry
- Persistent sessions and session history
- Native agent execution capabilities (`read/edit/write/exec/process`)
- Sub-sessions and task spawning (`sessions_spawn`, `subagents`)
- ACP / coding harness bridging capability
- In-flight steering, continuation, and status queries

## 3. Role Split

OpenClaw:
- The sole user-facing entry point
- Owns conversational continuity, multi-turn clarification, in-flight interruption, constraint addition, status queries

swarm (delivery CLI):
- Owns deterministic delivery convergence
- Owns worktree, driver, PR, CI, review, retry, cleanup
- Implemented as shell CLI with zero Python dependency

coding harness:
- Owns unified execution behavior, quality constraints, DoD adherence, and PR artifact format

## 4. North Star Metric

Primary metric:

**Under ongoing conversation and steering through OpenClaw, maximize production-grade merged deliveries per unit of human attention.**

## 5. Success Metrics

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

## 6. Product Contract

The system commits to:
- Users first encounter skills, not runtime directory structure
- Users only need to converse with OpenClaw, not directly operate underlying coding tools
- Users can continue adding constraints, interrupt, or request continuation during execution
- Default artifact is trackable task state and PR, not just text replies
- The system commits to high-determinism delivery and production-grade quality, not absolute zero errors

[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
