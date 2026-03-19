# 30X Swarm - Skills-First Swarm Delivery System

Reusable OpenClaw package where skills are the public product surface and `swarm-core/` is the internal delivery runtime.

<directory>
skills/ - Public entry layer with fixed slash surfaces (`/coding`, `/delivery`, `/swarm`)
  skills/delivery/ - Shell-based delivery CLI (spawn/monitor/kill/cleanup) with SQLite state
  skills/coding/ - Coding skill (placeholder)
swarm-core/ - Internal runtime core (CLI/state machine/drivers/templates)
reference/ - Maintainer docs for system definition, architecture, and constitution
.archive/ - Historical material and superseded operational docs
</directory>

<config>
README.md - Installation and operations guide for other agents
CHANGELOG.md - Release log for runtime behavior changes and verification notes
install.sh - One-command installer to deploy runtime into ~/.openclaw/swarm-core
AGENTS.md - Repository map and maintenance protocol
</config>

Rules
- Keep `skills/` as the only public product surface.
- Keep `swarm-core/` executable and self-contained.
- Keep `reference/` maintainer-facing; do not let it outrank the user entry path.
- Keep docs aligned with runtime behavior before each release.
- Preserve `default_driver = "codex"` unless explicitly changed by owner.

[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
