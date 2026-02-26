# 30X Swarm - Private Distribution Pack

Reusable 30X Swarm control plane package for organization-wide seeding.

<directory>
swarm-core/ - Runtime core (CLI/state machine/drivers/templates)
reference/ - Architecture, constitution, and usage docs
</directory>

<config>
README.md - Installation and operations guide for other agents
install.sh - One-command installer to deploy runtime into ~/.openclaw/swarm-core
AGENTS.md - Repository map and maintenance protocol
</config>

Rules
- Keep `swarm-core/` executable and self-contained.
- Keep docs aligned with runtime behavior before each release.
- Preserve `default_driver = "codex"` unless explicitly changed by owner.

[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
