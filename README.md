# OpenClaw Swarm Core (Private Distribution)

Global Delivery OS for OpenClaw agent swarm.

This repo packages a reusable, project-agnostic swarm control plane with:
- deterministic task state machine
- multi-driver execution (`codex`, `claudecode`, `opencode`, `gemini-cli`)
- SQLite truth source + JSON compatibility projection
- OpenClaw-native notifications (`openclaw message send`)
- per-project thin wrappers via `swarm seed`

## Contents

- `swarm-core/` global control plane runtime
- `reference/` architecture / constitution / usage docs
- `install.sh` one-command installer for agents

## Requirements

- macOS/Linux shell
- `python3` (3.11+ recommended)
- `git`, `tmux`, `gh`
- at least one coding CLI installed:
  - `codex`
  - `claude`
  - `opencode`
  - `gemini`

## Agent Self-Install

```bash
git clone https://github.com/20XCOMPANY/openclaw-swarm-core.git
cd openclaw-swarm-core
./install.sh --yes --link-bin
```

What it does:
- installs runtime to `~/.openclaw/swarm-core`
- keeps backup of existing install (`.bak.<timestamp>`)
- optionally links `~/.local/bin/swarm` -> `~/.openclaw/swarm-core/swarm`

## Verify

```bash
~/.openclaw/swarm-core/swarm --help
# or if --link-bin used:
swarm --help
```

## Bootstrap a Project

```bash
swarm seed --repo /abs/path/to/your/repo
```

Then use generated wrappers in project `.openclaw/`:

```bash
./.openclaw/spawn-agent.sh --id "task-$(date +%s)" --agent codex --prompt "your task"
./.openclaw/check-agents.sh
./.openclaw/status.sh
./.openclaw/cleanup.sh
```

## Driver Notes

- Default project driver is `codex`
- `claude` alias maps to `claudecode`
- `gemini-cli` is executable and can be toggled via project config:

```toml
[drivers.gemini-cli]
model = "gemini-2.5-pro"
reasoning = "high"
enabled = true
```

## Notification Notes

Notifications are sent by OpenClaw itself (not raw webhook scripts):
- command path: `openclaw message send ...`
- configured in each project `.openclaw/project.toml` under `[notifications]`

## Release Update

```bash
cd openclaw-swarm-core
git pull
./install.sh --yes --link-bin
```

## References

- `reference/agent-swarm-usage.md`
- `reference/agent-swarm-architecture.md`
- `reference/agent-swarm-constitution-v1.md`
