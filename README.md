<div align="center">

# 30X SWARM
### OPENCLAW EDITION // SKILLS-FIRST DELIVERY SYSTEM

<p>
  <img src="https://img.shields.io/badge/Visibility-PRIVATE-0f172a?style=for-the-badge" alt="private" />
  <img src="https://img.shields.io/badge/Public_Surface-Skills-111827?style=for-the-badge" alt="skills-first" />
  <img src="https://img.shields.io/badge/Runtime-Shell-1f2937?style=for-the-badge" alt="runtime" />
  <img src="https://img.shields.io/badge/State_Truth-SQLite-334155?style=for-the-badge" alt="sqlite" />
</p>

<p><strong>Users enter through skills. Delivery runs underneath.</strong></p>

</div>

---

## Start Here

`openclaw-swarm-core` exposes the Swarm system through two stable slash entrypoints:

| Slash | Purpose | User Contract |
|---|---|---|
| `/coding` | Direct coding through ACP harnesses | Choose a harness, execute synchronously in the current conversation |
| `/delivery` | Tracked delivery with PR gates, retries, cleanup | Create a task that converges toward merge-ready output |

If you only care about how users invoke the system, stop at `skills/`.

If you need to understand the delivery runtime, look inside `skills/delivery/bin/`.

If you maintain the product contract or architecture, read `reference/`.

---

## Install

```bash
git clone https://github.com/30XCOMPANY/openclaw-swarm-core.git
cd openclaw-swarm-core
./install.sh --yes --link-bin
```

Installer behavior:

- Copies `skills/coding/` and `skills/delivery/` to `~/.openclaw/skills/`
- Backs up previous install as `.bak.<timestamp>`
- Optionally symlinks `delivery` CLI to `~/.local/bin/delivery`

Verify:

```bash
delivery --help
```

---

## Install Skills Into OpenClaw

Send this block directly to an OpenClaw agent:

```text
Please install the skills from https://github.com/30XCOMPANY/openclaw-swarm-core into my current OpenClaw environment.

Requirements:
- install `skills/coding` as `/coding`
- install `skills/delivery` as `/delivery`
- make sure slash commands are enabled for chat use
- if needed, set OpenClaw commands config to:
  - `commands.text = true`
  - `commands.native = true`
  - `commands.nativeSkills = true`

Execution steps:
1. Clone or update `openclaw-swarm-core`.
2. Run `./install.sh --yes --link-bin`.
3. Install or link the two skill folders into the current OpenClaw skills directory.
4. Verify that `/coding` and `/delivery` are available.
5. Reply with the final runtime path, skills path, and any restart/reload step that was required.
```

---

## How Users Think About The System

| When the user means... | Use | Why |
|---|---|---|
| "Fix this now in the current thread." | `/coding` | Direct execution beats orchestration |
| "Take this to PR / merge-ready." | `/delivery` | Task tracking, gates, retries, and cleanup matter |
| "What is that task doing?" | `/delivery` | Status, redirect, monitor, kill are all delivery subcommands |

The clean mental model:

- `/coding` = execution (synchronous, conversational, no PR orchestration)
- `/delivery` = delivery (tracked, async, PR-backed, self-recovering)

---

## What Delivery Does Under The Skills

When a user enters `/delivery`, the skill hands work to the `delivery` CLI.

The delivery runtime provides:

- Deterministic task state machine (queued -> running -> pr_created -> ... -> merged)
- Worktree + branch + tmux session isolation per task attempt
- Multi-driver execution (`codex`, `claudecode`, `opencode`, `gemini-cli`)
- SQLite as single source of truth for task state
- PR / CI / review monitoring loop
- Evidence-driven retries (failure evidence injected into retry prompt)
- Cleanup of terminated task artifacts (worktrees, branches, tmux sessions)
- OpenClaw-native notifications via `openclaw message send`

The runtime is pure shell. Zero Python dependency.

---

## Bootstrap A Repository

```bash
delivery init --repo /abs/path/to/repo
```

This creates only the SQLite database at `<repo>/.openclaw/swarm.db`. No scripts are seeded into the project. `init` is also auto-called on first `spawn` if needed.

---

## Delivery CLI Commands

```bash
delivery spawn    --repo <path> --task-id <id> --driver <auto|codex|claudecode|claude|opencode|gemini-cli> --prompt "..."
delivery status   --repo <path> [--format json|text] [--task-id <id>]
delivery redirect --repo <path> --task-id <id> --message "..."
delivery monitor  --repo <path>
delivery kill     --repo <path> --task-id <id>
delivery cleanup  --repo <path>
delivery init     --repo <path>
```

Additional `spawn` flags:

| Flag | Purpose |
|---|---|
| `--prompt-file <path>` | Read prompt from file (mutually exclusive with `--prompt`) |
| `--source-session-key <key>` | OpenClaw session key for notification routing |
| `--notify-channel <ch>` | Notification channel (discord, telegram, etc.) |
| `--notify-target <target>` | Notification target identifier |
| `--notify-account <acct>` | Notification account |
| `--progress-every <min>` | Progress update interval in minutes |
| `--no-progress` | Disable progress updates |

Legacy project cleanup:

```bash
delivery cleanup --legacy
```

Removes old seeded scripts (`.openclaw/spawn-agent.sh`, etc.) from projects that used the previous `swarm seed` mechanism.

---

## Driver Matrix

| Driver | Primary Use | Default Model | Notes |
|---|---|---|---|
| `codex` | Backend, debugging, complex reasoning | Inherit Codex default | Default driver |
| `claudecode` | Frontend and rapid iteration | Inherit Claude Code default | `claude` alias supported |
| `opencode` | OpenCode-native flows | Inherit OpenCode default | |
| `gemini-cli` | Gemini CLI execution | Inherit Gemini CLI default | Auth required |

Auto driver selection (`--driver auto`): frontend-related prompts prefer `claudecode`; otherwise falls through priority `codex` > `claudecode` > `opencode` > `gemini-cli`, first available.

---

## Notification Path

- Sender: `openclaw message send`
- Config: `.openclaw/delivery.conf` (key=value format)
- Defaults: disabled
- Routing priority: task source session target -> project static target
- Recommended events: `ready_to_merge`, `merged`
- Noisy failure events require `notify_allow_failure_events=true`
- Progress updates emit `System: [swarm-progress] ...` at configured interval

---

## Upgrade

```bash
cd openclaw-swarm-core
git pull
./install.sh --yes --link-bin
```

---

## Repo Layout

| Path | Role |
|---|---|
| `skills/coding/` | `/coding` — pure text ACP operations guide |
| `skills/delivery/` | `/delivery` — self-contained delivery skill with embedded CLI |
| `skills/delivery/bin/` | Shell-based delivery runtime (CLI entrypoint + lib modules) |
| `reference/` | Maintainer docs: architecture, constitution, north star |
| `.archive/` | Historical material and superseded operational docs |
| `install.sh` | Skill installer + CLI linker |
| `CHANGELOG.md` | Release log for runtime behavior changes |

---

## Maintainer Reading

Use `reference/` when you need the deeper contract:

1. `reference/agent-swarm-north-star-v1.md` — product definition and metrics
2. `reference/agent-swarm-architecture.md` — layered system architecture
3. `reference/agent-swarm-constitution-v1.md` — governance, role contracts, invariants

Those docs are for maintainers and system design, not for first-contact user onboarding.
