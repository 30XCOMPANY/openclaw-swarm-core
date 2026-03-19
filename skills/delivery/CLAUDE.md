# delivery/
> L2 | Parent: skills/CLAUDE.md

Self-contained delivery skill — shell CLI + docs. Merges old `/delivery` and `/swarm` into one surface.

## Members

- `SKILL.md`: Skill entrypoint with frontmatter, trigger rules, command cheatsheet, state overview
- `agents/openai.yaml`: OpenAI-compatible agent manifest for /delivery invocation
- `references/state-machine.md`: 10 states, full transition map, ASCII diagram, agent interpretation guide
- `references/driver-matrix.md`: 4 drivers, auto-selection heuristics, model normalization rules
- `references/dod-gates.md`: 7 Definition of Done gates, notification policy, failure recovery
- `references/retry-policy.md`: Evidence-driven retry protocol, steering discipline, anti-patterns
- `references/notification.md`: OpenClaw notification config, routing, progress updates, cron setup

## bin/

- `delivery`: Main entrypoint, dispatches subcommands to lib/ modules
- `schema.sql`: SQLite DDL (7 tables, 7 indexes), byte-compatible with legacy swarm.db

## bin/lib/

- `common.sh`: State constants, config loader, SQLite helpers, repo utilities
- `drivers.sh`: Driver selection, command building, model normalization (4 functions)
- `git-ops.sh`: Git worktree, branch, PR, CI check, review, UI detection, cleanup (10 functions)
- `notify.sh`: OpenClaw notification routing and dispatch — status/progress notifications (12 functions)

[PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
