# Skills-First Complete Restructure

Status: Approved
Date: 2026-03-19
Scope: Full architectural restructure of openclaw-swarm-core

## Problem

Skills and execution scripts are two disconnected islands. Skills contain only
markdown guidance for AI agents. Executable scripts live in `swarm-core/templates/`
and get seeded into per-project `.openclaw/` directories. The binding between them
is implicit — an agent reads a skill's text, then independently decides to invoke
swarm CLI commands. This coupling is fragile, undiscoverable, and untestable.

## Decision Summary

| Decision                  | Outcome                                                  |
|---------------------------|----------------------------------------------------------|
| swarm-core                | Delete. Capabilities rewritten and distributed to skills |
| /coding                   | Pure text skill. Complete ACP operations guide            |
| /delivery + /swarm        | Merge into single `/delivery` skill                      |
| Driver implementation     | Rewrite as shell. One `case` statement replaces 4 Python driver classes + base class + registry |
| Seed mechanism            | Remove. `delivery` CLI operates target repos directly    |
| Naming                    | `coding/` and `delivery/`. Directories match slash commands |
| Language                  | All shell. Zero Python dependency                        |
| Configuration             | Replace `project.toml` with shell-friendly `.env` format |

## Runtime Dependencies

The delivery CLI requires these tools on PATH:

- `bash` (4.0+, for associative arrays)
- `sqlite3`
- `git`
- `jq`
- `gh` (GitHub CLI, for PR operations)
- `tmux` (session isolation)
- `openclaw` (notifications via `openclaw message send`)

## Target Directory Structure

```
openclaw-swarm-core/
├── skills/
│   ├── coding/                          # /coding — pure text skill
│   │   ├── SKILL.md
│   │   ├── agents/
│   │   │   └── openai.yaml
│   │   └── references/
│   │       ├── harness-selection.md
│   │       ├── acp-guide.md
│   │       └── harness-capabilities.md
│   │
│   └── delivery/                        # /delivery — self-contained execution skill
│       ├── SKILL.md
│       ├── agents/
│       │   └── openai.yaml
│       ├── references/
│       │   ├── state-machine.md
│       │   ├── driver-matrix.md
│       │   ├── dod-gates.md
│       │   ├── retry-policy.md
│       │   └── notification.md
│       └── bin/
│           ├── delivery                 # Main entrypoint (shell dispatcher)
│           ├── lib/
│           │   ├── common.sh            # Path resolution, die(), date formatting
│           │   ├── state.sh             # SQLite state machine operations
│           │   ├── drivers.sh           # Driver selection + command building
│           │   ├── git-ops.sh           # Worktree, branch, PR operations
│           │   ├── monitor.sh           # Inspection loop + evidence-driven retry
│           │   └── notify.sh            # openclaw message send wrapper
│           └── schema.sql               # CREATE TABLE statements
│
├── reference/                           # Maintainer docs (retained as-is)
│   ├── agent-swarm-north-star-v1.md
│   ├── agent-swarm-architecture.md
│   └── agent-swarm-constitution-v1.md
│
├── .archive/                            # Legacy snapshots
│   └── swarm-core-legacy/               # Pre-restructure swarm-core snapshot
│
├── install.sh                           # Install skills + link delivery CLI
├── README.md
├── CHANGELOG.md
└── AGENTS.md
```

## Before / After Architecture

```
BEFORE:
┌──────────────────────────────────────────────────────┐
│ skills/                                              │
│  ├── openclaw-direct-coding/      (pure markdown)    │
│  ├── openclaw-advanced-delivery/  (pure markdown)    │
│  └── swarm-task-control/          (pure markdown)    │
│                                                      │
│ swarm-core/                                          │
│  ├── swarm_cli.py    (~2500-line Python engine)      │
│  ├── drivers/        (4 Python driver classes + base)│
│  └── templates/      (shell templates, seed system)  │
│                                                      │
│ Binding: agent reads text → improvises CLI calls     │
└──────────────────────────────────────────────────────┘

AFTER:
┌──────────────────────────────────────────────────────┐
│ skills/                                              │
│  ├── coding/                                         │
│  │    ├── SKILL.md           (full ACP guide)        │
│  │    └── references/        (harness + ACP docs)    │
│  │                                                   │
│  └── delivery/                                       │
│       ├── SKILL.md           (requires: delivery)    │
│       ├── references/        (state + gate + retry)  │
│       └── bin/               (shell execution engine)│
│            ├── delivery      (CLI entrypoint)        │
│            └── lib/          (shell modules)         │
│                                                      │
│ Binding: SKILL.md requires.bins → delivery CLI       │
└──────────────────────────────────────────────────────┘
```

## /coding Skill Design

### Purpose

Pure text skill. Tells the agent what coding harnesses exist, what each can do,
and how to operate them through ACP. No executable scripts.

### SKILL.md Frontmatter

```yaml
---
name: coding
description: "Direct coding through ACP-connected coding harnesses. Use when the task is synchronous, conversational, and does not need PR/gate/retry orchestration."
user-invocable: true
argument-hint: "[task and optional harness]"
metadata: {"openclaw":{"primaryEnv":"OPENCLAW_GATEWAY_TOKEN"}}
---
```

### SKILL.md Body

- When to use `/coding` vs when to escalate to `/delivery`
- Require agent to confirm harness selection before executing
- Report concrete results after execution

### references/

| File                     | Content                                              |
|--------------------------|------------------------------------------------------|
| harness-selection.md     | Four harness positions + recommendation rules        |
| acp-guide.md             | Full ACP operations: bridge model, session routing, acpx usage, flags, env vars, session key patterns |
| harness-capabilities.md  | Per-harness capability boundaries: modes, model override, sandbox, redirect support |

## /delivery Skill Design

### Purpose

Self-contained execution skill. Merges original `/delivery` (spawn tasks) and
`/swarm` (control tasks) into a single product surface. Owns the complete
delivery lifecycle: spawn, monitor, status, redirect, kill, cleanup.

### SKILL.md Frontmatter

```yaml
---
name: delivery
description: "Tracked delivery through Swarm runtime. Spawn tasks, monitor progress, redirect, inspect status, kill, and cleanup. Converges toward PR-backed merge-ready output."
user-invocable: true
argument-hint: "[spawn <task> | status | redirect <id> <msg> | monitor | kill <id> | cleanup]"
metadata: {"openclaw":{"requires":{"bins":["delivery"]}}}
---
```

### SKILL.md Body

- When to enter delivery mode (trigger rules from original delivery-trigger-rules.md)
- Full command cheatsheet (`delivery spawn/status/redirect/monitor/kill/cleanup/init`)
- State machine overview (agent needs to understand states for user communication)
- No separate `/swarm` — all control operations live here

### references/

| File               | Content                                              |
|--------------------|------------------------------------------------------|
| state-machine.md   | State definitions, transitions, terminal states, retry conditions |
| driver-matrix.md   | Four driver positions + auto selection logic          |
| dod-gates.md       | 7 Definition of Done gates                           |
| retry-policy.md    | Evidence-driven retry strategy                       |
| notification.md    | OpenClaw notification config and routing              |

## delivery CLI Design

### Command Surface

```bash
delivery spawn   --repo <path> --task-id <id> --driver <auto|codex|claudecode|claude|opencode|gemini-cli> --prompt "..." [--prompt-file <path>] [--source-session-key <key>] [--notify-channel <ch>] [--notify-target <target>] [--notify-account <acct>] [--progress-every <min>] [--no-progress]
delivery status  --repo <path> [--format json|text] [--task-id <id>]
delivery redirect --repo <path> --task-id <id> --message "..."
delivery monitor --repo <path>
delivery kill    --repo <path> --task-id <id>
delivery cleanup --repo <path>
delivery init    --repo <path>
```

Notes:
- `--prompt` and `--prompt-file` are mutually exclusive; error if both given
- `--driver claude` is an alias for `claudecode`
- `--source-session-key`, `--notify-*` flags control notification routing
- `--progress-every` and `--no-progress` control progress update cadence

### Command Mapping (old → new)

| Old                              | New                  |
|----------------------------------|----------------------|
| `swarm seed --repo`              | `delivery init` (auto-called on first spawn) |
| `swarm task spawn`               | `delivery spawn`     |
| `swarm task redirect`            | `delivery redirect`  |
| `swarm task kill`                | `delivery kill`      |
| `swarm monitor tick`             | `delivery monitor`   |
| `swarm cleanup tick`             | `delivery cleanup`   |
| `swarm status`                   | `delivery status`    |
| `.openclaw/spawn-agent.sh` etc   | Removed. Agent calls `delivery` CLI directly |

### init Behavior

`delivery init --repo <path>` creates only the SQLite database:

```
<repo>/.openclaw/
├── ...              # OpenClaw native structure (untouched)
└── swarm.db         # delivery's sole artifact
```

No executable scripts are seeded into the project. The `.openclaw/` directory
structure is managed by OpenClaw natively; `delivery` only adds `swarm.db`.

`active-tasks.json` is removed. It was a compatibility projection of SQLite
state. With `delivery status --format json`, there is no need for a static
JSON file. Any external consumer should call `delivery status` instead.

### Configuration

The current `project.toml` (TOML format) is replaced by `.openclaw/delivery.conf`
using shell-friendly key=value format:

```bash
# .openclaw/delivery.conf
base_branch=main
default_driver=codex
max_attempts=3

# Per-driver model overrides (empty = inherit CLI default)
model_codex=
model_claudecode=
model_opencode=
model_gemini_cli=

# Per-driver reasoning effort
reasoning_codex=high
reasoning_claudecode=
reasoning_opencode=high
reasoning_gemini_cli=

# Driver enable/disable
driver_codex_enabled=true
driver_claudecode_enabled=true
driver_opencode_enabled=true
driver_gemini_cli_enabled=false

# Notifications
notify_enabled=false
notify_channel=discord
notify_target=
notify_account=
notify_events=ready_to_merge,merged
notify_allow_failure_events=false

# Progress
progress_enabled=true
progress_interval_minutes=5
```

Parsing: `source` the file directly in shell (it is valid bash). Defaults are
hardcoded in `common.sh`; the config file overrides them. If the file does not
exist, all defaults apply.

Environment variables override config file values. Priority: CLI flags > env vars > delivery.conf > hardcoded defaults.

### Main Entrypoint (delivery)

```bash
#!/usr/bin/env bash
set -euo pipefail
RUNTIME_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")" && pwd)"
source "$RUNTIME_DIR/lib/common.sh"

case "${1:-}" in
  spawn)    shift; source "$RUNTIME_DIR/lib/state.sh";    cmd_spawn "$@" ;;
  status)   shift; source "$RUNTIME_DIR/lib/state.sh";    cmd_status "$@" ;;
  redirect) shift; source "$RUNTIME_DIR/lib/state.sh";    cmd_redirect "$@" ;;
  monitor)  shift; source "$RUNTIME_DIR/lib/monitor.sh";  cmd_monitor "$@" ;;
  kill)     shift; source "$RUNTIME_DIR/lib/state.sh";    cmd_kill "$@" ;;
  cleanup)  shift; source "$RUNTIME_DIR/lib/git-ops.sh";  cmd_cleanup "$@" ;;
  init)     shift; source "$RUNTIME_DIR/lib/state.sh";    cmd_init "$@" ;;
  *)        usage ;;
esac
```

`RUNTIME_DIR` resolution via `readlink -f` ensures correct path whether
invoked via symlink (`~/.local/bin/delivery`) or directly from repo
(`skills/delivery/bin/delivery`). Both installed and development modes work.

### lib/ Module Breakdown

**common.sh** — Path resolution, `die()`, date formatting, environment detection,
`quote()` for safe shell escaping. Loads `delivery.conf` with defaults.

**state.sh** — All SQLite operations. Schema initialization via `schema.sql`,
state transitions with validation against allowed transition map, task queries,
JSON output via `jq`. The state transition map is a shell associative array
mirroring the current Python `STATE_TRANSITIONS` dict. All SQLite writes use
transactions (`BEGIN`/`COMMIT`/`ROLLBACK`) to prevent partial state on failure.

**drivers.sh** — Two functions replacing four Python classes + base class + registry:

```bash
check_driver_available() {
  case "$1" in
    codex)      command -v codex >/dev/null ;;
    claudecode) command -v claude >/dev/null ;;
    opencode)   command -v opencode >/dev/null ;;
    gemini-cli) command -v gemini >/dev/null ;;
  esac
}

build_driver_command() {
  local driver="$1" prompt="$2" model="$3" reasoning="$4"
  local model_arg=""
  [[ -n "$model" ]] && model_arg="--model $(quote "$model")"
  case "$driver" in
    codex)
      echo "codex exec $model_arg -c $(quote "model_reasoning_effort=$reasoning") --dangerously-bypass-approvals-and-sandbox $(quote "$prompt")" ;;
    claudecode)
      echo "claude $model_arg --dangerously-skip-permissions -p $(quote "$prompt")" ;;
    opencode)
      echo "opencode run $model_arg --variant $(quote "${reasoning:-high}") $(quote "$prompt")" ;;
    gemini-cli)
      echo "gemini $model_arg --approval-mode yolo --prompt $(quote "$prompt")" ;;
  esac
}
```

Auto driver selection (`--driver auto`): check if prompt mentions frontend
keywords (`frontend`, `ui`, `css`, `tailwind`, `component`, `layout`, `style`);
if so and `claudecode` is available, use `claudecode`. Otherwise fall through
priority: `codex` > `claudecode` > `opencode` > `gemini-cli`, first available.

Model normalization per driver (must be preserved in shell rewrite):
- `codex`, `claudecode`, `gemini-cli`: strip provider prefix (`openai/gpt-5` → `gpt-5`)
- `opencode`: add provider prefix if missing (`gpt-5` → `default/gpt-5`);
  special case `openai/gpt-5.3-codex` → `default/gpt-5.3-codex`

**git-ops.sh** — Worktree creation/deletion, branch management, PR creation and
status checking via `gh` CLI, cleanup of terminated task artifacts (worktree
removal, tmux session kill, branch cleanup).

**monitor.sh** — The deterministic inspection loop. Checks tmux session alive
status, git/PR state, CI status, review state. Drives state transitions.
Implements evidence-driven retry: captures failure evidence (CI output, review
deltas, missing artifacts), injects into retry prompt, narrows scope, increments
attempt counter, stops at max attempts and reports to human.

**notify.sh** — Wraps `openclaw message send`. Handles session key routing,
channel detection, event filtering. Respects `notify_events` config and
`notify_allow_failure_events` flag.

**schema.sql** — CREATE TABLE statements for the full task data model:
- `tasks` — Core task state and metadata
- `task_attempts` — Per-attempt records with evidence
- `task_checks` — CI and review check results
- `task_artifacts` — PR URLs, screenshot paths, branch names
- `task_events` — State transition audit log
- `task_notifications` — Notification delivery records
- `task_progress` — Progress update history

Plus indexes for common query patterns. Schema is identical to the current
Python-created schema to ensure existing `swarm.db` files are compatible.

### State Machine

Allowed states (unchanged from current):

```
                              ┌─────────────────────────────────────┐
                              │                                     ▼
queued ──► running ──► pr_created ──► ci_passed ──► ready_to_merge ──► merged
               │           │    │         │    │          │
               │           │    │         │    └► ci_failed (regression)
               │           │    │         └► review_changes_requested
               │           │    └► ci_failed                │
               │           │    └► review_changes_requested │
               │           └► ready_to_merge ──────────────►│
               │           └► merged (fast path)            │
               ▼                                            │
           failed ──► running (retry with evidence)         │
               │                                            │
               └──────────────► abandoned ◄─────────────────┘
                                (from any non-terminal state)
```

Full transition map (authoritative source: `state-machine.md`):
- `queued` → {running, abandoned}
- `running` → {pr_created, failed, abandoned}
- `pr_created` → {ci_failed, ci_passed, review_changes_requested, ready_to_merge, merged, abandoned}
- `ci_failed` → {running, abandoned}
- `ci_passed` → {review_changes_requested, ready_to_merge, merged, ci_failed, abandoned}
- `review_changes_requested` → {running, ready_to_merge, abandoned}
- `ready_to_merge` → {merged, review_changes_requested, ci_failed, abandoned}
- `failed` → {running, abandoned}
- `merged` → {} (terminal)
- `abandoned` → {} (terminal)

Retry conditions:
- Retry only from `failed`, `ci_failed`, `review_changes_requested`
- Retries are evidence-driven, never blind reruns
- Monitor loop runs every 10 minutes (cron) or on-demand via `delivery monitor`

### Driver Matrix (unchanged)

| Driver       | Primary Use                    | Default Model            |
|-------------|--------------------------------|--------------------------|
| `codex`      | Backend, debugging, reasoning  | Inherit Codex default    |
| `claudecode` | Frontend, rapid iteration      | Inherit Claude default   |
| `opencode`   | OpenCode-native flows          | Inherit OpenCode default |
| `gemini-cli` | Gemini CLI execution           | Inherit Gemini default   |

Default driver: `codex`. `claude` is an alias for `claudecode`.

### Error Handling

- All SQLite writes wrapped in transactions. On failure: ROLLBACK, report error, exit non-zero.
- Partial state cleanup: if worktree creation succeeds but spawn fails, cleanup removes the worktree.
  If tmux session creation succeeds but driver launch fails, session is killed.
- Driver errors are captured to stderr, stored in `task_attempts` as evidence, and used for retry prompt injection.
- All errors go to stderr. Exit codes: 0 success, 1 user error, 2 system error.

## install.sh Behavior

```bash
./install.sh [--yes] [--link-bin]
```

Two actions:

1. **Install skills** — Copy `skills/coding/` and `skills/delivery/` to
   `~/.openclaw/skills/`
2. **Link CLI** — Symlink `skills/delivery/bin/delivery` to `~/.local/bin/delivery`

No `swarm seed`. No per-project script generation.

## Existing Project Migration

Projects with old seeded `.openclaw/` scripts need a one-time cleanup:

**Old seeded scripts (safe to remove):**
- `.openclaw/spawn-agent.sh`
- `.openclaw/redirect-agent.sh`
- `.openclaw/kill-agent.sh`
- `.openclaw/check-agents.sh`
- `.openclaw/cleanup.sh`
- `.openclaw/status.sh`
- `.openclaw/run-agent.sh`
- `.openclaw/setup.sh`
- `.openclaw/AGENTS.md`

**Keep untouched:**
- `.openclaw/swarm.db` — schema is identical, fully compatible
- `.openclaw/logs/` — OpenClaw native directory
- `.openclaw/project.toml` — will be ignored; replaced by `delivery.conf` when created

**active-tasks.json:** Remove. No longer generated or consumed.

`delivery` CLI handles old projects gracefully:
- Old seeded scripts are inert (they call `swarm` binary which no longer exists at the old path)
- `delivery` ignores their presence; they cause no conflict
- A `delivery cleanup --legacy` command removes old seeded scripts from `.openclaw/`

**SQLite compatibility:** The schema is identical. Existing `swarm.db` files work
without migration. If schema evolves in future versions, `delivery init` will
run `ALTER TABLE` migrations with version tracking.

## Scheduling

Monitor cron is per-project, set up by the operator or OpenClaw agent:

```bash
# Example: monitor every 10 minutes for a specific repo
*/10 * * * * delivery monitor --repo /path/to/repo
```

`install.sh` does not create cron entries. Cron setup is documented in
`references/notification.md` and is the operator's responsibility.

## Deletions and Archival

| Action    | Target                                |
|-----------|---------------------------------------|
| Delete    | `swarm-core/` (entire directory)      |
| Delete    | `skills/openclaw-direct-coding/`      |
| Delete    | `skills/openclaw-advanced-delivery/`  |
| Delete    | `skills/swarm-task-control/`          |
| Archive   | `swarm-core/` snapshot → `.archive/swarm-core-legacy/` |

## Migration Path

1. Archive `swarm-core/` to `.archive/swarm-core-legacy/`
2. Delete old skill directories
3. Create new `skills/coding/` with SKILL.md + references
4. Create new `skills/delivery/` with SKILL.md + references + bin/
5. Rewrite `swarm_cli.py` logic as shell modules in `delivery/bin/lib/`
6. Rewrite `install.sh` for new layout
7. Update `README.md`, `AGENTS.md`, `reference/` docs
8. Update `CHANGELOG.md`

## Testing Strategy

Shell rewrite is validated by integration tests:

- `bats` (Bash Automated Testing System) for unit-level shell function tests
- Each lib/ module gets a corresponding test file
- Integration tests: spawn a task against a test repo, verify state transitions,
  verify worktree/branch creation, verify cleanup
- Existing `swarm.db` compatibility test: run new CLI against an old database
- Driver command construction tests: verify exact CLI strings for each driver

## What This Design Does NOT Change

- State machine states and transitions (proven, keep as-is)
- Definition of Done gates (keep all 7)
- Driver CLI invocation arguments (keep exact same commands)
- SQLite as single source of truth (keep)
- SQLite schema (keep identical for backward compatibility)
- Notification via `openclaw message send` (keep)
- `reference/` maintainer docs (keep, update for new structure)
- `.openclaw/swarm.db` per-project location (keep)

## Success Criteria

1. `delivery spawn/status/redirect/monitor/kill/cleanup` work identically to current `swarm` CLI
2. Zero Python dependency — entire system runs on bash + sqlite3 + git + jq + gh + tmux + openclaw
3. `/coding` skill provides complete ACP operations guide
4. `/delivery` skill is self-contained: SKILL.md + references + bin/
5. `install.sh` installs both skills and links the CLI
6. Old `swarm-core/` fully archived, no orphan references
7. Existing `swarm.db` files work without migration
8. `bats` integration tests pass for all CLI commands
