<div align="center">

# 30X SWARM
### OPENCLAW EDITION // CONVERSATIONAL DELIVERY KERNEL

<p>
  <img src="https://img.shields.io/badge/Visibility-PRIVATE-0f172a?style=for-the-badge" alt="private" />
  <img src="https://img.shields.io/badge/Default_Driver-codex-111827?style=for-the-badge" alt="default-driver" />
  <img src="https://img.shields.io/badge/State_Truth-SQLite-1f2937?style=for-the-badge" alt="sqlite" />
  <img src="https://img.shields.io/badge/Notifications-OpenClaw-334155?style=for-the-badge" alt="openclaw-notify" />
</p>

<p><strong>OpenClaw steers the conversation. Swarm converges the delivery.</strong></p>

</div>

---

## Why 30X?

`openclaw-swarm-core` is a reusable swarm delivery kernel for OpenClaw-native conversational software delivery.

`30X` means leverage, not layoffs.
- target: every employee gets the effective execution bandwidth of a 30-person org unit
- method: OpenClaw conversation + deterministic delivery gates + standardized coding harness behavior
- outcome: faster shipping without surrendering quality controls

It gives every repo the same hardened runtime:
- OpenClaw-native conversational delegation
- deterministic task state machine
- multi-driver execution (`codex`, `claudecode`, `opencode`, `gemini-cli`)
- SQLite truth source + JSON compatibility projection
- OpenClaw-native notifications (`openclaw message send`)
- thin per-project wrappers via `swarm seed`
- optional skills layer for `/coding`, `/delivery`, and `/swarm`

North star:

**Under ongoing conversation and steering through OpenClaw, maximize production-grade merged deliveries per unit of human attention.**

---

## Conversational Delivery Chain

| Stage | Owner | Output |
|---|---|---|
| Conversation | Human + OpenClaw | scoped and clarified requirement |
| Delegation | OpenClaw | task + driver + steering context |
| Execution | swarm + driver + worktree + tmux | commits + branch + PR attempt |
| Deterministic Monitor | `swarm monitor tick` | state updates + retries + gates |
| Gate | DoD checks | `ready_to_merge` or failure path |
| Notification | OpenClaw message layer | channel update and status reply |

---

## 90-Second Install

```bash
git clone https://github.com/30XCOMPANY/openclaw-swarm-core.git
cd openclaw-swarm-core
./install.sh --yes --link-bin
```

Installer behavior:
- deploy runtime into `~/.openclaw/swarm-core`
- backup previous install as `.bak.<timestamp>`
- optionally link `~/.local/bin/swarm` to runtime binary

Verify:

```bash
swarm --help
# or
~/.openclaw/swarm-core/swarm --help
```

---

## Ask An OpenClaw Agent To Install The Skills

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

## Skill Modes

Use the three skills as distinct product surfaces, not loose synonyms:

| Slash | Purpose | Key Rule |
|---|---|---|
| `/coding` | direct coding in the current conversation | ask for harness first if not already chosen |
| `/delivery` | tracked Swarm delivery toward PR-backed merge-ready output | do not force harness selection first |
| `/swarm` | inspect or control an existing Swarm task | read status first; retry progression happens via monitor |

---

## Bootstrap Any Repository

```bash
swarm seed --repo /abs/path/to/repo
```

Seed generates project `.openclaw/` wrappers:
- `spawn-agent.sh`
- `redirect-agent.sh`
- `check-agents.sh`
- `status.sh`
- `cleanup.sh`

---

## Command Deck

```bash
# 1) Spawn
./.openclaw/spawn-agent.sh \
  --id "task-$(date +%s)" \
  --agent codex \
  --progress-every 5 \
  --prompt "ship feature X"

# 2) Mid-flight correction
./.openclaw/redirect-agent.sh <task-id> "focus API first then UI"

# 3) Deterministic monitor loop
./.openclaw/check-agents.sh

# 4) Inspect and cleanup
./.openclaw/status.sh --json
./.openclaw/cleanup.sh
```

---

## 30X System Map

```mermaid
flowchart TB
    HUMAN["Remote Human"]
    CH["Discord / Telegram / Direct"]
    OC["OpenClaw Native Session Layer"]
    SES["Sessions + History + Steering"]
    DEL["Delegation Boundary"]
    SW["swarm Delivery Kernel"]
    DR["Driver Layer"]
    HAR["Codex / Claude / OpenCode / Gemini"]
    ACP["ACP Bridge Surface"]
    GH["GitHub PR / CI / Reviews"]
    DB["SQLite Task Truth"]
    NT["OpenClaw Notify"]

    HUMAN --> CH
    CH --> OC
    OC --> SES
    SES --> DEL
    DEL --> SW
    SW --> DR
    DR --> HAR
    HAR --> GH
    OC -. optional bridge .-> ACP
    GH --> SW
    SW --> DB
    DB --> OC
    SW --> NT
    NT --> HUMAN

    TICK["cron every 10 minutes<br/>swarm monitor tick"] --> SW
```

Current reality:

- current Swarm drivers are direct CLI adapters
- ACP is an OpenClaw bridge surface, not a current Swarm driver path
- future ACP-backed drivers can be added later without changing the delivery kernel

---

## Driver Matrix

| Driver | Primary Use | Default Model | Notes |
|---|---|---|---|
| `codex` | backend, complex reasoning | inherit Codex default | default driver |
| `claudecode` | frontend, rapid iteration | inherit Claude Code default | `claude` alias supported |
| `opencode` | OpenCode flows | inherit OpenCode default | set `model` only when you want explicit override |
| `gemini-cli` | Gemini CLI execution | inherit Gemini CLI default | auth required |

ACP note:

- ACP is not listed here because it is not a current `swarm-core` driver
- ACP belongs to the OpenClaw bridge layer today
- an ACP-backed driver is a future integration path, not current runtime behavior

`gemini-cli` can be toggled per project:

```toml
[drivers.gemini-cli]
model = "gemini-2.5-pro"
reasoning = "high"
enabled = true
```

---

## Notification Path

Notifications are sent by OpenClaw itself, not raw webhook scripts.

- sender: `openclaw message send`
- config location: project `.openclaw/project.toml` -> `[notifications]`
- defaults: disabled + empty target (must be explicitly configured)
- routing priority: task source session target -> project static target
- recommended events: `ready_to_merge`, `merged`
- optional noisy events (`abandoned`, `failed`, `ci_failed`, `review_changes_requested`) require `allow_failure_events = true`
- progress output layer: active tasks emit `System: [swarm-progress] ...` every 5 minutes by default
- per-task override: pass `--progress-every <minutes>` at spawn, or `--no-progress` to disable

---

## Upgrade Protocol

```bash
cd openclaw-swarm-core
git pull
./install.sh --yes --link-bin
```

---

## Repo Structure

- `swarm-core/` runtime core
- `reference/` system definition, architecture, and constitution
- `skills/` agent-facing operation skills
- `.archive/` superseded operational docs and history
- `install.sh` one-command agent installer

---

## Reading Order

1. `reference/agent-swarm-north-star-v1.md`
2. `reference/agent-swarm-architecture.md`
3. `reference/agent-swarm-constitution-v1.md`
4. `skills/openclaw-direct-coding/` -> `/coding`
5. `skills/openclaw-advanced-delivery/` -> `/delivery`
6. `skills/swarm-task-control/` -> `/swarm`
