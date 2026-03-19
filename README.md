<div align="center">

# 30X SWARM
### OPENCLAW EDITION // SKILLS-FIRST DELIVERY SYSTEM

<p>
  <img src="https://img.shields.io/badge/Visibility-PRIVATE-0f172a?style=for-the-badge" alt="private" />
  <img src="https://img.shields.io/badge/Public_Surface-Skills-111827?style=for-the-badge" alt="skills-first" />
  <img src="https://img.shields.io/badge/Runtime-Swarm_Core-1f2937?style=for-the-badge" alt="runtime" />
  <img src="https://img.shields.io/badge/State_Truth-SQLite-334155?style=for-the-badge" alt="sqlite" />
</p>

<p><strong>Users enter through skills. Swarm does the delivery underneath.</strong></p>

</div>

---

## Start Here

`openclaw-swarm-core` is a skills-first package that exposes the Swarm system to OpenClaw through three stable slash entrypoints:

| Slash | Purpose | User Contract |
|---|---|---|
| `/coding` | direct coding in the current conversation | choose a harness and execute now |
| `/delivery` | tracked Swarm delivery | create a task and converge toward PR-backed merge-ready output |
| `/swarm` | task control for existing delivery work | inspect status, redirect, monitor, cleanup, or kill |

If you only care about how users invoke the system, stop at `skills/`.

If you need to understand how the system works underneath, continue into `swarm-core/`.

If you maintain the product contract or architecture, read `reference/`.

---

## What This Repo Is

This repository is not "a runtime with some optional skills attached."

It is a delivery system packaged in three layers:

1. `skills/` is the public product surface.
2. `swarm-core/` is the internal delivery runtime.
3. `reference/` is the maintainer and governance layer.

That split matters:

- users should learn `/coding`, `/delivery`, and `/swarm`
- they should not need to learn `tmux`, worktrees, or retry state transitions first
- Swarm should remain a deterministic kernel behind the skill surface, not the first thing a user has to read

North star:

**Under ongoing conversation and steering through OpenClaw, maximize production-grade merged deliveries per unit of human attention.**

---

## Install

```bash
git clone https://github.com/30XCOMPANY/openclaw-swarm-core.git
cd openclaw-swarm-core
./install.sh --yes --link-bin
```

Installer behavior:

- deploy runtime into `~/.openclaw/swarm-core`
- back up previous install as `.bak.<timestamp>`
- optionally link `~/.local/bin/swarm` to the runtime binary

Verify:

```bash
swarm --help
# or
~/.openclaw/swarm-core/swarm --help
```

---

## Install The Skills Into OpenClaw

Send this block directly to an OpenClaw agent:

```text
Please install the three skills from https://github.com/30XCOMPANY/openclaw-swarm-core into my current OpenClaw environment.

Requirements:
- install `skills/openclaw-direct-coding` as `/coding`
- install `skills/openclaw-advanced-delivery` as `/delivery`
- install `skills/swarm-task-control` as `/swarm`
- keep the runtime install at `~/.openclaw/swarm-core`
- make sure slash commands are enabled for chat use
- if needed, set OpenClaw commands config to:
  - `commands.text = true`
  - `commands.native = true`
  - `commands.nativeSkills = true`

Execution steps:
1. Clone or update `openclaw-swarm-core`.
2. Run `./install.sh --yes --link-bin`.
3. Install or link the three skill folders into the current OpenClaw skills directory.
4. Verify that `/coding`, `/delivery`, and `/swarm` are available.
5. Reply with the final runtime path, skills path, and any restart/reload step that was required.
```

What this prompt is for:

- it gives another OpenClaw agent a single copy-paste install task
- it keeps the public entrypoints fixed as `/coding`, `/delivery`, and `/swarm`
- it standardizes slash-command enablement instead of relying on implicit defaults

---

## How Users Should Think About The System

Use the skills as distinct product surfaces, not loose synonyms:

| When the user means... | Use | Why |
|---|---|---|
| "Fix this now in the current thread." | `/coding` | direct execution beats orchestration |
| "Take this to PR / merge-ready." | `/delivery` | task tracking, gates, retries, and cleanup matter |
| "What is that task doing?" | `/swarm` | an existing Swarm task needs control, not re-spawn |

The clean mental model is:

- `/coding` = execution mode
- `/delivery` = delivery mode
- `/swarm` = control mode

---

## What Swarm Does Under The Skills

When a user enters `/delivery`, the skill hands work to the Swarm runtime.

Swarm then provides:

- deterministic task state machine
- worktree + branch + tmux isolation
- multi-driver execution (`codex`, `claudecode`, `opencode`, `gemini-cli`)
- SQLite truth source plus JSON compatibility projection
- PR / CI / review monitoring
- evidence-driven retries through `swarm monitor tick`
- cleanup through `swarm cleanup tick`
- OpenClaw-native notifications via `openclaw message send`

This is why the repo is skills-first, not skills-only.

The skills are the front door. `swarm-core/` is the machinery behind that door.

---

## Bootstrap A Repository

```bash
swarm seed --repo /abs/path/to/repo
```

Seed generates project `.openclaw/` wrappers:

- `spawn-agent.sh`
- `redirect-agent.sh`
- `check-agents.sh`
- `status.sh`
- `cleanup.sh`

Typical operator flow:

```bash
# 1) Spawn tracked delivery work
./.openclaw/spawn-agent.sh \
  --id "task-$(date +%s)" \
  --agent codex \
  --progress-every 5 \
  --prompt "ship feature X"

# 2) Mid-flight correction
./.openclaw/redirect-agent.sh <task-id> "focus API first then UI"

# 3) Monitor and retry progression
./.openclaw/check-agents.sh

# 4) Inspect and clean up
./.openclaw/status.sh --json
./.openclaw/cleanup.sh
```

---

## Repo Layout

| Path | Role |
|---|---|
| `skills/` | public user-facing skill surface |
| `swarm-core/` | internal runtime and deterministic delivery kernel |
| `reference/` | maintainer docs, architecture, constitution, and north star |
| `install.sh` | runtime installer |
| `CHANGELOG.md` | runtime behavior and verification log |

Reading order:

1. `skills/openclaw-direct-coding/`
2. `skills/openclaw-advanced-delivery/`
3. `skills/swarm-task-control/`
4. `swarm-core/`
5. `reference/`

---

## Runtime Notes

### Driver Matrix

| Driver | Primary Use | Default Model | Notes |
|---|---|---|---|
| `codex` | backend, debugging, complex reasoning | inherit Codex default | default driver |
| `claudecode` | frontend and rapid iteration | inherit Claude Code default | `claude` alias supported |
| `opencode` | OpenCode-native flows | inherit OpenCode default | set `model` only when explicit override matters |
| `gemini-cli` | Gemini CLI execution | inherit Gemini CLI default | auth required |

`gemini-cli` can be enabled per project:

```toml
[drivers.gemini-cli]
model = "gemini-2.5-pro"
reasoning = "high"
enabled = true
```

### Notification Path

Notifications are sent by OpenClaw itself, not raw webhook scripts.

- sender: `openclaw message send`
- config path: project `.openclaw/project.toml` -> `[notifications]`
- defaults: disabled with empty target
- routing priority: task source session target -> project static target
- recommended events: `ready_to_merge`, `merged`
- noisy failure events require `allow_failure_events = true`
- progress output emits `System: [swarm-progress] ...` every 5 minutes by default

### Upgrade

```bash
cd openclaw-swarm-core
git pull
./install.sh --yes --link-bin
```

---

## Maintainer Reading

Use `reference/` when you need the deeper contract:

1. `reference/agent-swarm-north-star-v1.md`
2. `reference/agent-swarm-architecture.md`
3. `reference/agent-swarm-constitution-v1.md`

Those docs are for maintainers and system design, not for first-contact user onboarding.
