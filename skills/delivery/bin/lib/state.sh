#!/usr/bin/env bash
# =============================================================================
# state.sh — SQLite state machine, spawn, status, redirect, kill
# =============================================================================
# [INPUT]:  common.sh (die, sql, sql_json, ensure_repo, ensure_db, load_config,
#           detect_base_branch, now_iso, db_path, openclaw_dir, STATUS_*),
#           drivers.sh (resolve_driver, build_driver_command, normalize_model,
#           check_driver_available),
#           git-ops.sh (create_worktree, remove_worktree),
#           notify.sh (send_status_notification, _record_event,
#           resolve_task_notify_route, discover_recent_discord_session_key,
#           parse_discord_route_from_session_key)
# [OUTPUT]: check_transition, transition_task, cmd_init, cmd_spawn, cmd_status,
#           cmd_redirect, cmd_kill — the five core command handlers
# [POS]:   State machine + command handler layer; wired by bin/delivery entrypoint
# [PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
# =============================================================================

# -- Guard against double-source --
[[ -n "${_STATE_SH_LOADED:-}" ]] && return 0
readonly _STATE_SH_LOADED=1

# -- Load dependencies --
SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"
# shellcheck source=drivers.sh
source "${SCRIPT_DIR}/drivers.sh"
# shellcheck source=git-ops.sh
source "${SCRIPT_DIR}/git-ops.sh"
# shellcheck source=notify.sh
source "${SCRIPT_DIR}/notify.sh"

# =============================================================================
# State transition map — mirrors Python STATE_TRANSITIONS exactly
# =============================================================================

# _allowed_transitions <state>
#   Prints space-separated list of valid target states.
#   Pure function — no global mutable state, bash 3.2 compatible.
_allowed_transitions() {
  case "${1:-}" in
    queued)                     printf '%s' "running abandoned" ;;
    running)                    printf '%s' "pr_created failed abandoned" ;;
    pr_created)                 printf '%s' "ci_failed ci_passed review_changes_requested ready_to_merge merged abandoned" ;;
    ci_failed)                  printf '%s' "running abandoned" ;;
    ci_passed)                  printf '%s' "review_changes_requested ready_to_merge merged ci_failed abandoned" ;;
    review_changes_requested)   printf '%s' "running ready_to_merge abandoned" ;;
    ready_to_merge)             printf '%s' "merged review_changes_requested ci_failed abandoned" ;;
    failed)                     printf '%s' "running abandoned" ;;
    merged)                     printf '%s' "" ;;
    abandoned)                  printf '%s' "" ;;
    *)                          printf '%s' "" ;;
  esac
}

# All known states — for completeness checks
readonly ALL_STATES="queued running pr_created ci_failed ci_passed review_changes_requested ready_to_merge merged failed abandoned"

# =============================================================================
# check_transition — validate old → new against transition map
# =============================================================================
# Same-state is a no-op (returns 0). Invalid transition → die.

check_transition() {
  local old="${1:?usage: check_transition <old_status> <new_status>}"
  local new="${2:?usage: check_transition <old_status> <new_status>}"

  # Same state: no-op
  [[ "$old" == "$new" ]] && return 0

  local allowed
  allowed="$(_allowed_transitions "$old")"
  local target
  for target in $allowed; do
    [[ "$target" == "$new" ]] && return 0
  done

  die "Illegal state transition: ${old} -> ${new}"
}

# =============================================================================
# transition_task — atomic: validate + UPDATE tasks + INSERT task_events
# =============================================================================
# Args: repo, task_id, old_status, new_status, message

transition_task() {
  local repo="${1:?usage: transition_task <repo> <task_id> <old> <new> [message]}"
  local task_id="${2:?}"
  local old_status="${3:?}"
  local new_status="${4:?}"
  local message="${5:-}"

  check_transition "$old_status" "$new_status"

  # Same state — nothing to do
  [[ "$old_status" == "$new_status" ]] && return 0

  local now
  now="$(now_iso)"
  local db
  db="$(db_path "$repo")"

  # Compute completed_at for terminal statuses
  local completed_clause="completed_at"
  case "$new_status" in
    merged|abandoned)
      completed_clause="COALESCE(completed_at, '${now}')" ;;
  esac

  sqlite3 "$db" <<SQL
BEGIN TRANSACTION;
UPDATE tasks
  SET status     = '${new_status}',
      completed_at = ${completed_clause},
      updated_at = '${now}'
  WHERE id = '${task_id}';
INSERT INTO task_events(task_id, event_type, old_status, new_status, message, created_at)
  VALUES('${task_id}', 'status_changed', '${old_status}', '${new_status}', '${message}', '${now}');
COMMIT;
SQL
}

# =============================================================================
# sanitize_token — strip non-alnum to hyphens, collapse, trim
# =============================================================================

sanitize_token() {
  local value="${1:-task}"
  local max_len="${2:-56}"
  local token
  token="$(printf '%s' "$value" | sed 's/[^a-zA-Z0-9_.-]/-/g; s/--*/-/g; s/^-//; s/-$//')"
  [[ -z "$token" ]] && token="task"
  printf '%s' "${token:0:$max_len}"
}

# =============================================================================
# build_prompt — wrap raw prompt with Definition of Done footer
# =============================================================================

build_prompt() {
  local prompt="${1:?usage: build_prompt <prompt> <task_id> <branch> <base_branch>}"
  local task_id="${2:?}"
  local branch="${3:?}"
  local base_branch="${4:?}"

  cat <<EOF
${prompt}

IMPORTANT - Definition of Done:
1. Implement the task with minimal, correct changes.
2. Run project-relevant checks for changed scope.
3. Commit your changes with clear message.
4. Push branch: git push origin ${branch}
5. Create PR to ${base_branch}: gh pr create --base ${base_branch} --head ${branch} --fill
6. If UI changed, include screenshot markdown in PR body.
7. Print: AGENT_DONE TASK_ID=${task_id}

If blocked, print: AGENT_STUCK TASK_ID=${task_id} REASON=<short reason>
EOF
}

# =============================================================================
# resolve_spawn_notify_route — derive channel/target/account for new task
# =============================================================================
# Mirrors Python resolve_spawn_notify_route exactly.
# Args: explicit_session explicit_channel explicit_target explicit_account
# Outputs tab-separated: channel \t target \t account \t source_session_key

resolve_spawn_notify_route() {
  local explicit_session="${1:-}"
  local explicit_channel="${2:-}"
  local explicit_target="${3:-}"
  local explicit_account="${4:-}"

  explicit_channel="$(printf '%s' "$explicit_channel" | tr '[:upper:]' '[:lower:]')"

  # If explicit target provided, use it directly
  if [[ -n "$explicit_target" ]]; then
    local channel="${explicit_channel:-${CONF_NOTIFY_CHANNEL:-discord}}"
    local account="${explicit_account:-$CONF_NOTIFY_ACCOUNT}"
    printf '%s\t%s\t%s\t%s' "$channel" "$explicit_target" "$account" "$explicit_session"
    return
  fi

  # Auto-discover session key
  local session_key="$explicit_session"
  if [[ -z "$session_key" ]]; then
    # Check env vars
    local var
    for var in OPENCLAW_SESSION_KEY OPENCLAW_SESSIONKEY SESSION_KEY OPENCLAW_CONTEXT_SESSION_KEY; do
      local val="${!var:-}"
      if [[ -n "$val" ]]; then
        session_key="$val"
        break
      fi
    done
  fi
  if [[ -z "$session_key" ]]; then
    session_key="$(discover_recent_discord_session_key)" || session_key=""
  fi

  # Try to parse discord route from session key
  local derived=""
  if [[ -n "$session_key" ]]; then
    derived="$(parse_discord_route_from_session_key "$session_key" 2>/dev/null)" || derived=""
  fi

  if [[ -z "$derived" ]]; then
    printf '%s\t%s\t%s\t%s' \
      "$explicit_channel" "$explicit_target" "$explicit_account" \
      "${explicit_session:-$session_key}"
    return
  fi

  # Unpack derived route: channel \t target \t account \t source_session_key
  local d_channel d_target d_account d_session
  IFS=$'\t' read -r d_channel d_target d_account d_session <<< "$derived"

  [[ -n "$explicit_channel" ]] && d_channel="$explicit_channel"
  [[ -n "$explicit_target" ]]  && d_target="$explicit_target"
  if [[ -n "$explicit_account" ]]; then
    d_account="$explicit_account"
  elif [[ -z "$d_account" ]]; then
    d_account="$CONF_NOTIFY_ACCOUNT"
  fi

  printf '%s\t%s\t%s\t%s' "$d_channel" "$d_target" "$d_account" "$d_session"
}

# =============================================================================
# resolve_progress_settings — parse progress flags against config
# =============================================================================
# Args: explicit_interval_minutes no_progress
# Outputs tab-separated: enabled(0|1) \t interval_minutes

resolve_progress_settings() {
  local explicit_interval="${1:-}"
  local no_progress="${2:-false}"

  if [[ "$no_progress" == "true" ]]; then
    printf '0\t0'
    return
  fi

  if [[ -n "$explicit_interval" ]]; then
    local interval="$explicit_interval"
    (( interval < 0 )) && interval=0
    local enabled=0
    (( interval > 0 )) && enabled=1
    printf '%d\t%d' "$enabled" "$interval"
    return
  fi

  local interval="${CONF_PROGRESS_INTERVAL_MINUTES:-5}"
  (( interval < 0 )) && interval=0
  local enabled=0
  if [[ "${CONF_PROGRESS_ENABLED:-true}" == "true" ]] && (( interval > 0 )); then
    enabled=1
  fi
  printf '%d\t%d' "$enabled" "$interval"
}

# =============================================================================
# write_projection — regenerate active-tasks.json from DB
# =============================================================================

write_projection() {
  local repo="${1:?usage: write_projection <repo>}"
  local target
  target="$(openclaw_dir "$repo")/active-tasks.json"

  local _proj_query="SELECT t.id, t.tmux_session, t.driver, t.model, t.description, \
    t.repo_path, t.worktree_path, t.branch, t.started_at, t.created_at, t.status, \
    t.attempt_count, t.max_attempts, t.notify_on_ready, t.pr_number, t.last_error_reason, \
    COALESCE(c.pr_created,0) AS pr_created, COALESCE(c.branch_mergeable,0) AS branch_mergeable, \
    COALESCE(c.ci_passed,0) AS ci_passed, COALESCE(c.review_codex_passed,0) AS review_codex_passed, \
    COALESCE(c.review_claude_passed,0) AS review_claude_passed, \
    COALESCE(c.review_gemini_passed,0) AS review_gemini_passed, \
    COALESCE(c.ui_screenshot_present,0) AS ui_screenshot_present \
    FROM tasks t LEFT JOIN task_checks c ON c.task_id = t.id \
    WHERE t.cleaned_at IS NULL AND t.status NOT IN ('merged','abandoned') \
    ORDER BY datetime(t.created_at) ASC"

  if ! command -v jq >/dev/null 2>&1; then
    local rows
    rows="$(sql_json "$repo" "$_proj_query")" 2>/dev/null || rows="[]"
    printf '%s\n' "${rows:-[]}" > "$target"
    return
  fi

  sql_json "$repo" "$_proj_query" 2>/dev/null \
  | jq '[.[] | {
      id, tmuxSession: .tmux_session, agent: .driver, model, description,
      repo: .repo_path, worktree: .worktree_path, branch,
      startedAt: (.started_at // .created_at),
      status, attempts: .attempt_count, maxAttempts: .max_attempts,
      notifyOnComplete: (.notify_on_ready == 1), pr: .pr_number,
      checks: { prCreated: (.pr_created==1), branchMergeable: (.branch_mergeable==1),
        ciPassed: (.ci_passed==1), codexReviewPassed: (.review_codex_passed==1),
        claudeReviewPassed: (.review_claude_passed==1),
        geminiReviewPassed: (.review_gemini_passed==1),
        uiScreenshotPresent: (.ui_screenshot_present==1) },
      note: (.last_error_reason // "")
    }]' > "$target" 2>/dev/null || printf '[]\n' > "$target"
}

# =============================================================================
# cmd_init — initialize delivery database for a repo
# =============================================================================

cmd_init() {
  local repo=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo) repo="${2:?--repo requires a value}"; shift 2 ;;
      *)      die "Unknown flag: $1" ;;
    esac
  done

  [[ -n "$repo" ]] || die "Missing required --repo flag"
  repo="$(ensure_repo "$repo")"
  ensure_db "$repo"

  local db
  db="$(db_path "$repo")"
  printf 'Initialized delivery database at %s\n' "$db"
}

# =============================================================================
# cmd_spawn — create worktree, launch tmux session, persist task
# =============================================================================
# Ported from Python cmd_task_spawn. The big one.

cmd_spawn() {
  local repo="" task_id="" driver_req="auto" prompt="" prompt_file=""
  local source_session_key="" notify_channel="" notify_target="" notify_account=""
  local progress_every="" no_progress=false

  # -- Parse flags --
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo)                repo="${2:?--repo requires a value}";               shift 2 ;;
      --task-id)             task_id="${2:?--task-id requires a value}";          shift 2 ;;
      --driver)              driver_req="${2:?--driver requires a value}";        shift 2 ;;
      --prompt)              prompt="$2";                                        shift 2 ;;
      --prompt-file)         prompt_file="${2:?--prompt-file requires a value}";  shift 2 ;;
      --source-session-key)  source_session_key="$2";                            shift 2 ;;
      --notify-channel)      notify_channel="$2";                                shift 2 ;;
      --notify-target)       notify_target="$2";                                 shift 2 ;;
      --notify-account)      notify_account="$2";                                shift 2 ;;
      --progress-every)      progress_every="$2";                                shift 2 ;;
      --no-progress)         no_progress=true;                                   shift ;;
      *)                     die "Unknown flag: $1" ;;
    esac
  done

  # -- Validate required inputs --
  [[ -n "$repo" ]]    || die "Missing required --repo flag"
  [[ -n "$task_id" ]] || die "Missing required --task-id flag"

  # Exactly one of --prompt or --prompt-file
  if [[ -n "$prompt" && -n "$prompt_file" ]]; then
    die "Use either --prompt or --prompt-file, not both"
  fi
  if [[ -z "$prompt" && -z "$prompt_file" ]]; then
    die "Prompt is required (--prompt or --prompt-file)"
  fi

  # Read prompt file if specified
  local raw_prompt="$prompt"
  if [[ -n "$prompt_file" ]]; then
    local resolved_file
    resolved_file="$(cd "$(dirname "$prompt_file")" 2>/dev/null && pwd -P)/$(basename "$prompt_file")"
    [[ -f "$resolved_file" ]] || die "Prompt file not found: $prompt_file"
    raw_prompt="$(cat "$resolved_file")"
  fi

  # -- Initialize --
  repo="$(ensure_repo "$repo")"
  ensure_db "$repo"
  load_config "$repo"

  # Sanitize task_id
  task_id="$(sanitize_token "$task_id" 80)"

  # -- Resolve driver --
  local driver
  driver="$(resolve_driver "$driver_req" "$raw_prompt")"

  # -- Derive model and reasoning from config --
  local conf_model_var="CONF_DRIVER_${driver^^}_MODEL"
  # Normalize driver name for var lookup: gemini-cli → GEMINI_CLI
  conf_model_var="$(printf '%s' "$conf_model_var" | tr '-' '_')"
  local model="${!conf_model_var:-}"
  model="$(normalize_model "$driver" "$model")"

  local conf_reasoning_var="CONF_DRIVER_${driver^^}_REASONING"
  conf_reasoning_var="$(printf '%s' "$conf_reasoning_var" | tr '-' '_')"
  local reasoning="${!conf_reasoning_var:-high}"

  # -- Compute paths --
  local base_branch
  base_branch="$(detect_base_branch "$repo")"
  local worktree_base="${CONF_WORKTREE_BASE:-${HOME}/code-worktrees/$(basename "$repo")}"
  local branch="swarm/${task_id}"
  local session
  session="$(sanitize_token "swarm-$(sanitize_token "$(basename "$repo")" 20)-$(sanitize_token "$task_id" 28)" 60)"
  local log_file
  log_file="$(openclaw_dir "$repo")/logs/${task_id}.log"

  # -- Build enhanced prompt --
  local full_prompt
  full_prompt="$(build_prompt "$raw_prompt" "$task_id" "$branch" "$base_branch")"

  # -- Resolve notify route --
  local route_line
  route_line="$(resolve_spawn_notify_route "$source_session_key" "$notify_channel" "$notify_target" "$notify_account")"
  local r_channel r_target r_account r_session
  IFS=$'\t' read -r r_channel r_target r_account r_session <<< "$route_line"

  # -- Resolve progress settings --
  local progress_line
  progress_line="$(resolve_progress_settings "$progress_every" "$no_progress")"
  local progress_enabled progress_interval
  IFS=$'\t' read -r progress_enabled progress_interval <<< "$progress_line"

  # -- Create worktree --
  local worktree_path
  worktree_path="$(create_worktree "$repo" "$branch" "$worktree_base")" \
    || die "Failed to create worktree for task ${task_id}"

  # -- Build driver command --
  local driver_cmd
  driver_cmd="$(build_driver_command "$driver" "$full_prompt" "$model" "$reasoning")"

  # -- Launch tmux session --
  # Kill stale session if exists
  tmux kill-session -t "$session" 2>/dev/null || true

  local wrapped_cmd
  wrapped_cmd="bash -lc $(printf '%q' "$driver_cmd")"
  if ! tmux new-session -d -s "$session" -c "$worktree_path" "$wrapped_cmd" 2>/dev/null; then
    # Cleanup worktree on tmux failure
    remove_worktree "$repo" "$worktree_path"
    die "Failed to start tmux session: ${session}"
  fi

  # Setup log file and pipe tmux output to it
  mkdir -p "$(dirname "$log_file")"
  touch "$log_file"
  tmux pipe-pane -t "$session" -o "cat >> $(printf '%q' "$log_file")" 2>/dev/null || true

  # -- Persist to database --
  local now
  now="$(now_iso)"
  local db
  db="$(db_path "$repo")"

  local title="Task ${task_id}"
  local description
  description="$(printf '%s' "$raw_prompt" | head -1)"
  [[ -z "$description" ]] && description="$task_id"

  # Determine attempt count (increment if re-spawning)
  local prev_attempts
  prev_attempts="$(sql "$repo" "SELECT attempt_count FROM tasks WHERE id = '${task_id}';" 2>/dev/null)" || prev_attempts=""
  local attempts=1
  if [[ -n "$prev_attempts" ]]; then
    attempts=$(( prev_attempts + 1 ))
  fi

  # Escape single quotes in prompt for SQL
  local safe_prompt safe_desc safe_title
  safe_prompt="$(printf '%s' "$raw_prompt" | sed "s/'/''/g")"
  safe_desc="$(printf '%s' "$description" | sed "s/'/''/g")"
  safe_title="$(printf '%s' "$title" | sed "s/'/''/g")"

  sqlite3 "$db" <<SQL
BEGIN TRANSACTION;

INSERT INTO tasks(
  id, title, description, status, priority, driver, model,
  repo_path, base_branch, branch, worktree_path, tmux_session,
  log_path, prompt_text, attempt_count, max_attempts,
  notify_on_ready, notify_channel, notify_target, notify_account, source_session_key,
  progress_notify_enabled, progress_notify_interval_minutes, last_progress_notified_at,
  ci_status, pr_number, pr_url,
  mergeable, ui_change_detected, last_error_code,
  last_error_reason, last_error_evidence,
  created_at, started_at, completed_at, updated_at
) VALUES(
  '${task_id}', '${safe_title}', '${safe_desc}', '${STATUS_RUNNING}', 'medium',
  '${driver}', '${model}', '${repo}', '${base_branch}',
  '${branch}', '${worktree_path}', '${session}',
  '${log_file}', '${safe_prompt}',
  ${attempts}, ${CONF_MAX_ATTEMPTS:-3},
  $([ "${CONF_NOTIFY_ON_READY:-true}" = "true" ] && echo 1 || echo 0),
  '${r_channel}', '${r_target}', '${r_account}', '${r_session}',
  ${progress_enabled}, ${progress_interval}, NULL,
  NULL, NULL, NULL,
  NULL, NULL, NULL,
  NULL, NULL,
  '${now}', '${now}', NULL, '${now}'
)
ON CONFLICT(id) DO UPDATE SET
  title = excluded.title,
  description = excluded.description,
  status = excluded.status,
  driver = excluded.driver,
  model = excluded.model,
  repo_path = excluded.repo_path,
  base_branch = excluded.base_branch,
  branch = excluded.branch,
  worktree_path = excluded.worktree_path,
  tmux_session = excluded.tmux_session,
  log_path = excluded.log_path,
  prompt_text = excluded.prompt_text,
  attempt_count = excluded.attempt_count,
  max_attempts = excluded.max_attempts,
  notify_on_ready = excluded.notify_on_ready,
  notify_channel = excluded.notify_channel,
  notify_target = excluded.notify_target,
  notify_account = excluded.notify_account,
  source_session_key = excluded.source_session_key,
  progress_notify_enabled = excluded.progress_notify_enabled,
  progress_notify_interval_minutes = excluded.progress_notify_interval_minutes,
  last_progress_notified_at = NULL,
  ci_status = NULL,
  pr_number = NULL,
  pr_url = NULL,
  mergeable = NULL,
  ui_change_detected = NULL,
  last_error_code = NULL,
  last_error_reason = NULL,
  last_error_evidence = NULL,
  started_at = excluded.started_at,
  completed_at = NULL,
  cleaned_at = NULL,
  updated_at = excluded.updated_at;

INSERT INTO task_checks(
  task_id, pr_created, branch_mergeable, ci_passed,
  review_codex_passed, review_claude_passed, review_gemini_passed,
  ui_screenshot_present, updated_at
) VALUES('${task_id}', 0, 0, 0, 0, 0, 0, 0, '${now}')
ON CONFLICT(task_id) DO NOTHING;

INSERT INTO task_attempts(
  task_id, attempt_no, driver, model, tmux_session, prompt_snapshot, started_at
) VALUES('${task_id}', ${attempts}, '${driver}', '${model}', '${session}', '${safe_prompt}', '${now}');

INSERT INTO task_events(
  task_id, event_type, old_status, new_status, message, payload, created_at
) VALUES(
  '${task_id}', 'spawned', '${STATUS_QUEUED}', '${STATUS_RUNNING}', 'Task spawned',
  '{"driver":"${driver}","notifyChannel":"${r_channel}","notifyTarget":"${r_target}","notifyAccount":"${r_account}","sourceSessionKey":"${r_session}","progressEnabled":${progress_enabled},"progressEveryMinutes":${progress_interval}}',
  '${now}'
);

COMMIT;
SQL

  # Update projection
  write_projection "$repo"

  # -- Print summary --
  printf 'task_id: %s\n'   "$task_id"
  printf 'driver: %s\n'    "$driver"
  printf 'model: %s\n'     "${model:-<driver-default>}"
  printf 'session: %s\n'   "$session"
  printf 'branch: %s\n'    "$branch"
  printf 'worktree: %s\n'  "$worktree_path"
  printf 'log: %s\n'       "$log_file"
  printf 'notify_channel: %s\n' "${r_channel:-<none>}"
  printf 'notify_target: %s\n'  "${r_target:-<none>}"
  [[ -n "$r_session" ]] && printf 'source_session: %s\n' "$r_session"
  if (( progress_enabled )); then
    printf 'progress_updates: enabled\n'
    printf 'progress_every_minutes: %d\n' "$progress_interval"
  else
    printf 'progress_updates: disabled\n'
  fi
  printf 'status: %s\n' "$STATUS_RUNNING"
}

# =============================================================================
# cmd_status — display task status (text or JSON)
# =============================================================================

cmd_status() {
  local repo="" format="text" task_id=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo)     repo="${2:?--repo requires a value}";     shift 2 ;;
      --format)   format="${2:?--format requires a value}";  shift 2 ;;
      --task-id)  task_id="${2:?--task-id requires a value}"; shift 2 ;;
      *)          die "Unknown flag: $1" ;;
    esac
  done

  [[ -n "$repo" ]] || die "Missing required --repo flag"
  repo="$(ensure_repo "$repo")"
  ensure_db "$repo"

  local query
  if [[ -n "$task_id" ]]; then
    task_id="$(sanitize_token "$task_id" 80)"
    query="SELECT t.id, t.status, t.driver, t.branch, t.attempt_count, t.max_attempts, t.updated_at, t.pr_number
           FROM tasks t WHERE t.id = '${task_id}'"
  else
    query="SELECT t.id, t.status, t.driver, t.branch, t.attempt_count, t.max_attempts, t.updated_at, t.pr_number
           FROM tasks t
           WHERE t.status NOT IN ('merged','abandoned')
             AND t.cleaned_at IS NULL
           ORDER BY datetime(t.created_at) DESC"
  fi

  if [[ "$format" == "json" ]]; then
    if [[ -n "$task_id" ]]; then
      sql_json "$repo" \
        "SELECT t.*, \
                COALESCE(c.pr_created,0) AS check_pr_created, \
                COALESCE(c.branch_mergeable,0) AS check_branch_mergeable, \
                COALESCE(c.ci_passed,0) AS check_ci_passed, \
                COALESCE(c.review_codex_passed,0) AS check_review_codex, \
                COALESCE(c.review_claude_passed,0) AS check_review_claude, \
                COALESCE(c.review_gemini_passed,0) AS check_review_gemini, \
                COALESCE(c.ui_screenshot_present,0) AS check_ui_screenshot \
         FROM tasks t \
         LEFT JOIN task_checks c ON c.task_id = t.id \
         WHERE t.id = '${task_id}'"
    else
      sql_json "$repo" \
        "SELECT t.*, \
                COALESCE(c.pr_created,0) AS check_pr_created, \
                COALESCE(c.branch_mergeable,0) AS check_branch_mergeable, \
                COALESCE(c.ci_passed,0) AS check_ci_passed, \
                COALESCE(c.review_codex_passed,0) AS check_review_codex, \
                COALESCE(c.review_claude_passed,0) AS check_review_claude, \
                COALESCE(c.review_gemini_passed,0) AS check_review_gemini, \
                COALESCE(c.ui_screenshot_present,0) AS check_ui_screenshot \
         FROM tasks t \
         LEFT JOIN task_checks c ON c.task_id = t.id \
         ORDER BY datetime(t.created_at) DESC"
    fi
    return
  fi

  # Text format — tabular output
  local rows
  rows="$(sql "$repo" "$query")"

  printf '%-30s %-26s %-12s %-10s %-8s %s\n' \
    "ID" "STATUS" "DRIVER" "ATTEMPTS" "PR" "BRANCH"
  printf '%s\n' "$(printf '%0.s-' {1..96})"

  if [[ -z "$rows" ]]; then
    printf 'No tasks found.\n'
    return
  fi

  local tid tstatus tdriver tbranch tattempts tmax tupdated tpr
  while IFS=$'\t' read -r tid tstatus tdriver tbranch tattempts tmax tupdated tpr; do
    [[ -z "$tid" ]] && continue
    printf '%-30s %-26s %-12s %s/%-7s %-8s %s\n' \
      "$tid" "$tstatus" "$tdriver" "$tattempts" "$tmax" "${tpr:--}" "${tbranch:--}"
  done <<< "$rows"
}

# =============================================================================
# cmd_redirect — send a message to a running task's tmux session
# =============================================================================

cmd_redirect() {
  local repo="" task_id="" message=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo)     repo="${2:?--repo requires a value}";     shift 2 ;;
      --task-id)  task_id="${2:?--task-id requires a value}"; shift 2 ;;
      --message)  message="${2:?--message requires a value}"; shift 2 ;;
      *)          die "Unknown flag: $1" ;;
    esac
  done

  [[ -n "$repo" ]]    || die "Missing required --repo flag"
  [[ -n "$task_id" ]] || die "Missing required --task-id flag"
  [[ -n "$message" ]] || die "Missing required --message flag"

  repo="$(ensure_repo "$repo")"
  ensure_db "$repo"
  task_id="$(sanitize_token "$task_id" 80)"

  # Fetch task row
  local row
  row="$(sql "$repo" "SELECT status, tmux_session FROM tasks WHERE id = '${task_id}';")"
  [[ -n "$row" ]] || die "Task not found: ${task_id}"

  local status session
  IFS=$'\t' read -r status session <<< "$row"

  [[ -n "$session" ]] || die "Task ${task_id} has no tmux session"

  # Verify tmux session exists
  if ! tmux has-session -t "$session" 2>/dev/null; then
    die "tmux session not found: ${session}"
  fi

  # Send message to tmux
  tmux send-keys -t "$session" "$message" Enter

  # Record event
  local now
  now="$(now_iso)"
  sql "$repo" \
    "INSERT INTO task_events(task_id, event_type, old_status, new_status, message, created_at) \
     VALUES('${task_id}', 'redirect', '${status}', '${status}', '$(printf '%s' "$message" | sed "s/'/''/g")', '${now}');"

  # Update projection
  write_projection "$repo"

  printf 'task_id: %s\n' "$task_id"
  printf 'redirect: ok\n'
}

# =============================================================================
# cmd_kill — kill tmux session, transition to abandoned/failed
# =============================================================================

cmd_kill() {
  local repo="" task_id=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo)     repo="${2:?--repo requires a value}";     shift 2 ;;
      --task-id)  task_id="${2:?--task-id requires a value}"; shift 2 ;;
      *)          die "Unknown flag: $1" ;;
    esac
  done

  [[ -n "$repo" ]]    || die "Missing required --repo flag"
  [[ -n "$task_id" ]] || die "Missing required --task-id flag"

  repo="$(ensure_repo "$repo")"
  ensure_db "$repo"
  load_config "$repo"
  task_id="$(sanitize_token "$task_id" 80)"

  # Fetch task row
  local row
  row="$(sql "$repo" "SELECT status, tmux_session FROM tasks WHERE id = '${task_id}';")"
  [[ -n "$row" ]] || die "Task not found: ${task_id}"

  local old_status session
  IFS=$'\t' read -r old_status session <<< "$row"

  # Kill tmux session if alive
  if [[ -n "$session" ]] && tmux has-session -t "$session" 2>/dev/null; then
    tmux kill-session -t "$session" 2>/dev/null || true
  fi

  # Transition to appropriate terminal/error state
  if [[ "$old_status" != "$STATUS_MERGED" && "$old_status" != "$STATUS_ABANDONED" ]]; then
    local new_status="$STATUS_ABANDONED"
    local reason="Task killed manually"

    if [[ "$old_status" == "$STATUS_RUNNING" ]]; then
      new_status="$STATUS_FAILED"
      reason="Task killed manually"
    elif [[ "$old_status" == "$STATUS_PR_CREATED" \
         || "$old_status" == "$STATUS_CI_FAILED" \
         || "$old_status" == "$STATUS_CI_PASSED" \
         || "$old_status" == "$STATUS_REVIEW_CHANGES" \
         || "$old_status" == "$STATUS_READY" ]]; then
      new_status="$STATUS_ABANDONED"
      reason="Task killed after PR stage"
    fi

    transition_task "$repo" "$task_id" "$old_status" "$new_status" "$reason"
  fi

  # Mark error metadata
  local now
  now="$(now_iso)"
  sql "$repo" \
    "UPDATE tasks SET last_error_code = 'killed', last_error_reason = 'Manually terminated', updated_at = '${now}' WHERE id = '${task_id}';"

  # Record kill event
  sql "$repo" \
    "INSERT INTO task_events(task_id, event_type, old_status, new_status, message, created_at) \
     VALUES('${task_id}', 'killed', '${old_status}', '${old_status}', 'Manual kill', '${now}');"

  # Update projection
  write_projection "$repo"

  printf 'task_id: %s\n' "$task_id"
  printf 'killed: ok\n'
}
