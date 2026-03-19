<!--
[INPUT]: delivery bin/lib/notify.sh, .openclaw/delivery.conf notification settings
[OUTPUT]: Notification provider config, routing rules, progress update protocol, cron setup
[POS]: delivery/references notification specification; consumed by SKILL.md and notify.sh implementation
[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
-->

# Notification

Delivery uses OpenClaw as the notification provider. All notifications are
sent via `openclaw message send`.

## Configuration

Notification settings live in `.openclaw/delivery.conf`:

```bash
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

### Defaults

| Setting | Default | Description |
|---------|---------|-------------|
| `notify_enabled` | `false` | Master switch. Notifications are off until explicitly enabled. |
| `notify_channel` | `discord` | Delivery channel (discord, telegram, etc.) |
| `notify_target` | (empty) | Target identifier (channel ID, chat ID, etc.) |
| `notify_account` | (empty) | Account identifier for multi-account setups |
| `notify_events` | `ready_to_merge,merged` | Comma-separated list of events that trigger notification |
| `notify_allow_failure_events` | `false` | Whether to notify on failure events (`failed`, `ci_failed`, `abandoned`) |
| `progress_enabled` | `true` | Whether to send periodic progress updates |
| `progress_interval_minutes` | `5` | Minutes between progress updates |

## Routing Priority

Notification target is resolved in this order:

1. **Task-level override** — `--notify-target` flag on `delivery spawn`
2. **Source session key** — `--source-session-key` routes back to the originating OpenClaw session
3. **Project static target** — `notify_target` in `delivery.conf`

If no target resolves, the notification is silently skipped (not an error).

## Event Types

### Default Events

These events notify by default when `notify_enabled=true`:

| Event | Trigger |
|-------|---------|
| `ready_to_merge` | All 7 DoD gates passed. Human action needed. |
| `merged` | PR merged successfully. Informational. |

### Failure Events

These events only notify when `notify_allow_failure_events=true`:

| Event | Trigger |
|-------|---------|
| `failed` | Driver execution failed |
| `ci_failed` | CI checks failed |
| `abandoned` | Task abandoned (max retries or killed) |

Failure events are disabled by default to avoid notification fatigue.
The monitor loop handles retries automatically — the human only needs to
know when intervention is required.

## Progress Updates

When `progress_enabled=true`, the system sends periodic progress messages
with a `System: [swarm-progress]` prefix.

- **Default interval**: every 5 minutes
- **Per-task override**: `--progress-every <min>` on `delivery spawn`
- **Disable for a task**: `--no-progress` on `delivery spawn`

Progress messages include:
- Task ID and current state
- Driver name and attempt number
- Time elapsed since task start
- Brief status summary

## Per-Task Overrides

`delivery spawn` accepts notification flags that override project defaults
for a single task:

```bash
delivery spawn \
  --repo /path/to/repo \
  --task-id my-task \
  --driver auto \
  --prompt "..." \
  --source-session-key <key> \
  --notify-channel discord \
  --notify-target "#dev-alerts" \
  --notify-account my-bot \
  --progress-every 10
```

These overrides are stored with the task record and used for the task's
entire lifecycle.

## Cron Setup

The monitor loop must be scheduled externally. Delivery does not install
cron entries automatically — this is the operator's responsibility.

### Example: Monitor Every 10 Minutes

```bash
*/10 * * * * delivery monitor --repo /path/to/repo
```

### Example: Multiple Repos

```bash
*/10 * * * * delivery monitor --repo /path/to/repo-a
*/10 * * * * delivery monitor --repo /path/to/repo-b
```

### Example: With Logging

```bash
*/10 * * * * delivery monitor --repo /path/to/repo >> /var/log/delivery-monitor.log 2>&1
```

The monitor loop is idempotent — running it more frequently than needed is
safe but wasteful. Running it less frequently delays state transitions and
retry attempts.

## Priority Override Chain

The full priority chain for all notification settings:

```
CLI flags > environment variables > delivery.conf > hardcoded defaults
```

This applies to all settings, not just notification-specific ones.

[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
