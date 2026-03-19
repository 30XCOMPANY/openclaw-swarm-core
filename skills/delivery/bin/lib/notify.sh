#!/usr/bin/env bash
# =============================================================================
# notify.sh — OpenClaw notification routing and dispatch
# =============================================================================
# [INPUT]:  common.sh (CONF_NOTIFY_*, STATUS_*, sql, now_iso, die),
#           openclaw CLI (message send), ~/.openclaw/logs/commands.log
# [OUTPUT]: send_status_notification, send_progress_notification,
#           resolve_task_notify_route, dispatch_openclaw_notification,
#           build_notification_message, and supporting helpers
# [POS]:   Notification subsystem; consumed by monitor/state modules to push
#          status and progress updates via OpenClaw message routing
# [PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
# =============================================================================

# -- Guard against double-source --
[[ -n "${_NOTIFY_SH_LOADED:-}" ]] && return 0
readonly _NOTIFY_SH_LOADED=1

# =============================================================================
# Constants
# =============================================================================

readonly PROGRESS_STATUSES="${STATUS_RUNNING}|${STATUS_PR_CREATED}|${STATUS_CI_FAILED}|${STATUS_CI_PASSED}|${STATUS_REVIEW_CHANGES}"
readonly MAX_MESSAGE_LENGTH=1800

# =============================================================================
# is_temp_repo_path — check if path is under /tmp/ or /private/tmp/
# =============================================================================

is_temp_repo_path() {
  local raw="${1:-}"
  local resolved
  resolved="$(cd "$raw" 2>/dev/null && pwd -P)" || resolved="$raw"
  [[ "$resolved" == /tmp/* || "$resolved" == /private/tmp/* ]]
}

# =============================================================================
# truncate_text — trim whitespace and cap at $2 chars with "..." suffix
# =============================================================================

truncate_text() {
  local text="${1:-}"
  local limit="${2:-1800}"
  text="${text#"${text%%[![:space:]]*}"}"
  text="${text%"${text##*[![:space:]]}"}"
  if (( ${#text} <= limit )); then
    printf '%s' "$text"
    return
  fi
  local cut=$(( limit - 3 ))
  (( cut < 0 )) && cut=0
  printf '%s...' "${text:0:$cut}"
}

# =============================================================================
# normalized_notify_events — parse config events, filter against allowed set
# =============================================================================

normalized_notify_events() {
  local events="${1:-$CONF_NOTIFY_EVENTS}"
  local allow_failure="${2:-$CONF_NOTIFY_ALLOW_FAILURE_EVENTS}"

  local -a allowed=( "$STATUS_READY" "$STATUS_MERGED" )
  if [[ "$allow_failure" == "true" ]]; then
    allowed+=( "$STATUS_ABANDONED" "$STATUS_FAILED" "$STATUS_CI_FAILED" "$STATUS_REVIEW_CHANGES" )
  fi

  local -a result=()
  local item
  for item in $events; do
    item="$(printf '%s' "$item" | tr ',' ' ')"
    local word
    for word in $item; do
      word="$(printf '%s' "$word" | tr '[:upper:]' '[:lower:]')"
      word="${word#"${word%%[![:space:]]*}"}"
      word="${word%"${word##*[![:space:]]}"}"
      [[ -z "$word" ]] && continue
      # Check if word is in allowed set
      local a; local found=false
      for a in "${allowed[@]}"; do
        [[ "$word" == "$a" ]] && found=true && break
      done
      $found || continue
      # Deduplicate
      local r; local dup=false
      for r in "${result[@]+"${result[@]}"}"; do
        [[ "$r" == "$word" ]] && dup=true && break
      done
      $dup || result+=( "$word" )
    done
  done

  if (( ${#result[@]} == 0 )); then
    result=( "$STATUS_READY" "$STATUS_MERGED" )
  fi
  printf '%s\n' "${result[@]}"
}

# =============================================================================
# openclaw_state_dir — resolve ~/.openclaw or $OPENCLAW_CONFIG_PATH parent
# =============================================================================

_openclaw_state_dir() {
  if [[ -n "${OPENCLAW_CONFIG_PATH:-}" ]]; then
    local dir
    dir="$(cd "$(dirname "$OPENCLAW_CONFIG_PATH")" 2>/dev/null && pwd -P)" || dir=""
    if [[ -n "$dir" ]]; then
      printf '%s' "$dir"
      return
    fi
  fi
  printf '%s/.openclaw' "$HOME"
}

# =============================================================================
# load_openclaw_bindings — read bindings array from openclaw.json
# =============================================================================

_load_openclaw_bindings() {
  local config_path
  config_path="$(_openclaw_state_dir)/openclaw.json"
  [[ -f "$config_path" ]] || return
  # Extract bindings array via jq (fail silently if unavailable)
  if command -v jq >/dev/null 2>&1; then
    jq -c '.bindings // [] | .[]' "$config_path" 2>/dev/null
  fi
}

# =============================================================================
# _binding_account_for_agent — look up accountId for agent+channel in bindings
# =============================================================================

_binding_account_for_agent() {
  local channel="${1:-}"
  local agent_id="${2:-}"
  [[ -z "$channel" || -z "$agent_id" ]] && return

  local chan
  chan="$(printf '%s' "$channel" | tr '[:upper:]' '[:lower:]')"

  local binding
  while IFS= read -r binding; do
    [[ -z "$binding" ]] && continue
    if ! command -v jq >/dev/null 2>&1; then
      return
    fi
    local bid bchan bacct
    bid="$(printf '%s' "$binding" | jq -r '.agentId // ""' 2>/dev/null)"
    [[ "$bid" != "$agent_id" ]] && continue
    bchan="$(printf '%s' "$binding" | jq -r '.match.channel // ""' 2>/dev/null)"
    bchan="$(printf '%s' "$bchan" | tr '[:upper:]' '[:lower:]')"
    [[ "$bchan" != "$chan" ]] && continue
    bacct="$(printf '%s' "$binding" | jq -r '.match.accountId // ""' 2>/dev/null)"
    if [[ -n "$bacct" ]]; then
      printf '%s' "$bacct"
      return
    fi
  done < <(_load_openclaw_bindings)
}

# =============================================================================
# parse_discord_route_from_session_key — extract channel_id from session key
# =============================================================================
# Pattern: agent:<agent_id>:discord:channel:<channel_id>
# Returns tab-separated: channel \t target \t account \t source_session_key
# Returns 1 if pattern does not match.

parse_discord_route_from_session_key() {
  local raw="${1:-}"
  raw="${raw#"${raw%%[![:space:]]*}"}"
  raw="${raw%"${raw##*[![:space:]]}"}"
  [[ -z "$raw" ]] && return 1

  if [[ "$raw" =~ ^agent:([^:]+):discord:channel:([0-9]+)$ ]]; then
    local agent_id="${BASH_REMATCH[1]}"
    local channel_id="${BASH_REMATCH[2]}"
    local account
    account="$(_binding_account_for_agent "discord" "$agent_id")"

    # Output: channel target account source_session_key
    printf '%s\t%s\t%s\t%s' \
      "discord" \
      "channel:${channel_id}" \
      "${account:-}" \
      "$raw"
    return 0
  fi
  return 1
}

# =============================================================================
# discover_recent_discord_session_key — scan commands.log for recent sessions
# =============================================================================
# Searches backwards through ~/.openclaw/logs/commands.log for a Discord
# session key younger than $1 seconds (default 900).

discover_recent_discord_session_key() {
  local max_age="${1:-900}"
  local log_path
  log_path="$(_openclaw_state_dir)/logs/commands.log"
  [[ -f "$log_path" ]] || return

  command -v jq >/dev/null 2>&1 || return

  local now_epoch
  now_epoch="$(date +%s)"

  # Read lines in reverse order
  local line
  tac "$log_path" 2>/dev/null | while IFS= read -r line; do
    [[ -z "$line" ]] && continue

    local source_val session_key timestamp_raw
    source_val="$(printf '%s' "$line" | jq -r '.source // ""' 2>/dev/null)" || continue
    source_val="$(printf '%s' "$source_val" | tr '[:upper:]' '[:lower:]')"
    [[ "$source_val" != "discord" ]] && continue

    session_key="$(printf '%s' "$line" | jq -r '.sessionKey // ""' 2>/dev/null)"
    session_key="${session_key#"${session_key%%[![:space:]]*}"}"
    session_key="${session_key%"${session_key##*[![:space:]]}"}"
    [[ -z "$session_key" ]] && continue

    # Validate it parses as discord route
    parse_discord_route_from_session_key "$session_key" >/dev/null 2>&1 || continue

    # Check age
    timestamp_raw="$(printf '%s' "$line" | jq -r '.timestamp // ""' 2>/dev/null)"
    if [[ -n "$timestamp_raw" ]]; then
      local event_epoch
      event_epoch="$(date -j -f "%Y-%m-%dT%H:%M:%S" "${timestamp_raw%%[.Z+]*}" +%s 2>/dev/null)" \
        || event_epoch="$(date -d "$timestamp_raw" +%s 2>/dev/null)" \
        || event_epoch=""
      if [[ -n "$event_epoch" ]]; then
        local elapsed=$(( now_epoch - event_epoch ))
        (( elapsed > max_age )) && continue
      fi
    fi

    printf '%s' "$session_key"
    return 0
  done
}

# =============================================================================
# resolve_task_notify_route — derive channel/target/account from row + config
# =============================================================================
# Accepts tab-separated row fields:
#   $1=notify_channel  $2=notify_target  $3=notify_account  $4=source_session_key
# Falls back to CONF_NOTIFY_* defaults.
# Outputs tab-separated: channel \t target \t account \t source_session_key

resolve_task_notify_route() {
  local row_channel="${1:-}"
  local row_target="${2:-}"
  local row_account="${3:-}"
  local row_session_key="${4:-}"

  local channel target account source_session_key
  channel="${row_channel:-$CONF_NOTIFY_CHANNEL}"
  channel="$(printf '%s' "$channel" | tr '[:upper:]' '[:lower:]')"
  channel="${channel#"${channel%%[![:space:]]*}"}"
  channel="${channel%"${channel##*[![:space:]]}"}"

  target="${row_target:-$CONF_NOTIFY_TARGET}"
  target="${target#"${target%%[![:space:]]*}"}"
  target="${target%"${target##*[![:space:]]}"}"

  account="${row_account:-$CONF_NOTIFY_ACCOUNT}"
  account="${account#"${account%%[![:space:]]*}"}"
  account="${account%"${account##*[![:space:]]}"}"

  source_session_key="${row_session_key}"
  source_session_key="${source_session_key#"${source_session_key%%[![:space:]]*}"}"
  source_session_key="${source_session_key%"${source_session_key##*[![:space:]]}"}"

  printf '%s\t%s\t%s\t%s' "$channel" "$target" "$account" "$source_session_key"
}

# =============================================================================
# should_send_notification — gate check for status notifications
# =============================================================================
# Args: $1=repo_path $2=status $3=notify_on_ready
#        $4=notify_channel $5=notify_target $6=notify_account $7=source_session_key
# Returns 0 (should send) or 1 (should not).

should_send_notification() {
  local repo_path="${1:-}"
  local status="${2:-}"
  local notify_on_ready="${3:-1}"
  local row_channel="${4:-}" row_target="${5:-}" row_account="${6:-}" row_session="${7:-}"

  [[ "$CONF_NOTIFY_ENABLED" == "true" ]] || return 1
  [[ "$CONF_NOTIFY_PROVIDER" == "openclaw" ]] || return 1
  is_temp_repo_path "$repo_path" && return 1

  local route_line
  route_line="$(resolve_task_notify_route "$row_channel" "$row_target" "$row_account" "$row_session")"
  local channel target
  channel="$(printf '%s' "$route_line" | cut -f1)"
  target="$(printf '%s' "$route_line" | cut -f2)"
  [[ -z "$channel" || -z "$target" ]] && return 1

  local lower_status
  lower_status="$(printf '%s' "$status" | tr '[:upper:]' '[:lower:]')"

  local enabled_event found=false
  while IFS= read -r enabled_event; do
    [[ "$enabled_event" == "$lower_status" ]] && found=true && break
  done < <(normalized_notify_events)
  $found || return 1

  # ready_to_merge requires notify_on_ready flag
  if [[ "$status" == "$STATUS_READY" && "$notify_on_ready" != "1" ]]; then
    return 1
  fi

  return 0
}

# =============================================================================
# notification_sent — dedup check in task_notifications table
# =============================================================================

notification_sent() {
  local repo="${1:?usage: notification_sent <repo> <task_id> <status>}"
  local task_id="${2:?}"
  local status="${3:?}"
  local row
  row="$(sql "$repo" "SELECT 1 FROM task_notifications WHERE task_id = '$task_id' AND status = '$status' LIMIT 1;")"
  [[ -n "$row" ]]
}

# =============================================================================
# build_notification_message — format multi-line status notification
# =============================================================================
# Args (positional): task_id status driver model attempt_count max_attempts
#                     repo_path branch pr_url pr_number last_error_reason detail

build_notification_message() {
  local task_id="${1:-}" status="${2:-}" driver="${3:-}" model="${4:-}"
  local attempt_count="${5:-0}" max_attempts="${6:-3}"
  local repo_path="${7:-}" branch="${8:-}" pr_url="${9:-}" pr_number="${10:-}"
  local last_error_reason="${11:-}" detail="${12:-}"

  local repo_name
  repo_name="$(basename "$repo_path")"
  [[ -z "$repo_name" ]] && repo_name="${repo_path:--}"

  local lines=""
  lines="[swarm] ${repo_name}"
  lines="${lines}"$'\n'"task=${task_id} status=${status}"
  lines="${lines}"$'\n'"driver=${driver} model=${model} attempt=${attempt_count}/${max_attempts}"

  [[ -n "$branch" ]] && lines="${lines}"$'\n'"branch=${branch}"

  if [[ -n "$pr_url" ]]; then
    lines="${lines}"$'\n'"pr=${pr_url}"
  elif [[ -n "$pr_number" ]]; then
    lines="${lines}"$'\n'"pr=#${pr_number}"
  fi

  local note="${detail:-$last_error_reason}"
  note="${note#"${note%%[![:space:]]*}"}"
  note="${note%"${note##*[![:space:]]}"}"
  [[ -n "$note" ]] && lines="${lines}"$'\n'"note=${note}"

  truncate_text "$lines" "$MAX_MESSAGE_LENGTH"
}

# =============================================================================
# dispatch_openclaw_notification — execute openclaw message send
# =============================================================================
# Args: $1=channel $2=target $3=message $4=account
# Outputs JSON result to stdout. Returns 0 on success, 1 on failure.

dispatch_openclaw_notification() {
  local channel="${1:?usage: dispatch_openclaw_notification <ch> <target> <msg> [account]}"
  local target="${2:?}"
  local message="${3:?}"
  local account="${4:-}"

  if ! command -v openclaw >/dev/null 2>&1; then
    printf '{"code":"openclaw_not_found"}'
    return 1
  fi

  local -a cmd=( openclaw message send --channel "$channel" --target "$target" --message "$message" --json )
  [[ -n "$account" ]] && cmd+=( --account "$account" )
  [[ "$CONF_NOTIFY_SILENT" == "true" ]] && cmd+=( --silent )
  [[ "$CONF_NOTIFY_DRY_RUN" == "true" ]] && cmd+=( --dry-run )

  local stdout="" stderr="" rc=0
  stdout="$("${cmd[@]}" 2>/tmp/_notify_stderr)" || rc=$?
  stderr="$(cat /tmp/_notify_stderr 2>/dev/null)" || stderr=""
  rm -f /tmp/_notify_stderr

  stdout="$(truncate_text "$stdout" 3000)"
  stderr="$(truncate_text "$stderr" 2000)"

  printf '{"returncode":%d,"stdout":"%s","stderr":"%s"}' \
    "$rc" \
    "$(printf '%s' "$stdout" | sed 's/"/\\"/g' | tr '\n' ' ')" \
    "$(printf '%s' "$stderr" | sed 's/"/\\"/g' | tr '\n' ' ')"

  (( rc == 0 )) && return 0 || return 1
}

# =============================================================================
# _record_event — insert into task_events (thin wrapper around sql)
# =============================================================================

_record_event() {
  local repo="${1:?}" task_id="${2:?}" event_type="${3:?}"
  local old_status="${4:-}" new_status="${5:-}" message="${6:-}" payload="${7:-}"
  local ts
  ts="$(now_iso)"
  sql "$repo" "INSERT INTO task_events(task_id, event_type, old_status, new_status, message, payload, created_at) \
    VALUES('$task_id', '$event_type', '$old_status', '$new_status', '$message', '$payload', '$ts');"
}

# =============================================================================
# send_status_notification — orchestrate: gate → dedup → build → dispatch → record
# =============================================================================
# Args: $1=repo_path, remaining are task row fields passed positionally:
#   $2=task_id $3=status $4=driver $5=model $6=attempt_count $7=max_attempts
#   $8=branch $9=pr_url $10=pr_number $11=last_error_reason $12=detail
#   $13=notify_on_ready $14=notify_channel $15=notify_target $16=notify_account
#   $17=source_session_key

send_status_notification() {
  local repo="${1:?usage: send_status_notification <repo> ...}"
  local task_id="${2:-}" status="${3:-}" driver="${4:-}" model="${5:-}"
  local attempt_count="${6:-0}" max_attempts="${7:-3}"
  local branch="${8:-}" pr_url="${9:-}" pr_number="${10:-}"
  local last_error_reason="${11:-}" detail="${12:-}"
  local notify_on_ready="${13:-1}"
  local row_channel="${14:-}" row_target="${15:-}" row_account="${16:-}" row_session="${17:-}"

  # Gate check
  should_send_notification "$repo" "$status" "$notify_on_ready" \
    "$row_channel" "$row_target" "$row_account" "$row_session" || return 1

  # Dedup check
  notification_sent "$repo" "$task_id" "$status" && return 1

  # Build route + message
  local route_line
  route_line="$(resolve_task_notify_route "$row_channel" "$row_target" "$row_account" "$row_session")"
  local channel target account source_session_key
  channel="$(printf '%s' "$route_line" | cut -f1)"
  target="$(printf '%s' "$route_line" | cut -f2)"
  account="$(printf '%s' "$route_line" | cut -f3)"
  source_session_key="$(printf '%s' "$route_line" | cut -f4)"

  local message
  message="$(build_notification_message \
    "$task_id" "$status" "$driver" "$model" \
    "$attempt_count" "$max_attempts" "$repo" "$branch" \
    "$pr_url" "$pr_number" "$last_error_reason" "$detail")"

  # Dispatch
  local result="" ok=true
  result="$(dispatch_openclaw_notification "$channel" "$target" "$message" "$account")" || ok=false

  if ! $ok; then
    local fail_payload
    fail_payload="$(printf '{"provider":"%s","channel":"%s","target":"%s","account":"%s","sourceSessionKey":"%s","result":%s}' \
      "$CONF_NOTIFY_PROVIDER" "$channel" "$target" "$account" "$source_session_key" \
      "${result:-\"{}\"}")"
    _record_event "$repo" "$task_id" "notification_failed" "$status" "$status" \
      "notify failed: $status" "$fail_payload"
    return 1
  fi

  # Record in task_notifications
  local ts
  ts="$(now_iso)"
  local safe_msg safe_result
  safe_msg="$(printf '%s' "$message" | sed "s/'/''/g")"
  safe_result="$(printf '%s' "$result" | sed "s/'/''/g")"
  sql "$repo" "INSERT OR IGNORE INTO task_notifications(task_id, status, channel, target, message, result, sent_at) \
    VALUES('$task_id', '$status', '$channel', '$target', '$safe_msg', '$safe_result', '$ts');"

  # Record event
  local success_payload
  success_payload="$(printf '{"provider":"%s","channel":"%s","target":"%s","account":"%s","sourceSessionKey":"%s"}' \
    "$CONF_NOTIFY_PROVIDER" "$channel" "$target" "$account" "$source_session_key")"
  _record_event "$repo" "$task_id" "notification_sent" "$status" "$status" \
    "notified: $status" "$success_payload"
  return 0
}

# =============================================================================
# Progress notification helpers
# =============================================================================

# -- progress_doing — human description of what's happening at this status --
_progress_doing() {
  case "${1:-}" in
    "$STATUS_RUNNING")          printf 'Agent is implementing code in worktree and tmux session.' ;;
    "$STATUS_PR_CREATED")       printf 'PR is open; waiting for CI and review gates.' ;;
    "$STATUS_CI_FAILED")        printf 'CI is failing; waiting retry with failure evidence.' ;;
    "$STATUS_CI_PASSED")        printf 'CI passed; waiting review and mergeability checks.' ;;
    "$STATUS_REVIEW_CHANGES")   printf 'Review requested changes; retry loop preparing fix.' ;;
    *)                          printf 'Task is progressing through delivery pipeline.' ;;
  esac
}

# -- progress_next — what happens next --
_progress_next() {
  case "${1:-}" in
    "$STATUS_RUNNING")                                      printf 'Create PR and enter gate checks.' ;;
    "$STATUS_PR_CREATED"|"$STATUS_CI_PASSED")               printf 'Wait for all DoD gates then mark ready_to_merge.' ;;
    "$STATUS_CI_FAILED"|"$STATUS_REVIEW_CHANGES")           printf 'Auto-retry with contextual evidence injection.' ;;
    *)                                                      printf 'Continue monitor loop.' ;;
  esac
}

# =============================================================================
# should_send_progress_notification — gate check for progress updates
# =============================================================================
# Args: $1=repo_path $2=status $3=progress_notify_enabled
#       $4=progress_notify_interval_minutes $5=last_progress_notified_at
#       $6=started_at $7=created_at
#       $8=notify_channel $9=notify_target $10=notify_account $11=source_session_key

should_send_progress_notification() {
  local repo_path="${1:-}" status="${2:-}"
  local progress_enabled="${3:-0}" interval_minutes="${4:-0}"
  local last_notified="${5:-}" started_at="${6:-}" created_at="${7:-}"
  local row_channel="${8:-}" row_target="${9:-}" row_account="${10:-}" row_session="${11:-}"

  [[ "$CONF_NOTIFY_ENABLED" == "true" ]] || return 1
  [[ "$CONF_NOTIFY_PROVIDER" == "openclaw" ]] || return 1
  is_temp_repo_path "$repo_path" && return 1

  # Status must be in progress set
  local s found=false
  IFS='|' read -ra _pstats <<< "$PROGRESS_STATUSES"
  for s in "${_pstats[@]}"; do
    [[ "$status" == "$s" ]] && found=true && break
  done
  $found || return 1

  # Route must be valid
  local route_line
  route_line="$(resolve_task_notify_route "$row_channel" "$row_target" "$row_account" "$row_session")"
  local channel target
  channel="$(printf '%s' "$route_line" | cut -f1)"
  target="$(printf '%s' "$route_line" | cut -f2)"
  [[ -z "$channel" || -z "$target" ]] && return 1

  # Task-level progress must be enabled
  [[ "$progress_enabled" == "1" ]] || return 1
  (( interval_minutes > 0 )) || return 1

  # Check elapsed time since anchor
  local anchor="${last_notified:-${started_at:-${created_at:-}}}"
  [[ -z "$anchor" ]] && return 0  # No anchor → always send

  local now_epoch anchor_epoch
  now_epoch="$(date +%s)"
  anchor_epoch="$(date -j -f "%Y-%m-%dT%H:%M:%S" "${anchor%%[.Z+]*}" +%s 2>/dev/null)" \
    || anchor_epoch="$(date -d "$anchor" +%s 2>/dev/null)" \
    || anchor_epoch=""
  [[ -z "$anchor_epoch" ]] && return 0  # Unparseable → send

  local elapsed=$(( now_epoch - anchor_epoch ))
  local threshold=$(( interval_minutes * 60 ))
  (( elapsed >= threshold ))
}

# =============================================================================
# build_progress_message — format multi-line progress notification
# =============================================================================
# Args: task_id status driver model attempt_count max_attempts
#       repo_path branch pr_url pr_number ci_status last_error_reason

build_progress_message() {
  local task_id="${1:-}" status="${2:-}" driver="${3:-}" model="${4:-}"
  local attempt_count="${5:-0}" max_attempts="${6:-3}"
  local repo_path="${7:-}" branch="${8:-}" pr_url="${9:-}" pr_number="${10:-}"
  local ci_status="${11:-}" last_error_reason="${12:-}"

  local repo_name
  repo_name="$(basename "$repo_path")"
  [[ -z "$repo_name" ]] && repo_name="${repo_path:--}"

  local doing next_step
  doing="$(_progress_doing "$status")"
  next_step="$(_progress_next "$status")"

  local lines=""
  lines="System: [swarm-progress] ${repo_name}"
  lines="${lines}"$'\n'"task=${task_id} status=${status}"
  lines="${lines}"$'\n'"doing=${doing}"
  lines="${lines}"$'\n'"next=${next_step}"
  lines="${lines}"$'\n'"attempt=${attempt_count}/${max_attempts} driver=${driver} model=${model}"

  [[ -n "$branch" ]] && lines="${lines}"$'\n'"branch=${branch}"

  if [[ -n "$pr_url" ]]; then
    lines="${lines}"$'\n'"pr=${pr_url}"
  elif [[ -n "$pr_number" ]]; then
    lines="${lines}"$'\n'"pr=#${pr_number}"
  fi

  ci_status="${ci_status#"${ci_status%%[![:space:]]*}"}"
  ci_status="${ci_status%"${ci_status##*[![:space:]]}"}"
  [[ -n "$ci_status" ]] && lines="${lines}"$'\n'"ci=${ci_status}"

  local note="${last_error_reason}"
  note="${note#"${note%%[![:space:]]*}"}"
  note="${note%"${note##*[![:space:]]}"}"
  [[ -n "$note" ]] && lines="${lines}"$'\n'"note=${note}"

  truncate_text "$lines" "$MAX_MESSAGE_LENGTH"
}

# =============================================================================
# send_progress_notification — orchestrate progress update dispatch
# =============================================================================
# Args: $1=repo_path, remaining are task row fields:
#   $2=task_id $3=status $4=driver $5=model $6=attempt_count $7=max_attempts
#   $8=branch $9=pr_url $10=pr_number $11=ci_status $12=last_error_reason
#   $13=progress_notify_enabled $14=progress_notify_interval_minutes
#   $15=last_progress_notified_at $16=started_at $17=created_at
#   $18=notify_channel $19=notify_target $20=notify_account $21=source_session_key

send_progress_notification() {
  local repo="${1:?usage: send_progress_notification <repo> ...}"
  local task_id="${2:-}" status="${3:-}" driver="${4:-}" model="${5:-}"
  local attempt_count="${6:-0}" max_attempts="${7:-3}"
  local branch="${8:-}" pr_url="${9:-}" pr_number="${10:-}"
  local ci_status="${11:-}" last_error_reason="${12:-}"
  local progress_enabled="${13:-0}" interval_minutes="${14:-0}"
  local last_notified="${15:-}" started_at="${16:-}" created_at="${17:-}"
  local row_channel="${18:-}" row_target="${19:-}" row_account="${20:-}" row_session="${21:-}"

  # Gate check
  should_send_progress_notification "$repo" "$status" \
    "$progress_enabled" "$interval_minutes" \
    "$last_notified" "$started_at" "$created_at" \
    "$row_channel" "$row_target" "$row_account" "$row_session" || return 1

  # Build route + message
  local route_line
  route_line="$(resolve_task_notify_route "$row_channel" "$row_target" "$row_account" "$row_session")"
  local channel target account source_session_key
  channel="$(printf '%s' "$route_line" | cut -f1)"
  target="$(printf '%s' "$route_line" | cut -f2)"
  account="$(printf '%s' "$route_line" | cut -f3)"
  source_session_key="$(printf '%s' "$route_line" | cut -f4)"

  local message
  message="$(build_progress_message \
    "$task_id" "$status" "$driver" "$model" \
    "$attempt_count" "$max_attempts" "$repo" "$branch" \
    "$pr_url" "$pr_number" "$ci_status" "$last_error_reason")"

  # Dispatch
  local result="" ok=true
  result="$(dispatch_openclaw_notification "$channel" "$target" "$message" "$account")" || ok=false

  if ! $ok; then
    local fail_payload
    fail_payload="$(printf '{"channel":"%s","target":"%s","account":"%s","sourceSessionKey":"%s","result":%s}' \
      "$channel" "$target" "$account" "$source_session_key" \
      "${result:-\"{}\"}")"
    _record_event "$repo" "$task_id" "progress_notification_failed" "$status" "$status" \
      "progress notify failed" "$fail_payload"
    return 1
  fi

  # Record in task_progress_notifications
  local ts
  ts="$(now_iso)"
  local safe_msg safe_result
  safe_msg="$(printf '%s' "$message" | sed "s/'/''/g")"
  safe_result="$(printf '%s' "$result" | sed "s/'/''/g")"
  sql "$repo" "INSERT INTO task_progress_notifications(task_id, status, channel, target, message, result, sent_at) \
    VALUES('$task_id', '$status', '$channel', '$target', '$safe_msg', '$safe_result', '$ts');"

  # Update last_progress_notified_at on the task
  sql "$repo" "UPDATE tasks SET last_progress_notified_at = '$ts', updated_at = '$ts' WHERE id = '$task_id';"

  # Record event
  local success_payload
  success_payload="$(printf '{"channel":"%s","target":"%s","account":"%s","sourceSessionKey":"%s"}' \
    "$channel" "$target" "$account" "$source_session_key")"
  _record_event "$repo" "$task_id" "progress_notification_sent" "$status" "$status" \
    "progress update sent" "$success_payload"
  return 0
}
