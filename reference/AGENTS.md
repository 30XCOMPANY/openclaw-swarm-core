# reference/
> L2 | Parent: AGENTS.md

Member list:
- AGENTS.md: `reference/` module map, defines directory boundaries and maintenance protocol.
- agent-swarm-architecture.md: 30X Swarm architecture, defines how OpenClaw native session layer and delivery kernel collaborate.
- agent-swarm-constitution-v1.md: 30X Swarm constitution, defines north star, role contracts, state machine, session-to-task mapping, and multi-CLI driver boundaries.
- agent-swarm-north-star-v1.md: 30X Swarm north star spec, defines product definition, capability commitments, and metrics.

Architecture boundary:
- This directory holds only static reference and governance docs for 30X Swarm; no runtime code.
- Operational content lives in `skills/*/references/`; this directory retains only system-level docs.
- This directory serves maintainers, architecture design, and release verification; first-time users should start at `skills/`.
- Code implementation and these docs must remain in sync: state machine, role boundaries, and DoD rules must not diverge.

Dependency:
- Input: root `AGENTS.md` (release rules), `skills/delivery/bin/` implementation (source of truth).
- Output: orchestration design, CLI interface constraints, control plane field and state definitions.

[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
