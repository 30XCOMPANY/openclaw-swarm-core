# Changelog

All notable changes to `30X Swarm` are documented in this file.

## 2026-03-19

### Changed (Breaking)
- Complete skills-first restructure
- `swarm-core/` removed; delivery runtime now lives in `skills/delivery/bin/`
- Three skills merged into two: `/coding` and `/delivery`
- `/swarm` merged into `/delivery`
- Python runtime replaced with shell (zero Python dependency)
- `project.toml` replaced with `delivery.conf` (key=value format)
- `swarm seed` removed; `delivery init` only creates SQLite DB
- Per-project seeded scripts removed; agent calls `delivery` CLI directly
- `active-tasks.json` removed; use `delivery status --format json`

### Added
- `delivery` CLI with subcommands: spawn, status, redirect, monitor, kill, cleanup, init
- Complete ACP operations guide in `/coding` skill
- `delivery cleanup --legacy` to remove old seeded scripts

## 2026-02-27

### Added
- Per-task progress update controls:
  - `--progress-every-minutes <N>`
  - `--no-progress-updates`
- Default progress cadence support from project config (`[progress] interval_minutes`, default `5`).
- Spawn-time notify route options:
  - `--source-session-key`
  - `--notify-channel`
  - `--notify-target`
  - `--notify-account`

### Changed
- Status notifications now support richer per-task routing metadata persisted in SQLite.
- Project wrapper templates forward progress and notify routing options to `swarm task spawn`.

### Fixed
- Monitor pass no longer attempts illegal transition `failed -> ci_failed`.
- Removed zombie-agent pattern where completion flow could block on interactive `read` in background sessions.
- Driver model fallback behavior verified:
  - `claudecode` with empty model does **not** pass `--model` (uses local Claude CLI default).
  - `opencode` with empty model does **not** pass `--model` (uses local OpenCode default).

### Verification Notes
- Captured launch argv for both drivers with and without explicit model values.
- Confirmed only explicit model paths include `--model`.
- Confirmed default path delegates model selection to local CLI configuration.
