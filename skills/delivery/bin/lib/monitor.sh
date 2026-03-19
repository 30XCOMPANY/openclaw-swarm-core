#!/usr/bin/env bash
# =============================================================================
# monitor.sh — Deterministic inspection loop with evidence-driven retry
# =============================================================================
# [INPUT]:  common.sh (STATUS_*, CONF_*, sql, sql_json, ensure_repo, ensure_db,
#           load_config, now_iso, db_path, openclaw_dir, die, sanitize_token),
#           state.sh (check_transition, transition_task, write_projection,
#           build_prompt, TRANSITIONS),
#           drivers.sh (build_driver_command, normalize_model, check_driver_available),
#           git-ops.sh (create_worktree, remove_worktree, check_ci_status,
#           detect_ui_change),
#           notify.sh (send_status_notification, send_progress_notification)
# [OUTPUT]: cmd_monitor — the single top-level inspection loop entrypoint
# [POS]:   Monitor subsystem; invoked by bin/delivery entrypoint as `monitor`
#          subcommand. Reads active tasks, drives state transitions,
#          handles evidence-driven retry, flushes notifications.
# [PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
# =============================================================================
[[ -n "${_MONITOR_SH_LOADED:-}" ]] && return 0
readonly _MONITOR_SH_LOADED=1

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
source "${SCRIPT_DIR}/common.sh"   # shellcheck source=common.sh
source "${SCRIPT_DIR}/state.sh"    # shellcheck source=state.sh
source "${SCRIPT_DIR}/drivers.sh"  # shellcheck source=drivers.sh
source "${SCRIPT_DIR}/git-ops.sh"  # shellcheck source=git-ops.sh
source "${SCRIPT_DIR}/notify.sh"   # shellcheck source=notify.sh

readonly MAX_EVIDENCE_LEN=1800
readonly LOG_TAIL_BYTES=12000

# -- _read_log_tail <path> [max_bytes] — grab last N bytes of log file --------
_read_log_tail() {
  local log_path="${1:-}" max_bytes="${2:-$LOG_TAIL_BYTES}"
  [[ -z "$log_path" || ! -f "$log_path" ]] && return 0
  local size
  size="$(wc -c < "$log_path" 2>/dev/null)" || return 0
  size="${size// /}"
  if (( size > max_bytes )); then
    tail -c "$max_bytes" "$log_path" 2>/dev/null || true
  else
    cat "$log_path" 2>/dev/null || true
  fi
}

# -- _classify_non_retryable <log_tail> — detect permanent failures -----------
# Prints: <code>\t<reason>  or returns 1 if retryable
_classify_non_retryable() {
  local log_tail="${1:-}"
  [[ -z "$log_tail" ]] && return 1
  local text
  text="$(printf '%s' "$log_tail" | tr '[:upper:]' '[:lower:]')"
  if [[ "$text" == *"agent_stuck"* && "$text" == *"origin_not_github_remote"* ]]; then
    printf '%s\t%s' "non_retryable_remote" "Origin remote is not GitHub; cannot create PR"; return 0
  fi
  if [[ "$text" == *"gh pr create"* ]] \
    && { [[ "$text" == *"not github host"* ]] || [[ "$text" == *"local path"* ]]; }; then
    printf '%s\t%s' "non_retryable_remote" "Repository remote is not PR-capable for gh CLI"; return 0
  fi
  if [[ "$text" == *"please set an auth method"* && "$text" == *"gemini"* ]]; then
    printf '%s\t%s' "non_retryable_auth_missing" "Gemini auth is missing"; return 0
  fi
  if [[ "$text" == *"model not found"* || "$text" == *"providermodelnotfounderror"* ]]; then
    printf '%s\t%s' "non_retryable_model_not_found" "Model unavailable for this driver/provider"; return 0
  fi
  return 1
}

# -- _screenshot_present <body> — check PR body for image/screenshot ----------
_screenshot_present() {
  local body="${1:-}"
  [[ -z "$body" ]] && return 1
  printf '%s' "$body" | grep -qE '!\[[^\]]*\]\([^\)]+\)' && return 0
  printf '%s' "$body" | grep -qi 'screenshot' && return 0
  return 1
}

# -- _gh_json <repo> <cmd...> — run gh CLI, return JSON -----------------------
_gh_json() {
  local repo="${1:?}"; shift
  local stdout
  stdout="$("$@" 2>/dev/null)" || { printf 'null'; return 1; }
  stdout="${stdout## }"; stdout="${stdout%% }"
  [[ -z "$stdout" ]] && { printf 'null'; return 1; }
  printf '%s' "$stdout"
}

# -- _review_gates <json> — compute per-reviewer gate flags -------------------
# Prints: codex_passed \t claude_passed \t gemini_passed \t changes_requested
_review_gates() {
  local json_out="${1:-}"
  command -v jq >/dev/null 2>&1 || { printf '0\t0\t0\t0'; return; }

  local decision
  decision="$(printf '%s' "$json_out" | jq -r '.reviewDecision // "NONE"' 2>/dev/null)"
  decision="${decision^^}"
  local changes_requested=0
  [[ "$decision" == "CHANGES_REQUESTED" ]] && changes_requested=1
  local codex_passed=0 claude_passed=0 gemini_passed=0

  local approved_logins
  approved_logins="$(printf '%s' "$json_out" | jq -r '.reviews // [] | .[] | select(.state == "APPROVED") | .author.login // "" | ascii_downcase' 2>/dev/null)" || approved_logins=""
  local login
  while IFS= read -r login; do
    [[ -z "$login" ]] && continue
    [[ "$login" == *codex* || "$login" == *openai* ]]       && codex_passed=1
    [[ "$login" == *claude* || "$login" == *anthropic* ]]    && claude_passed=1
    [[ "$login" == *gemini* || "$login" == *google* ]]       && gemini_passed=1
  done <<< "$approved_logins"

  if [[ "$decision" == "APPROVED" ]]; then
    for req in $CONF_REQUIRED_REVIEWS; do
      case "$req" in
        codex)  (( codex_passed  == 0 )) && codex_passed=1  ;;
        claude) (( claude_passed == 0 )) && claude_passed=1 ;;
        gemini) (( gemini_passed == 0 )) && gemini_passed=1 ;;
      esac
    done
  fi
  printf '%d\t%d\t%d\t%d' "$codex_passed" "$claude_passed" "$gemini_passed" "$changes_requested"
}

# -- _all_gates_pass <repo> <task_id> — check all DoD gates ------------------
_all_gates_pass() {
  local repo="${1:?}" task_id="${2:?}"
  local checks_row
  checks_row="$(sql "$repo" "SELECT pr_created, branch_mergeable, ci_passed, review_codex_passed, review_claude_passed, review_gemini_passed, ui_screenshot_present FROM task_checks WHERE task_id = '${task_id}';")"
  [[ -z "$checks_row" ]] && return 1
  local pr_created branch_mergeable ci_passed r_codex r_claude r_gemini ui_screenshot
  IFS=$'\t' read -r pr_created branch_mergeable ci_passed r_codex r_claude r_gemini ui_screenshot <<< "$checks_row"
  (( pr_created ))       || return 1
  (( branch_mergeable )) || return 1
  (( ci_passed ))        || return 1
  for req in $CONF_REQUIRED_REVIEWS; do
    case "$req" in
      codex)  (( r_codex  )) || return 1 ;;
      claude) (( r_claude )) || return 1 ;;
      gemini) (( r_gemini )) || return 1 ;;
    esac
  done
  local ui_changed
  ui_changed="$(sql "$repo" "SELECT COALESCE(ui_change_detected, 0) FROM tasks WHERE id = '${task_id}';")"
  if (( ui_changed )) && ! (( ui_screenshot )); then return 1; fi
  return 0
}

# -- _update_checks <repo> <task_id> <key=val...> — batch UPDATE task_checks --
_update_checks() {
  local repo="${1:?}" task_id="${2:?}"; shift 2
  local sets="" now; now="$(now_iso)"
  while [[ $# -gt 0 ]]; do
    sets="${sets:+${sets}, }${1%%=*} = ${1#*=}"; shift
  done
  [[ -z "$sets" ]] && return 0
  sql "$repo" "UPDATE task_checks SET ${sets}, updated_at = '${now}' WHERE task_id = '${task_id}';"
}

# -- _safe_transition — transition with legality guard ------------------------
_safe_transition() {
  local repo="${1:?}" task_id="${2:?}" old="${3:?}" new="${4:?}" msg="${5:-}"
  [[ "$old" == "$new" ]] && return 0
  local allowed="${TRANSITIONS[$old]:-}" target found=false
  for target in $allowed; do [[ "$target" == "$new" ]] && found=true && break; done
  $found || return 1
  transition_task "$repo" "$task_id" "$old" "$new" "$msg"
}

# -- _ensure_pr_created — step running → pr_created if needed -----------------
_ensure_pr_created() {
  local repo="${1:?}" task_id="${2:?}" current_ref="${3:?}"
  local current="${!current_ref}"
  if [[ "$current" == "$STATUS_RUNNING" ]]; then
    _safe_transition "$repo" "$task_id" "$STATUS_RUNNING" "$STATUS_PR_CREATED" "PR detected"
    eval "${current_ref}='${STATUS_PR_CREATED}'"
  fi
}

# =============================================================================
# _monitor_one — inspect a single task and drive its state forward
# =============================================================================
_monitor_one() {
  local repo="${1:?}" task_id="${2:?}" status="${3:?}" session="${4:-}" branch="${5:-}" log_path="${6:-}"
  local tmux_alive=false
  [[ -n "$session" ]] && tmux has-session -t "$session" 2>/dev/null && tmux_alive=true

  # -- Discover PR --
  local pr_json="null"
  if [[ -n "$branch" ]]; then
    local remote_url
    remote_url="$(git -C "$repo" remote get-url origin 2>/dev/null)" || remote_url=""
    [[ -n "$remote_url" ]] && pr_json="$(_gh_json "$repo" gh pr list --repo "$remote_url" --state all --head "$branch" --json "number,url,state")"
  fi
  local pr_number="" pr_url="" pr_state=""
  if command -v jq >/dev/null 2>&1 && [[ "$pr_json" != "null" ]]; then
    local pr_count
    pr_count="$(printf '%s' "$pr_json" | jq 'if type == "array" then length else 0 end' 2>/dev/null)" || pr_count=0
    if (( pr_count > 0 )); then
      pr_number="$(printf '%s' "$pr_json" | jq -r '.[0].number // ""' 2>/dev/null)"
      pr_url="$(printf '%s' "$pr_json" | jq -r '.[0].url // ""' 2>/dev/null)"
      pr_state="$(printf '%s' "$pr_json" | jq -r '.[0].state // "" | ascii_upcase' 2>/dev/null)"
    fi
  fi

  # -- No PR found --
  if [[ -z "$pr_number" ]]; then
    if [[ "$status" == "$STATUS_RUNNING" ]] && ! $tmux_alive; then
      local log_tail; log_tail="$(_read_log_tail "$log_path")"
      local nr_line=""; nr_line="$(_classify_non_retryable "$log_tail")" || nr_line=""
      if [[ -n "$nr_line" ]]; then
        local nr_code nr_reason; IFS=$'\t' read -r nr_code nr_reason <<< "$nr_line"
        local safe_ev; safe_ev="$(printf '%s' "$log_tail" | head -c 4000 | sed "s/'/''/g")"
        sql "$repo" "UPDATE tasks SET last_error_code='${nr_code}', last_error_reason='$(printf '%s' "$nr_reason" | sed "s/'/''/g")', last_error_evidence='${safe_ev}', updated_at='$(now_iso)' WHERE id='${task_id}';"
        transition_task "$repo" "$task_id" "$status" "$STATUS_ABANDONED" "$nr_reason"; return
      fi
      sql "$repo" "UPDATE tasks SET last_error_code='session_exited_no_pr', last_error_reason='Session exited before PR creation', updated_at='$(now_iso)' WHERE id='${task_id}';"
      transition_task "$repo" "$task_id" "$status" "$STATUS_FAILED" "Session exited before PR creation"
    fi
    return
  fi

  # -- PR found: persist metadata --
  local now; now="$(now_iso)"
  sql "$repo" "UPDATE tasks SET pr_number=${pr_number}, pr_url='${pr_url}', updated_at='${now}' WHERE id='${task_id}';"
  _update_checks "$repo" "$task_id" "pr_created=1"

  # -- PR merged → terminal --
  if [[ "$pr_state" == "MERGED" ]]; then
    if [[ "$status" != "$STATUS_MERGED" ]]; then
      if [[ "$status" == "$STATUS_READY" ]]; then
        transition_task "$repo" "$task_id" "$status" "$STATUS_MERGED" "PR merged"
      else
        local db; db="$(db_path "$repo")"
        sqlite3 "$db" "BEGIN; UPDATE tasks SET status='${STATUS_MERGED}', completed_at='${now}', updated_at='${now}' WHERE id='${task_id}'; INSERT INTO task_events(task_id,event_type,old_status,new_status,message,created_at) VALUES('${task_id}','status_changed','${status}','${STATUS_MERGED}','PR merged','${now}'); COMMIT;"
      fi
    fi; return
  fi

  # -- PR closed → abandoned --
  if [[ "$pr_state" == "CLOSED" ]]; then
    if [[ "$status" != "$STATUS_ABANDONED" ]]; then
      local allowed="${TRANSITIONS[$status]:-}"
      [[ " $allowed " == *" ${STATUS_ABANDONED} "* ]] && transition_task "$repo" "$task_id" "$status" "$STATUS_ABANDONED" "PR closed"
    fi; return
  fi

  # -- PR is open: inspect CI, reviews, mergeability --
  local remote_url; remote_url="$(git -C "$repo" remote get-url origin 2>/dev/null)" || remote_url=""
  local details_json="{}"
  [[ -n "$remote_url" ]] && { details_json="$(_gh_json "$repo" gh pr view "$pr_number" --repo "$remote_url" --json "state,mergeable,mergeStateStatus,reviewDecision,reviews,body")" || details_json="{}"; }

  local mergeable_raw="" merge_state="" branch_mergeable=0
  if command -v jq >/dev/null 2>&1; then
    mergeable_raw="$(printf '%s' "$details_json" | jq -r '.mergeable // "UNKNOWN"' 2>/dev/null)"; mergeable_raw="${mergeable_raw^^}"
    merge_state="$(printf '%s' "$details_json" | jq -r '.mergeStateStatus // ""' 2>/dev/null)"; merge_state="${merge_state^^}"
    [[ "$mergeable_raw" == "MERGEABLE" || "$merge_state" =~ ^(CLEAN|HAS_HOOKS|UNSTABLE)$ ]] && branch_mergeable=1
  fi

  local ci_status; ci_status="$(check_ci_status "$repo" "$pr_number")"
  local ci_passed=0; [[ "$ci_status" == "passing" ]] && ci_passed=1

  local ui_changed=0
  if [[ -n "$branch" ]]; then
    local base_branch; base_branch="$(sql "$repo" "SELECT base_branch FROM tasks WHERE id='${task_id}';")"
    [[ -z "$base_branch" ]] && base_branch="$CONF_BASE_BRANCH"
    detect_ui_change "$repo" "$branch" "$base_branch" 2>/dev/null && ui_changed=1
  fi
  local ui_screenshot=1
  if (( ui_changed )); then
    local pr_body=""; command -v jq >/dev/null 2>&1 && pr_body="$(printf '%s' "$details_json" | jq -r '.body // ""' 2>/dev/null)"
    _screenshot_present "$pr_body" || ui_screenshot=0
  fi

  local review_line; review_line="$(_review_gates "$details_json")"
  local r_codex r_claude r_gemini changes_requested
  IFS=$'\t' read -r r_codex r_claude r_gemini changes_requested <<< "$review_line"

  now="$(now_iso)"
  sql "$repo" "UPDATE tasks SET ci_status='${ci_status}', mergeable=${branch_mergeable}, ui_change_detected=${ui_changed}, updated_at='${now}' WHERE id='${task_id}';"
  _update_checks "$repo" "$task_id" "branch_mergeable=${branch_mergeable}" "ci_passed=${ci_passed}" \
    "review_codex_passed=${r_codex}" "review_claude_passed=${r_claude}" "review_gemini_passed=${r_gemini}" "ui_screenshot_present=${ui_screenshot}"

  # -- Status progression --
  local current; current="$(sql "$repo" "SELECT status FROM tasks WHERE id='${task_id}';")"
  [[ -z "$current" ]] && return

  if (( changes_requested )); then
    if [[ "$current" != "$STATUS_REVIEW_CHANGES" ]]; then
      _ensure_pr_created "$repo" "$task_id" current
      _safe_transition "$repo" "$task_id" "$current" "$STATUS_REVIEW_CHANGES" "Review requested changes"
    fi; return
  fi
  if [[ "$ci_status" == "failing" ]]; then
    _ensure_pr_created "$repo" "$task_id" current
    if [[ "$current" != "$STATUS_CI_FAILED" ]]; then
      _safe_transition "$repo" "$task_id" "$current" "$STATUS_CI_FAILED" "CI failed"
      local ci_ev; ci_ev="$(gh pr checks "$pr_number" --repo "$remote_url" 2>/dev/null | head -c 4000 | sed "s/'/''/g")" || ci_ev=""
      sql "$repo" "UPDATE tasks SET last_error_code='ci_failed', last_error_reason='CI checks failed', last_error_evidence='${ci_ev}', updated_at='$(now_iso)' WHERE id='${task_id}';"
    fi; return
  fi
  if [[ "$ci_status" == "passing" ]]; then
    _ensure_pr_created "$repo" "$task_id" current
    if [[ "$current" == "$STATUS_PR_CREATED" || "$current" == "$STATUS_CI_FAILED" ]]; then
      _safe_transition "$repo" "$task_id" "$current" "$STATUS_CI_PASSED" "CI passed"; current="$STATUS_CI_PASSED"
    fi
  fi
  if _all_gates_pass "$repo" "$task_id"; then
    current="$(sql "$repo" "SELECT status FROM tasks WHERE id='${task_id}';")"
    if [[ "$current" != "$STATUS_READY" && "$current" != "$STATUS_MERGED" && "$current" != "$STATUS_ABANDONED" ]]; then
      _ensure_pr_created "$repo" "$task_id" current
      _safe_transition "$repo" "$task_id" "$current" "$STATUS_READY" "All gates passed"
    fi
  fi
}

# =============================================================================
# _spawn_retry — relaunch task with evidence from previous failure
# =============================================================================
_spawn_retry() {
  local repo="${1:?}" task_id="${2:?}" evidence="${3:-}"
  local row; row="$(sql "$repo" "SELECT driver, model, branch, worktree_path, tmux_session, log_path, prompt_text, attempt_count, max_attempts, status, last_error_code FROM tasks WHERE id='${task_id}';")"
  [[ -z "$row" ]] && return 1

  local driver model branch worktree session log_path prompt attempts max_attempts t_status last_error_code
  IFS=$'\t' read -r driver model branch worktree session log_path prompt attempts max_attempts t_status last_error_code <<< "$row"

  # Non-retryable / max-attempts guards
  if [[ "$last_error_code" == non_retryable_* ]]; then
    _safe_transition "$repo" "$task_id" "$t_status" "$STATUS_ABANDONED" "Non-retryable: ${last_error_code}"; return 0
  fi
  if (( attempts >= max_attempts )); then
    [[ "$t_status" != "$STATUS_ABANDONED" ]] && {
      _safe_transition "$repo" "$task_id" "$t_status" "$STATUS_ABANDONED" "Max retries exceeded"
      sql "$repo" "UPDATE tasks SET last_error_code='max_retries_exceeded', last_error_reason='Max retries exceeded', updated_at='$(now_iso)' WHERE id='${task_id}';"
    }; return 0
  fi
  check_driver_available "$driver" || {
    sql "$repo" "UPDATE tasks SET last_error_code='retry_driver_unavailable', last_error_reason='Driver unavailable: ${driver}', updated_at='$(now_iso)' WHERE id='${task_id}';"
    return 1
  }

  local trimmed_ev; trimmed_ev="$(printf '%s' "$evidence" | head -c "$MAX_EVIDENCE_LEN")"
  local next_attempt=$(( attempts + 1 ))
  local retry_prompt="${prompt}

RETRY_CONTEXT:
Previous attempt failed with evidence:
${trimmed_ev}

Focus only on files relevant to this failure and complete DoD."

  local base_branch; base_branch="$(sql "$repo" "SELECT base_branch FROM tasks WHERE id='${task_id}';")"
  [[ -z "$base_branch" ]] && base_branch="$CONF_BASE_BRANCH"
  [[ -z "$branch" ]]   && branch="swarm/${task_id}"
  [[ -z "$worktree" ]]  && worktree="${CONF_WORKTREE_BASE}/${task_id}"
  [[ -z "$session" ]]   && session="$(sanitize_token "swarm-$(sanitize_token "$(basename "$repo")" 20)-$(sanitize_token "$task_id" 28)" 60)"
  [[ -z "$log_path" ]]  && log_path="$(openclaw_dir "$repo")/logs/${task_id}.log"

  # Kill stale session, rebuild worktree
  tmux has-session -t "$session" 2>/dev/null && tmux kill-session -t "$session" 2>/dev/null || true
  remove_worktree "$repo" "$worktree"
  git -C "$repo" branch -D "$branch" 2>/dev/null || true
  local wt_base; wt_base="$(dirname "$worktree")"
  worktree="$(create_worktree "$repo" "$branch" "$wt_base")" || {
    sql "$repo" "UPDATE tasks SET last_error_code='retry_worktree_failed', last_error_reason='Failed to create worktree for retry', updated_at='$(now_iso)' WHERE id='${task_id}';"
    return 1
  }

  local full_prompt; full_prompt="$(build_prompt "$retry_prompt" "$task_id" "$branch" "$base_branch")"
  local norm_model; norm_model="$(normalize_model "$driver" "$model")"
  local rv="CONF_DRIVER_${driver^^}_REASONING"; rv="$(printf '%s' "$rv" | tr '-' '_')"
  local reasoning="${!rv:-high}"
  local driver_cmd; driver_cmd="$(build_driver_command "$driver" "$full_prompt" "$norm_model" "$reasoning")"
  local wrapped_cmd; wrapped_cmd="bash -lc $(printf '%q' "$driver_cmd")"

  mkdir -p "$(dirname "$log_path")"; touch "$log_path"
  if ! tmux new-session -d -s "$session" -c "$worktree" "$wrapped_cmd" 2>/dev/null; then
    sql "$repo" "UPDATE tasks SET last_error_code='retry_tmux_failed', last_error_reason='Failed to start tmux for retry', updated_at='$(now_iso)' WHERE id='${task_id}';"
    return 1
  fi
  tmux pipe-pane -t "$session" -o "cat >> $(printf '%q' "$log_path")" 2>/dev/null || true

  local now; now="$(now_iso)"
  local safe_prompt; safe_prompt="$(printf '%s' "$retry_prompt" | sed "s/'/''/g")"
  local db; db="$(db_path "$repo")"
  sqlite3 "$db" <<SQL
BEGIN TRANSACTION;
UPDATE tasks SET status='${STATUS_RUNNING}', attempt_count=${next_attempt}, model='${norm_model}',
  prompt_text='${safe_prompt}', started_at='${now}', completed_at=NULL,
  branch='${branch}', worktree_path='${worktree}', tmux_session='${session}', log_path='${log_path}',
  last_error_code=NULL, last_error_reason=NULL, last_error_evidence=NULL, updated_at='${now}'
  WHERE id='${task_id}';
INSERT INTO task_attempts(task_id,attempt_no,driver,model,tmux_session,prompt_snapshot,started_at)
  VALUES('${task_id}',${next_attempt},'${driver}','${norm_model}','${session}','${safe_prompt}','${now}');
INSERT INTO task_events(task_id,event_type,old_status,new_status,message,created_at)
  VALUES('${task_id}','retry_spawned','${t_status}','${STATUS_RUNNING}','Automatic retry launched','${now}');
COMMIT;
SQL
  return 0
}

# =============================================================================
# Notification flush helpers
# =============================================================================
_flush_status_notifications() {
  local repo="${1:?}" sent=0
  local rows; rows="$(sql "$repo" \
    "SELECT t.id, t.status, t.driver, t.model, t.attempt_count, t.max_attempts,
            t.branch, t.pr_url, t.pr_number, t.last_error_reason,
            t.notify_on_ready, t.notify_channel, t.notify_target, t.notify_account, t.source_session_key
     FROM tasks t LEFT JOIN task_notifications n ON n.task_id=t.id AND n.status=t.status
     WHERE n.task_id IS NULL AND t.status IN ('${STATUS_READY}','${STATUS_MERGED}')
     ORDER BY datetime(t.updated_at) ASC")"
  [[ -z "$rows" ]] && { printf '0'; return; }
  local tid ts td tm ta tx tb tu tn te tor tc tt ta2 tsk
  while IFS=$'\t' read -r tid ts td tm ta tx tb tu tn te tor tc tt ta2 tsk; do
    [[ -z "$tid" ]] && continue
    send_status_notification "$repo" "$tid" "$ts" "$td" "$tm" "$ta" "$tx" "$tb" "$tu" "$tn" "$te" "" "$tor" "$tc" "$tt" "$ta2" "$tsk" && (( sent++ )) || true
  done <<< "$rows"
  printf '%d' "$sent"
}

_flush_progress_notifications() {
  local repo="${1:?}" sent=0
  local rows; rows="$(sql "$repo" \
    "SELECT id, status, driver, model, attempt_count, max_attempts,
            branch, pr_url, pr_number, ci_status, last_error_reason,
            progress_notify_enabled, progress_notify_interval_minutes,
            last_progress_notified_at, started_at, created_at,
            notify_channel, notify_target, notify_account, source_session_key
     FROM tasks
     WHERE status IN ('${STATUS_RUNNING}','${STATUS_PR_CREATED}','${STATUS_CI_FAILED}','${STATUS_CI_PASSED}','${STATUS_REVIEW_CHANGES}')
     ORDER BY datetime(updated_at) ASC")"
  [[ -z "$rows" ]] && { printf '0'; return; }
  local tid ts td tm ta tx tb tu tn tci te tpe tpi tpl tsa tc2 tnc tnt tna tnsk
  while IFS=$'\t' read -r tid ts td tm ta tx tb tu tn tci te tpe tpi tpl tsa tc2 tnc tnt tna tnsk; do
    [[ -z "$tid" ]] && continue
    send_progress_notification "$repo" "$tid" "$ts" "$td" "$tm" "$ta" "$tx" "$tb" "$tu" "$tn" "$tci" "$te" "$tpe" "$tpi" "$tpl" "$tsa" "$tc2" "$tnc" "$tnt" "$tna" "$tnsk" && (( sent++ )) || true
  done <<< "$rows"
  printf '%d' "$sent"
}

# =============================================================================
# cmd_monitor — top-level inspection loop (idempotent, cron-safe)
# =============================================================================
cmd_monitor() {
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
  load_config "$repo"

  local monitored=0 retries=0 notifications_sent=0 progress_sent=0

  # -- Phase 1: Inspect active tasks --
  local rows; rows="$(sql "$repo" \
    "SELECT id, status, tmux_session, branch, log_path FROM tasks
     WHERE status IN ('${STATUS_RUNNING}','${STATUS_PR_CREATED}','${STATUS_CI_FAILED}','${STATUS_CI_PASSED}','${STATUS_REVIEW_CHANGES}','${STATUS_READY}','${STATUS_QUEUED}')
     ORDER BY datetime(updated_at) ASC")"
  if [[ -n "$rows" ]]; then
    local tid tstatus tsession tbranch tlog
    while IFS=$'\t' read -r tid tstatus tsession tbranch tlog; do
      [[ -z "$tid" ]] && continue; (( monitored++ ))
      if [[ "$tstatus" == "$STATUS_QUEUED" ]]; then
        _safe_transition "$repo" "$tid" "$STATUS_QUEUED" "$STATUS_RUNNING" "Monitor safety net: queued to running" || true
        tstatus="$STATUS_RUNNING"
      fi
      _monitor_one "$repo" "$tid" "$tstatus" "$tsession" "$tbranch" "$tlog"
    done <<< "$rows"
  fi

  # -- Phase 2: Retry failed/ci_failed/review_changes tasks --
  local retry_rows; retry_rows="$(sql "$repo" \
    "SELECT id, status, attempt_count, max_attempts, last_error_reason, last_error_evidence, last_error_code FROM tasks
     WHERE status IN ('${STATUS_FAILED}','${STATUS_CI_FAILED}','${STATUS_REVIEW_CHANGES}')
     ORDER BY datetime(updated_at) ASC")"
  if [[ -n "$retry_rows" ]]; then
    local rtid rts rta rtx rtr rte rtc
    while IFS=$'\t' read -r rtid rts rta rtx rtr rte rtc; do
      [[ -z "$rtid" ]] && continue
      if (( rta >= rtx )); then
        [[ "$rts" != "$STATUS_ABANDONED" ]] && {
          _safe_transition "$repo" "$rtid" "$rts" "$STATUS_ABANDONED" "Max retries exceeded" || true
          sql "$repo" "UPDATE tasks SET last_error_code='max_retries_exceeded', last_error_reason='Max retries exceeded', updated_at='$(now_iso)' WHERE id='${rtid}';"
        }; continue
      fi
      local evidence="${rtr}"; [[ -z "$evidence" ]] && evidence="${rte}"; [[ -z "$evidence" ]] && evidence="status=${rts}"
      _spawn_retry "$repo" "$rtid" "$evidence" && (( retries++ ))
    done <<< "$retry_rows"
  fi

  # -- Phase 3: Flush notifications --
  notifications_sent="$(_flush_status_notifications "$repo")"
  progress_sent="$(_flush_progress_notifications "$repo")"

  # -- Phase 4: Write projection --
  write_projection "$repo"

  printf 'repo: %s\n' "$repo"
  printf 'monitored: %d\n' "$monitored"
  printf 'retries_launched: %d\n' "$retries"
  printf 'notifications_sent: %s\n' "$notifications_sent"
  printf 'progress_notifications_sent: %s\n' "$progress_sent"
}
