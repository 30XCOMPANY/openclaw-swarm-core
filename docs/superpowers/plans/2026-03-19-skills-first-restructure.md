# Skills-First Restructure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure openclaw-swarm-core from a disconnected skills+runtime repo into a skills-first system where `/delivery` is a self-contained execution skill and `/coding` is a complete ACP operations guide.

**Architecture:** Delete swarm-core/. Rewrite its ~2500-line Python engine as shell modules living inside `skills/delivery/bin/`. Merge `/delivery` + `/swarm` into one skill. Replace TOML config with sourceable key=value. Remove seed mechanism entirely.

**Tech Stack:** bash 4.0+, sqlite3, git, jq, gh, tmux, openclaw CLI, bats (testing)

**Spec:** `docs/superpowers/specs/2026-03-19-skills-first-restructure-design.md`

---

## File Structure

### New files to create

```
skills/coding/SKILL.md
skills/coding/agents/openai.yaml
skills/coding/references/harness-selection.md
skills/coding/references/acp-guide.md
skills/coding/references/harness-capabilities.md

skills/delivery/SKILL.md
skills/delivery/agents/openai.yaml
skills/delivery/references/state-machine.md
skills/delivery/references/driver-matrix.md
skills/delivery/references/dod-gates.md
skills/delivery/references/retry-policy.md
skills/delivery/references/notification.md
skills/delivery/bin/delivery
skills/delivery/bin/lib/common.sh
skills/delivery/bin/lib/state.sh
skills/delivery/bin/lib/drivers.sh
skills/delivery/bin/lib/git-ops.sh
skills/delivery/bin/lib/monitor.sh
skills/delivery/bin/lib/notify.sh
skills/delivery/bin/schema.sql

tests/test_common.bats
tests/test_state.bats
tests/test_drivers.bats
tests/test_integration.bats
```

### Files to modify

```
install.sh
README.md
AGENTS.md
CHANGELOG.md
reference/agent-swarm-architecture.md
reference/agent-swarm-constitution-v1.md
reference/agent-swarm-north-star-v1.md
reference/AGENTS.md
skills/AGENTS.md
```

### Files/dirs to delete (after archival)

```
swarm-core/                          → archive to .archive/swarm-core-legacy/
skills/openclaw-direct-coding/       → delete
skills/openclaw-advanced-delivery/   → delete
skills/swarm-task-control/           → delete
```

---

### Task 1: Archive and clean old structure

**Files:**
- Move: `swarm-core/` → `.archive/swarm-core-legacy/`
- Delete: `skills/openclaw-direct-coding/`
- Delete: `skills/openclaw-advanced-delivery/`
- Delete: `skills/swarm-task-control/`
- Delete: `skills/AGENTS.md`

- [ ] **Step 1: Archive swarm-core**

```bash
cp -r swarm-core .archive/swarm-core-legacy
rm -rf swarm-core
```

- [ ] **Step 2: Delete old skills**

```bash
rm -rf skills/openclaw-direct-coding
rm -rf skills/openclaw-advanced-delivery
rm -rf skills/swarm-task-control
rm -f skills/AGENTS.md
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "chore: archive swarm-core, delete old skill directories

Prepares for skills-first restructure. swarm-core preserved in
.archive/swarm-core-legacy for reference during rewrite."
```

---

### Task 2: Create /coding skill (pure text)

**Files:**
- Create: `skills/coding/SKILL.md`
- Create: `skills/coding/agents/openai.yaml`
- Create: `skills/coding/references/harness-selection.md`
- Create: `skills/coding/references/acp-guide.md`
- Create: `skills/coding/references/harness-capabilities.md`

- [ ] **Step 1: Create SKILL.md**

Write `skills/coding/SKILL.md` with:
- Frontmatter: name=coding, description about direct coding through ACP harnesses, user-invocable=true, argument-hint, metadata with primaryEnv=OPENCLAW_GATEWAY_TOKEN
- Body: when to use /coding vs /delivery, require harness confirmation, escalation rules
- Reference the ACP doc at https://docs.openclaw.ai/cli/acp for ACP bridge details

Source material for body and escalation rules: `.archive/swarm-core-legacy/` → old `skills/openclaw-direct-coding/SKILL.md` and its `references/direct-coding-escalation.md`

- [ ] **Step 2: Create agents/openai.yaml**

Write `skills/coding/agents/openai.yaml` with interface metadata:
- display_name: "Direct Coding"
- short_description: "Pick a harness and execute directly in the current conversation"
- brand_color: "#1D4ED8"
- default_prompt referencing /coding
- policy.allow_implicit_invocation: true

Source: `.archive/swarm-core-legacy/` → old `skills/openclaw-direct-coding/agents/openai.yaml`

- [ ] **Step 3: Create references/harness-selection.md**

Write `skills/coding/references/harness-selection.md` with:
- Codex: backend, debugging, multi-file reasoning (default)
- Claude Code: frontend, UI, rapid iteration
- OpenCode: when OpenCode flows are preferred
- Gemini CLI: explicit Gemini request only
- Boundary rule: if user wants PR/gates, recommend /delivery

Source: `.archive/swarm-core-legacy/` → old `skills/openclaw-direct-coding/references/harness-selection.md`

- [ ] **Step 4: Create references/acp-guide.md**

Write `skills/coding/references/acp-guide.md` with complete ACP operations:
- What ACP is: Gateway-backed ACP bridge, session routing + prompt delivery
- Session model: agent-scoped keys (agent:main:main), ACP session → Gateway session
- acpx usage: `acpx openclaw` for one-shot and persistent named sessions
- CLI flags: --url, --token, --session, --session-label, --reset-session, --verbose
- Environment variables: OPENCLAW_GATEWAY_TOKEN, OPENCLAW_GATEWAY_PASSWORD
- Supported operations: initialize, newSession, prompt, cancel, listSessions
- Limitations: no per-session MCP servers, no client filesystem/terminal methods

Source: ACP documentation at https://docs.openclaw.ai/cli/acp

- [ ] **Step 5: Create references/harness-capabilities.md**

Write `skills/coding/references/harness-capabilities.md` with per-harness details:
- Codex: exec mode, model override via --model, reasoning effort via -c, sandbox bypass
- Claude Code: prompt mode via -p, model override, permissions skip, redirect support
- OpenCode: run mode, variant selection, model override
- Gemini CLI: prompt mode, approval-mode yolo, model override, auth requirements

Source: `.archive/swarm-core-legacy/` → driver files in `swarm-core/drivers/`

- [ ] **Step 6: Commit**

```bash
git add skills/coding/
git commit -m "feat: create /coding skill with ACP operations guide

Pure text skill. Covers harness selection, complete ACP bridge
operations, and per-harness capability boundaries."
```

---

### Task 3: Create delivery CLI shell foundation

**Files:**
- Create: `skills/delivery/bin/delivery`
- Create: `skills/delivery/bin/lib/common.sh`
- Create: `skills/delivery/bin/schema.sql`

- [ ] **Step 1: Create schema.sql**

Write `skills/delivery/bin/schema.sql` — copy the exact schema from `.archive/swarm-core-legacy/swarm-core/swarm_cli.py` function `init_schema()` (lines 678-802). Must be byte-identical in table/column definitions for backward compatibility. Include all 7 tables and 7 indexes.

Tables: tasks, task_attempts, task_checks, task_artifacts, task_events, task_notifications, task_progress_notifications

- [ ] **Step 2: Create common.sh**

Write `skills/delivery/bin/lib/common.sh` with:

```bash
#!/usr/bin/env bash
# Common utilities for delivery CLI

set -euo pipefail

# --- defaults ---
DEFAULT_BASE_BRANCH=main
DEFAULT_DRIVER=codex
DEFAULT_MAX_ATTEMPTS=3
DEFAULT_NOTIFY_ENABLED=false
DEFAULT_NOTIFY_CHANNEL=discord
DEFAULT_NOTIFY_EVENTS="ready_to_merge,merged"
DEFAULT_NOTIFY_ALLOW_FAILURE=false
DEFAULT_PROGRESS_ENABLED=true
DEFAULT_PROGRESS_INTERVAL=5

# --- state constants ---
STATUS_QUEUED=queued
STATUS_RUNNING=running
STATUS_PR_CREATED=pr_created
STATUS_CI_FAILED=ci_failed
STATUS_CI_PASSED=ci_passed
STATUS_REVIEW_CHANGES=review_changes_requested
STATUS_READY=ready_to_merge
STATUS_MERGED=merged
STATUS_FAILED=failed
STATUS_ABANDONED=abandoned

# --- functions ---
die() { echo "ERROR: $1" >&2; exit "${2:-1}"; }

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

quote() { printf '%q' "$1"; }

ensure_repo() {
  local path
  path="$(cd "$1" && pwd)" 2>/dev/null || die "Repo path not found: $1"
  [[ -d "$path/.git" ]] || die "Not a git repository: $path"
  echo "$path"
}

db_path() { echo "$1/.openclaw/swarm.db"; }

load_config() {
  local repo_path="$1"
  local conf="$repo_path/.openclaw/delivery.conf"

  # Set defaults
  base_branch="$DEFAULT_BASE_BRANCH"
  default_driver="$DEFAULT_DRIVER"
  max_attempts="$DEFAULT_MAX_ATTEMPTS"
  # ... (all defaults from spec)

  # Source config if exists (overrides defaults)
  [[ -f "$conf" ]] && source "$conf"
}

ensure_db() {
  local repo_path="$1"
  local db
  db="$(db_path "$repo_path")"
  if [[ ! -f "$db" ]]; then
    mkdir -p "$(dirname "$db")"
    sqlite3 "$db" < "$RUNTIME_DIR/schema.sql"
    sqlite3 "$db" "PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;"
  fi
}

sql() {
  local db="$1"; shift
  sqlite3 -separator $'\t' "$db" "$@"
}

sql_json() {
  local db="$1"; shift
  sqlite3 -json "$db" "$@"
}
```

- [ ] **Step 3: Create delivery main entrypoint**

Write `skills/delivery/bin/delivery`:

```bash
#!/usr/bin/env bash
set -euo pipefail
RUNTIME_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")" && pwd)"
source "$RUNTIME_DIR/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: delivery <command> [options]

Commands:
  spawn      Create and launch a delivery task
  status     Show task status
  redirect   Send correction to a running task
  monitor    Run deterministic inspection and retry loop
  kill       Terminate a task
  cleanup    Clean up terminated task artifacts
  init       Initialize delivery database for a repo

Run 'delivery <command> --help' for command-specific options.
EOF
}

case "${1:-}" in
  spawn)    shift; source "$RUNTIME_DIR/lib/state.sh";    cmd_spawn "$@" ;;
  status)   shift; source "$RUNTIME_DIR/lib/state.sh";    cmd_status "$@" ;;
  redirect) shift; source "$RUNTIME_DIR/lib/state.sh";    cmd_redirect "$@" ;;
  monitor)  shift; source "$RUNTIME_DIR/lib/monitor.sh";  cmd_monitor "$@" ;;
  kill)     shift; source "$RUNTIME_DIR/lib/state.sh";    cmd_kill "$@" ;;
  cleanup)  shift; source "$RUNTIME_DIR/lib/git-ops.sh";  cmd_cleanup "$@" ;;
  init)     shift; source "$RUNTIME_DIR/lib/state.sh";    cmd_init "$@" ;;
  -h|--help) usage ;;
  *)        usage; exit 1 ;;
esac
```

```bash
chmod +x skills/delivery/bin/delivery
```

- [ ] **Step 4: Verify foundation loads**

```bash
skills/delivery/bin/delivery --help
```

Expected: usage text printed, exit 0

- [ ] **Step 5: Commit**

```bash
git add skills/delivery/bin/
git commit -m "feat: delivery CLI foundation — entrypoint, common.sh, schema.sql

Shell-based delivery runtime. Schema identical to Python version
for backward compatibility with existing swarm.db files."
```

---

### Task 4: Implement drivers.sh

**Files:**
- Create: `skills/delivery/bin/lib/drivers.sh`

- [ ] **Step 1: Write drivers.sh**

Write `skills/delivery/bin/lib/drivers.sh` with three functions:

1. `check_driver_available()` — case statement checking `command -v` for each driver binary
2. `build_driver_command()` — case statement building CLI command string per driver. Must match exact arguments from `.archive/swarm-core-legacy/swarm-core/drivers/*.py`
3. `normalize_model()` — per-driver model string normalization:
   - codex/claudecode/gemini-cli: strip provider prefix (split on `/`, take last part)
   - opencode: add `default/` prefix if no `/` present; special case `openai/gpt-5.3-codex` → `default/gpt-5.3-codex`
4. `resolve_driver()` — auto-selection logic:
   - If `--driver auto`: check prompt for frontend keywords → use claudecode if available
   - Fallthrough priority: codex > claudecode > opencode > gemini-cli (first available + enabled)
   - Alias `claude` → `claudecode`

Source: `.archive/swarm-core-legacy/swarm-core/drivers/*.py` and `swarm_cli.py` `resolve_driver()` function

- [ ] **Step 2: Commit**

```bash
git add skills/delivery/bin/lib/drivers.sh
git commit -m "feat: drivers.sh — driver selection, command building, model normalization

Replaces 4 Python driver classes with shell case branches.
Preserves exact CLI arguments and model normalization rules."
```

---

### Task 5: Implement state.sh (SQLite state machine + commands)

**Files:**
- Create: `skills/delivery/bin/lib/state.sh`

This is the largest module. It implements: state transition validation, cmd_init, cmd_spawn, cmd_status, cmd_redirect, cmd_kill.

- [ ] **Step 1: Write state transition map**

Declare the state transition map as a shell associative array at the top of `state.sh`:

```bash
declare -A TRANSITIONS
TRANSITIONS[queued]="running abandoned"
TRANSITIONS[running]="pr_created failed abandoned"
TRANSITIONS[pr_created]="ci_failed ci_passed review_changes_requested ready_to_merge merged abandoned"
TRANSITIONS[ci_failed]="running abandoned"
TRANSITIONS[ci_passed]="review_changes_requested ready_to_merge merged ci_failed abandoned"
TRANSITIONS[review_changes_requested]="running ready_to_merge abandoned"
TRANSITIONS[ready_to_merge]="merged review_changes_requested ci_failed abandoned"
TRANSITIONS[failed]="running abandoned"
TRANSITIONS[merged]=""
TRANSITIONS[abandoned]=""
```

Write `check_transition()` function that validates old→new against the map.

- [ ] **Step 2: Write cmd_init**

`cmd_init()` — parse `--repo` flag, call `ensure_repo`, call `ensure_db`. Print confirmation.

- [ ] **Step 3: Write cmd_spawn**

`cmd_spawn()` — the core spawn logic. Port from `swarm_cli.py` `cmd_task_spawn()`:
1. Parse all flags: --repo, --task-id, --driver, --prompt, --prompt-file, --source-session-key, --notify-*, --progress-*
2. Validate: prompt xor prompt-file, repo exists
3. Call `ensure_db`, `load_config`
4. Resolve driver (call `resolve_driver` from drivers.sh)
5. Normalize model (call `normalize_model` from drivers.sh)
6. Detect base branch
7. Create worktree: `git worktree add`
8. Create tmux session
9. Build driver command, launch in tmux
10. Insert task row into SQLite (BEGIN/COMMIT)
11. Insert task_checks row
12. Log task_events entry
13. Print task summary

Source: `.archive/swarm-core-legacy/swarm-core/swarm_cli.py` `cmd_task_spawn()` (read the full function)

- [ ] **Step 4: Write cmd_status**

`cmd_status()` — parse --repo, --format, --task-id. Query SQLite. Output as text table or JSON via jq.

Source: `.archive/swarm-core-legacy/swarm-core/swarm_cli.py` `cmd_status()`

- [ ] **Step 5: Write cmd_redirect**

`cmd_redirect()` — parse --repo, --task-id, --message. Verify task is running. Send keys to tmux session. Log event.

Source: `.archive/swarm-core-legacy/swarm-core/swarm_cli.py` `cmd_task_redirect()`

- [ ] **Step 6: Write cmd_kill**

`cmd_kill()` — parse --repo, --task-id. Verify task is non-terminal. Kill tmux session. Transition to abandoned. Log event.

Source: `.archive/swarm-core-legacy/swarm-core/swarm_cli.py` `cmd_task_kill()`

- [ ] **Step 7: Commit**

```bash
git add skills/delivery/bin/lib/state.sh
git commit -m "feat: state.sh — SQLite state machine, spawn, status, redirect, kill

Core delivery commands. State transitions validated against
associative array map. All SQLite writes use transactions."
```

---

### Task 6: Implement git-ops.sh

**Files:**
- Create: `skills/delivery/bin/lib/git-ops.sh`

- [ ] **Step 1: Write git-ops.sh**

Functions to implement:
1. `detect_base_branch()` — check `git symbolic-ref refs/remotes/origin/HEAD`, fallback to "main"
2. `create_worktree()` — `git worktree add` with branch naming convention
3. `remove_worktree()` — `git worktree remove --force`
4. `create_pr()` — `gh pr create` with title, body, base branch
5. `check_pr_status()` — `gh pr view --json` for mergeable, CI, reviews
6. `check_ci_status()` — parse PR checks from `gh pr checks`
7. `check_review_status()` — parse review state from `gh pr view --json reviews`
8. `detect_ui_change()` — check diff for UI file extensions (.tsx, .jsx, .css, .scss, .html, .vue, .svelte) and path hints (/client/, /web/, /frontend/, /ui/, /components/, /pages/, /styles/)
9. `cmd_cleanup()` — iterate terminal tasks, remove worktrees, kill tmux sessions, clean branches, update cleaned_at
10. `cmd_cleanup_legacy()` — remove old seeded scripts from .openclaw/ (for `delivery cleanup --legacy`)

Source: `.archive/swarm-core-legacy/swarm-core/swarm_cli.py` — scattered git/PR operations and `cmd_cleanup_tick()`

- [ ] **Step 2: Commit**

```bash
git add skills/delivery/bin/lib/git-ops.sh
git commit -m "feat: git-ops.sh — worktree, branch, PR, CI check, cleanup

Covers full git lifecycle: create/remove worktrees, PR creation
via gh CLI, CI/review status checking, artifact cleanup."
```

---

### Task 7: Implement notify.sh

**Files:**
- Create: `skills/delivery/bin/lib/notify.sh`

- [ ] **Step 1: Write notify.sh**

Functions to implement:
1. `should_send_notification()` — check config enabled, provider=openclaw, not temp repo, route has channel+target, status in allowed events
2. `notification_sent()` — check task_notifications table for dedup
3. `build_notification_message()` — format [swarm] repo_name, task/status/driver/model/attempt, branch, PR URL, error note. Truncate to 1800 chars.
4. `dispatch_openclaw_notification()` — run `openclaw message send --channel --target --message --json` with optional --account, --silent, --dry-run. Capture result. Return success/failure.
5. `send_status_notification()` — orchestrate: check should_send, check dedup, build message, dispatch, record in task_notifications, log event
6. `should_send_progress_notification()` — check interval elapsed since last progress notification
7. `send_progress_notification()` — similar to status but for progress updates, records in task_progress_notifications
8. `resolve_task_notify_route()` — resolve channel/target/account from task row + config fallbacks
9. `parse_discord_route_from_session_key()` — parse `agent:<id>:discord:channel:<channel_id>` pattern
10. `discover_recent_discord_session_key()` — scan openclaw commands.log for recent discord sessions (within 900 seconds)

Source: `.archive/swarm-core-legacy/swarm-core/swarm_cli.py` — notification functions (lines ~897-1200)

- [ ] **Step 2: Commit**

```bash
git add skills/delivery/bin/lib/notify.sh
git commit -m "feat: notify.sh — OpenClaw notification routing and dispatch

Status notifications, progress updates, session key routing,
Discord channel discovery, deduplication, event logging."
```

---

### Task 8: Implement monitor.sh

**Files:**
- Create: `skills/delivery/bin/lib/monitor.sh`

- [ ] **Step 1: Write monitor.sh**

`cmd_monitor()` — the deterministic inspection loop. Port from `swarm_cli.py` `cmd_monitor_tick()`:

1. Parse --repo
2. Load config, connect DB
3. Query all active (non-terminal, non-cleaned) tasks
4. For each task:
   a. Check tmux session alive (`tmux has-session -t`)
   b. If running + tmux dead → check if branch has commits → transition to pr_created or failed
   c. If pr_created → check PR status (CI, reviews, mergeable) → transition accordingly
   d. If ci_failed/failed/review_changes_requested → check retry eligibility (attempt < max) → build retry prompt with evidence → spawn retry in new tmux session
   e. If ci_passed → check remaining gates → transition to ready_to_merge if all pass
   f. If ready_to_merge → check for regressions (new CI failure, new review request)
   g. Send notifications for state transitions
   h. Send progress notifications if interval elapsed
5. Commit DB changes

Evidence-driven retry specifics:
- Capture CI output: `gh pr checks --json`
- Capture review comments: `gh pr view --json reviews`
- Inject evidence into retry prompt prefix
- Increment attempt_count
- Record in task_attempts

Source: `.archive/swarm-core-legacy/swarm-core/swarm_cli.py` `cmd_monitor_tick()` (read the full function, it's ~200 lines)

- [ ] **Step 2: Commit**

```bash
git add skills/delivery/bin/lib/monitor.sh
git commit -m "feat: monitor.sh — deterministic inspection loop with evidence-driven retry

Checks tmux, git, PR, CI, review states. Drives transitions.
Retries with captured evidence, never blind reruns."
```

---

### Task 9: Create /delivery skill docs

**Files:**
- Create: `skills/delivery/SKILL.md`
- Create: `skills/delivery/agents/openai.yaml`
- Create: `skills/delivery/references/state-machine.md`
- Create: `skills/delivery/references/driver-matrix.md`
- Create: `skills/delivery/references/dod-gates.md`
- Create: `skills/delivery/references/retry-policy.md`
- Create: `skills/delivery/references/notification.md`

- [ ] **Step 1: Create SKILL.md**

Write `skills/delivery/SKILL.md` with:
- Frontmatter per spec: name=delivery, requires.bins=["delivery"]
- Body: when to enter delivery mode (from old delivery-trigger-rules.md), full command cheatsheet, state machine overview, escalation from /coding
- Merges content from old `/delivery` and `/swarm` skills

Source:
- `.archive/swarm-core-legacy/` → old `skills/openclaw-advanced-delivery/SKILL.md`
- `.archive/swarm-core-legacy/` → old `skills/swarm-task-control/SKILL.md`

- [ ] **Step 2: Create agents/openai.yaml**

Write `skills/delivery/agents/openai.yaml`:
- display_name: "Delivery"
- short_description: "Tracked delivery with PR gates, retries, and cleanup"
- brand_color: "#B45309"
- default_prompt referencing /delivery
- policy.allow_implicit_invocation: true

- [ ] **Step 3: Create references/state-machine.md**

Full state machine documentation: all states, all transitions, terminal states, retry conditions. Include the ASCII diagram from the spec.

Source: spec state machine section + `.archive/swarm-core-legacy/` → old `skills/swarm-task-control/references/swarm-state-interpretation.md`

- [ ] **Step 4: Create references/driver-matrix.md**

Driver positions, auto-selection heuristics, model normalization rules, per-driver CLI flags.

Source: spec driver matrix section + `.archive/swarm-core-legacy/` → old driver files

- [ ] **Step 5: Create references/dod-gates.md**

All 7 Definition of Done gates:
1. Branch pushed
2. PR created and linked
3. Branch mergeable against base
4. Required CI checks pass
5. Required AI review checks pass
6. UI screenshot present (if UI diff detected)
7. No unresolved critical review

Source: `.archive/swarm-core-legacy/` → `reference/agent-swarm-constitution-v1.md` section 8

- [ ] **Step 6: Create references/retry-policy.md**

Evidence-driven retry rules: capture evidence, inject into prompt, narrow scope, increment counter, max attempts, escalation.

Source: `.archive/swarm-core-legacy/` → `reference/agent-swarm-constitution-v1.md` section 9

- [ ] **Step 7: Create references/notification.md**

Notification config: provider, channel, target, events, failure events, progress cadence, cron setup examples, session key routing.

Source: spec notification section + `.archive/swarm-core-legacy/` → README notification path section

- [ ] **Step 8: Commit**

```bash
git add skills/delivery/SKILL.md skills/delivery/agents/ skills/delivery/references/
git commit -m "feat: /delivery skill docs — SKILL.md, agents yaml, all references

Merges old /delivery and /swarm into single skill surface.
Covers state machine, drivers, DoD gates, retry, notifications."
```

---

### Task 10: Rewrite install.sh

**Files:**
- Modify: `install.sh`

- [ ] **Step 1: Rewrite install.sh**

New behavior:
1. Copy `skills/coding/` → `~/.openclaw/skills/coding/`
2. Copy `skills/delivery/` → `~/.openclaw/skills/delivery/`
3. `chmod +x` on `~/.openclaw/skills/delivery/bin/delivery` and all lib/*.sh
4. If `--link-bin`: symlink `~/.openclaw/skills/delivery/bin/delivery` → `~/.local/bin/delivery`
5. Backup previous install
6. Print confirmation

Remove all swarm-core deployment logic. Remove `swarm` binary references.

Source: current `install.sh` for structure/flags, rewrite body

- [ ] **Step 2: Verify install**

```bash
./install.sh --yes --link-bin
delivery --help
```

Expected: usage text from delivery CLI

- [ ] **Step 3: Commit**

```bash
git add install.sh
git commit -m "feat: rewrite install.sh for skills-first layout

Installs coding + delivery skills to ~/.openclaw/skills/.
Links delivery CLI to ~/.local/bin/delivery."
```

---

### Task 11: Update repo docs

**Files:**
- Modify: `README.md`
- Modify: `AGENTS.md`
- Modify: `CHANGELOG.md`
- Modify: `reference/agent-swarm-architecture.md`
- Modify: `reference/agent-swarm-constitution-v1.md`
- Modify: `reference/agent-swarm-north-star-v1.md`
- Modify: `reference/AGENTS.md`
- Create: `skills/AGENTS.md`

- [ ] **Step 1: Rewrite README.md**

Skills-first README:
- Lead with /coding and /delivery as the two product surfaces
- Install section with new install.sh behavior
- Delivery CLI command reference
- Repo layout table (skills/ → runtime/ is gone, just skills/ + reference/)
- Reading order: skills/coding/ → skills/delivery/ → reference/

- [ ] **Step 2: Rewrite AGENTS.md**

Update directory map:
- skills/coding/ — Pure text ACP operations guide
- skills/delivery/ — Self-contained delivery skill with embedded CLI
- reference/ — Maintainer docs
- No more swarm-core/ entry

- [ ] **Step 3: Update reference/ docs**

Update all three reference docs to reflect:
- skills/ is the public entry
- swarm-core no longer exists as a directory
- delivery CLI lives inside skills/delivery/bin/
- Remove any references to templates/, seed, project wrappers

Update `reference/AGENTS.md` member list.

- [ ] **Step 4: Create skills/AGENTS.md**

New skills-level AGENTS.md with:
- coding/ — Pure text, ACP guide, harness selection
- delivery/ — Self-contained execution skill, embedded delivery CLI

- [ ] **Step 5: Update CHANGELOG.md**

Add entry for the restructure with date, summarizing all changes.

- [ ] **Step 6: Commit**

```bash
git add README.md AGENTS.md CHANGELOG.md reference/ skills/AGENTS.md
git commit -m "docs: update all docs for skills-first restructure

README leads with skills. AGENTS.md reflects new layout.
Reference docs updated. CHANGELOG entry added."
```

---

### Task 12: Integration tests

**Files:**
- Create: `tests/test_common.bats`
- Create: `tests/test_state.bats`
- Create: `tests/test_drivers.bats`
- Create: `tests/test_integration.bats`

- [ ] **Step 1: Write test_common.bats**

Test common.sh functions:
- `now_iso` returns valid ISO timestamp
- `ensure_repo` fails on non-git directory
- `ensure_repo` succeeds on git directory
- `load_config` loads defaults when no conf file
- `load_config` overrides from conf file
- `db_path` returns correct path

- [ ] **Step 2: Write test_drivers.bats**

Test drivers.sh:
- `check_driver_available` returns correct status for installed/missing tools
- `build_driver_command` produces correct command for each driver
- `normalize_model` strips prefix for codex/claudecode/gemini-cli
- `normalize_model` adds prefix for opencode
- `resolve_driver` respects auto selection with frontend keywords
- `resolve_driver` maps claude → claudecode

- [ ] **Step 3: Write test_state.bats**

Test state.sh:
- `check_transition` allows valid transitions
- `check_transition` rejects invalid transitions
- `cmd_init` creates swarm.db with correct schema
- `cmd_status` on empty DB returns no tasks
- State transition validation against full transition map

- [ ] **Step 4: Write test_integration.bats**

End-to-end tests (require git repo):
- Create temp git repo
- `delivery init --repo <tmp>` creates swarm.db
- `delivery status --repo <tmp>` returns empty
- `delivery spawn --repo <tmp> --task-id test-1 --driver codex --prompt "test"` creates task (may fail if codex not installed — test the DB state, not the tmux session)
- Verify task appears in `delivery status`
- `delivery kill --repo <tmp> --task-id test-1` transitions to abandoned
- `delivery cleanup --repo <tmp>` cleans artifacts
- Verify existing swarm.db from old Python system loads correctly

- [ ] **Step 5: Run all tests**

```bash
bats tests/
```

Expected: all tests pass

- [ ] **Step 6: Commit**

```bash
git add tests/
git commit -m "test: bats integration tests for delivery CLI

Covers common utilities, driver logic, state machine validation,
and end-to-end init/spawn/status/kill/cleanup flow."
```

---

## Post-Implementation Checklist

- [ ] `delivery --help` works from symlink
- [ ] `delivery init --repo <path>` creates swarm.db
- [ ] `delivery spawn` creates worktree + tmux session + DB row
- [ ] `delivery status` shows tasks in text and JSON
- [ ] `delivery redirect` sends to tmux session
- [ ] `delivery kill` transitions to abandoned
- [ ] `delivery monitor` runs inspection loop
- [ ] `delivery cleanup` removes artifacts
- [ ] `delivery cleanup --legacy` removes old seeded scripts
- [ ] `/coding` SKILL.md loads in OpenClaw
- [ ] `/delivery` SKILL.md loads in OpenClaw
- [ ] `install.sh --yes --link-bin` works end-to-end
- [ ] Existing swarm.db files work without migration
- [ ] `bats tests/` passes
- [ ] No references to swarm-core/ remain outside .archive/
- [ ] No references to old skill directory names remain
