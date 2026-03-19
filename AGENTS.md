# 30X Swarm - OpenClaw-Native Delivery Pack

Reusable 30X Swarm delivery kernel package for OpenClaw-native conversational delivery.

<directory>
swarm-core/ - Runtime core (CLI/state machine/drivers/templates)
reference/ - System definition, architecture, and constitution docs
skills/ - Agent-facing operation layer (`/coding`, `/delivery`, and Swarm task control)
.archive/ - Historical material and superseded operational docs
</directory>

<config>
README.md - Installation and operations guide for other agents
CHANGELOG.md - Release log for runtime behavior changes and verification notes
install.sh - One-command installer to deploy runtime into ~/.openclaw/swarm-core
AGENTS.md - Repository map and maintenance protocol
</config>

Rules
- Keep `swarm-core/` executable and self-contained.
- Keep docs aligned with runtime behavior before each release.
- Preserve `default_driver = "codex"` unless explicitly changed by owner.

[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
