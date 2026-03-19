# delivery/
> L2 | Parent: skills/CLAUDE.md

Shell-based delivery CLI — deterministic task orchestration (spawn/monitor/kill/cleanup).

## bin/

- `delivery`: Main entrypoint, dispatches subcommands to lib/ modules
- `schema.sql`: SQLite DDL (7 tables, 7 indexes), byte-compatible with legacy swarm.db

## bin/lib/

- `common.sh`: State constants, config loader, SQLite helpers, repo utilities
- `drivers.sh`: Driver selection, command building, model normalization (4 functions)

[PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
