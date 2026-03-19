# 30X Swarm - Skills-First Delivery System

Reusable OpenClaw package where skills are the public product surface and the delivery runtime lives inside the skill.

<directory>
skills/coding/ - Pure text ACP operations guide (/coding)
skills/delivery/ - Self-contained delivery skill with embedded CLI (/delivery)
skills/delivery/bin/ - Shell-based delivery runtime (zero Python dependency)
reference/ - Maintainer docs for system definition, architecture, and constitution
.archive/ - Historical material and superseded operational docs
</directory>

<config>
README.md - Installation and operations guide for other agents
CHANGELOG.md - Release log for runtime behavior changes and verification notes
install.sh - One-command installer to deploy skills into ~/.openclaw/skills and link delivery CLI
AGENTS.md - Repository map and maintenance protocol
</config>

Rules
- Skills are the only public product surface. Users enter through `/coding` and `/delivery`.
- The delivery runtime (`skills/delivery/bin/`) is embedded inside the skill, not a separate top-level directory.
- `reference/` is maintainer-facing; it must not displace the skills entry path.
- Keep docs aligned with runtime behavior before each release.
- Preserve `default_driver = codex` unless explicitly changed by owner.
- No Python dependency. The entire delivery runtime is shell-based (bash + sqlite3 + git + jq + gh + tmux).

[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
