<div align="center">

# 30X SWARM
### OPENCLAW EDITION // PRIVATE DELIVERY OS

<p>
  <img src="https://img.shields.io/badge/Visibility-PRIVATE-0f172a?style=for-the-badge" alt="private" />
  <img src="https://img.shields.io/badge/Default_Driver-codex-111827?style=for-the-badge" alt="default-driver" />
  <img src="https://img.shields.io/badge/State_Truth-SQLite-1f2937?style=for-the-badge" alt="sqlite" />
  <img src="https://img.shields.io/badge/Notifications-OpenClaw-334155?style=for-the-badge" alt="openclaw-notify" />
</p>

<p><strong>Not replacing teams. Multiplying every individual into a 30-person department.</strong></p>

</div>

---

## Why 30X?

`openclaw-swarm-core` is a reusable swarm control plane.

`30X` means leverage, not layoffs.
- target: every employee gets the effective execution bandwidth of a 30-person org unit
- method: orchestration + deterministic delivery gates + multi-agent parallelism
- outcome: faster shipping without surrendering quality controls

It gives every repo the same hardened runtime:
- deterministic task state machine
- multi-driver execution (`codex`, `claudecode`, `opencode`, `gemini-cli`)
- SQLite truth source + JSON compatibility projection
- OpenClaw-native notifications (`openclaw message send`)
- thin per-project wrappers via `swarm seed`

---

## Swarm Kill Chain

| Stage | Owner | Output |
|---|---|---|
| Intent | Human | feature/bug instruction |
| Orchestration | OpenClaw | scoped task + selected driver |
| Execution | Driver + worktree + tmux | commits + branch + PR attempt |
| Deterministic Monitor | `swarm monitor tick` | state updates + retries + gates |
| Gate | DoD checks | `ready_to_merge` or failure path |
| Notification | OpenClaw message layer | Discord update to human |

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
    SEN["Sentry Error Logs"]
    SUP["Support Tickets"]
    ME["Me / Team"]
    MTG["Meeting Notes"]

    OBS["Obsidian"]
    MEM["Memory"]
    SKL["Skills"]
    MAIL["Emails"]
    PROD["Prod DB (Read-Only)"]

    OC["OpenClaw Orchestrator<br/>Context + Routing + Prompting"]

    C1["Codex Agent A"]
    C2["Codex Agent B"]
    C3["Codex Agent C"]
    CC["ClaudeCode Agent"]
    OP["OpenCode Agent"]
    GM["Gemini CLI Agent"]

    PIPE["GitHub CI/CD + Gates<br/>lint -> typecheck -> tests -> e2e -> AI reviews"]
    MON["Deterministic Monitor<br/>tmux + PR + CI + reviews + screenshot gate"]
    DEC{"DoD Passed?"}
    RETRY["Evidence-Driven Retry<br/>context injection + scoped fixes"]
    READY["ready_to_merge"]
    NOTIFY["OpenClaw Notify<br/>Discord / Telegram"]

    SEN --> OC
    SUP --> OC
    ME --> OC
    MTG --> OC

    OC --> OBS
    OC --> MEM
    OC --> SKL
    OC --> MAIL
    OC --> PROD

    OC --> C1
    OC --> C2
    OC --> C3
    OC --> CC
    OC --> OP
    OC --> GM

    C1 --> PIPE
    C2 --> PIPE
    C3 --> PIPE
    CC --> PIPE
    OP --> PIPE
    GM --> PIPE

    PIPE --> MON
    MON --> DEC
    DEC -- "No" --> RETRY
    RETRY --> OC
    DEC -- "Yes" --> READY
    READY --> NOTIFY
    NOTIFY --> ME

    TICK["cron every 10 minutes<br/>swarm monitor tick"] --> MON

    classDef source fill:#1b1430,stroke:#b67cff,color:#f2e8ff,stroke-width:1.8px;
    classDef human fill:#10201a,stroke:#2dd4bf,color:#d7fff3,stroke-width:1.8px;
    classDef memory fill:#06202a,stroke:#22d3ee,color:#dbfbff,stroke-width:1.6px;
    classDef core fill:#2b1015,stroke:#fb7185,color:#ffe4ea,stroke-width:2.2px;
    classDef agent fill:#0c1c33,stroke:#60a5fa,color:#e3f0ff,stroke-width:1.6px;
    classDef pipeline fill:#2f2416,stroke:#f59e0b,color:#fff2df,stroke-width:2px;
    classDef decision fill:#1f1f1f,stroke:#e5e7eb,color:#f8fafc,stroke-width:1.8px;
    classDef success fill:#0f2a16,stroke:#4ade80,color:#e7ffe8,stroke-width:1.8px;
    classDef monitor fill:#27213b,stroke:#c084fc,color:#f1e8ff,stroke-width:1.6px;

    class SEN,SUP,MTG source;
    class ME human;
    class OBS,MEM,SKL,MAIL,PROD memory;
    class OC core;
    class C1,C2,C3,CC,OP,GM agent;
    class PIPE pipeline;
    class DEC decision;
    class READY,NOTIFY success;
    class MON,RETRY,TICK monitor;
```

---

## Driver Matrix

| Driver | Primary Use | Default Model | Notes |
|---|---|---|---|
| `codex` | backend, complex reasoning | inherit Codex default | default driver |
| `claudecode` | frontend, rapid iteration | inherit Claude Code default | `claude` alias supported |
| `opencode` | OpenCode flows | inherit OpenCode default | set `model` only when you want explicit override |
| `gemini-cli` | Gemini CLI execution | inherit Gemini CLI default | auth required |

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
- recommended events: `ready_to_merge`, `merged`
- optional noisy events (`abandoned`, `failed`, `ci_failed`, `review_changes_requested`) require `allow_failure_events = true`

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
- `reference/` architecture, constitution, usage
- `install.sh` one-command agent installer

---

## Reading Order

1. `reference/agent-swarm-usage.md`
2. `reference/agent-swarm-architecture.md`
3. `reference/agent-swarm-constitution-v1.md`
