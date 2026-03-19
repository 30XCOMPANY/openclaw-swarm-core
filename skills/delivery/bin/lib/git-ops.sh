#!/usr/bin/env bash
# =============================================================================
# git-ops.sh — Git worktree, branch, PR, CI check, and cleanup operations
# =============================================================================
# [INPUT]:  common.sh (die, sql, ensure_repo, db_path, now_iso, openclaw_dir)
# [OUTPUT]: create_worktree, remove_worktree, create_pr, check_pr_status,
#           check_ci_status, check_review_status, detect_ui_change,
#           cmd_cleanup, cleanup_task_artifacts
# [POS]:   Git/PR/CI operations layer; consumed by spawn, monitor, cleanup commands
# [PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
# =============================================================================

# -- Guard against double-source --
[[ -n "${_GIT_OPS_SH_LOADED:-}" ]] && return 0
readonly _GIT_OPS_SH_LOADED=1

# -- Ensure common.sh is loaded --
SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# =============================================================================
# Constants — ported from Python UI_EXTENSIONS and UI_PATH_HINTS
# =============================================================================

readonly UI_EXTENSIONS=".tsx .jsx .css .scss .sass .less .html .vue .svelte"
readonly UI_PATH_HINTS="/client/ /web/ /frontend/ /ui/ /components/ /pages/ /styles/"

# =============================================================================
# Legacy cleanup targets — seeded scripts from old .openclaw/ layout
# =============================================================================

readonly LEGACY_SCRIPTS="spawn-agent.sh redirect-agent.sh kill-agent.sh check-agents.sh cleanup.sh status.sh run-agent.sh setup.sh AGENTS.md active-tasks.json"

# =============================================================================
# Worktree operations
# =============================================================================

# create_worktree <repo_path> <branch_name> <worktree_base>
#   Fetches base branch, cleans stale worktree/branch, creates fresh worktree.
#   Prints worktree path to stdout.
create_worktree() {
  local repo="${1:?usage: create_worktree <repo_path> <branch_name> <worktree_base>}"
  local branch="${2:?usage: create_worktree <repo_path> <branch_name> <worktree_base>}"
  local worktree_base="${3:?usage: create_worktree <repo_path> <branch_name> <worktree_base>}"

  local base_branch
  base_branch="$(detect_base_branch "$repo")"

  local task_id="${branch#swarm/}"
  local worktree_path="${worktree_base}/${task_id}"

  # Fetch latest base branch
  git -C "$repo" fetch origin "$base_branch" 2>/dev/null || true

  # Clean stale artifacts
  remove_worktree "$repo" "$worktree_path"
  git -C "$repo" branch -D "$branch" 2>/dev/null || true

  # Create worktree — try origin/<base> first, fall back to local <base>
  if ! git -C "$repo" worktree add -b "$branch" "$worktree_path" "origin/${base_branch}" 2>/dev/null; then
    if ! git -C "$repo" worktree add -b "$branch" "$worktree_path" "$base_branch" 2>/dev/null; then
      die "Failed to create worktree at ${worktree_path}"
    fi
  fi

  printf '%s' "$worktree_path"
}

# remove_worktree <repo_path> <worktree_path>
#   Force-removes worktree via git, then rm -rf as fallback.
remove_worktree() {
  local repo="${1:?usage: remove_worktree <repo_path> <worktree_path>}"
  local worktree="${2:?usage: remove_worktree <repo_path> <worktree_path>}"

  [[ -d "$worktree" ]] || return 0

  git -C "$repo" worktree remove "$worktree" --force 2>/dev/null || true

  # Fallback: nuke directory if git worktree remove didn't finish
  if [[ -d "$worktree" ]]; then
    rm -rf "$worktree"
  fi
}

# =============================================================================
# PR operations
# =============================================================================

# create_pr <repo_path> <worktree_path> <branch> <base_branch> <title> <body>
#   Pushes branch and creates a GitHub PR via gh CLI.
#   Prints: <pr_number>\t<pr_url>
create_pr() {
  local repo="${1:?usage: create_pr <repo_path> <worktree_path> <branch> <base_branch> <title> <body>}"
  local worktree="${2:?}"
  local branch="${3:?}"
  local base_branch="${4:?}"
  local title="${5:?}"
  local body="${6:-}"

  # Push the branch
  git -C "$worktree" push -u origin "$branch" 2>/dev/null \
    || die "Failed to push branch ${branch}"

  # Create PR via gh
  local pr_url
  pr_url="$(gh pr create \
    --repo "$(git -C "$repo" remote get-url origin)" \
    --base "$base_branch" \
    --head "$branch" \
    --title "$title" \
    --body "$body" 2>/dev/null)" \
    || die "Failed to create PR for branch ${branch}"

  # Extract PR number from URL (last path segment)
  local pr_number="${pr_url##*/}"

  printf '%s\t%s' "$pr_number" "$pr_url"
}

# =============================================================================
# PR / CI / Review status checks
# =============================================================================

# check_pr_status <repo_path> <pr_number>
#   Queries PR state via gh CLI.
#   Prints: <mergeable>\t<state>\t<ci_status>\t<review_decision>
check_pr_status() {
  local repo="${1:?usage: check_pr_status <repo_path> <pr_number>}"
  local pr_number="${2:?usage: check_pr_status <repo_path> <pr_number>}"

  local json_out
  json_out="$(gh pr view "$pr_number" \
    --repo "$(git -C "$repo" remote get-url origin)" \
    --json "state,mergeable,mergeStateStatus,reviewDecision" 2>/dev/null)" \
    || { printf 'UNKNOWN\tUNKNOWN\tpending\tNONE'; return 1; }

  local state mergeable merge_state review_decision
  state="$(printf '%s' "$json_out" | jq -r '.state // "UNKNOWN"')"
  mergeable="$(printf '%s' "$json_out" | jq -r '.mergeable // "UNKNOWN"')"
  merge_state="$(printf '%s' "$json_out" | jq -r '.mergeStateStatus // ""')"
  review_decision="$(printf '%s' "$json_out" | jq -r '.reviewDecision // "NONE"')"

  # Derive branch_mergeable same as Python logic
  local branch_mergeable="false"
  if [[ "${mergeable^^}" == "MERGEABLE" ]] \
    || [[ "${merge_state^^}" =~ ^(CLEAN|HAS_HOOKS|UNSTABLE)$ ]]; then
    branch_mergeable="true"
  fi

  local ci_status
  ci_status="$(check_ci_status "$repo" "$pr_number")"

  printf '%s\t%s\t%s\t%s' "$branch_mergeable" "$state" "$ci_status" "$review_decision"
}

# check_ci_status <repo_path> <pr_number>
#   Runs gh pr checks and classifies overall CI status.
#   Prints one of: passing, failing, pending
check_ci_status() {
  local repo="${1:?usage: check_ci_status <repo_path> <pr_number>}"
  local pr_number="${2:?usage: check_ci_status <repo_path> <pr_number>}"

  local json_out
  json_out="$(gh pr checks "$pr_number" \
    --repo "$(git -C "$repo" remote get-url origin)" \
    --json "state,name" 2>/dev/null)" \
    || { printf 'pending'; return 0; }

  # Empty or non-array → pending
  local count
  count="$(printf '%s' "$json_out" | jq 'length')" 2>/dev/null
  if [[ -z "$count" || "$count" == "0" ]]; then
    printf 'pending'
    return 0
  fi

  local states
  states="$(printf '%s' "$json_out" | jq -r '.[].state // "" | ascii_upcase')"

  # Classify per Python check_ci logic
  local line has_fail=false has_pending=false all_ok=true
  while IFS= read -r line; do
    case "${line}" in
      FAILURE|ERROR|CANCELLED|ACTION_REQUIRED|TIMED_OUT)
        has_fail=true; all_ok=false ;;
      PENDING|QUEUED|WAITING|IN_PROGRESS|REQUESTED)
        has_pending=true; all_ok=false ;;
      SUCCESS|SKIPPED|NEUTRAL)
        ;; # OK states
      *)
        all_ok=false ;;
    esac
  done <<< "$states"

  if $has_fail; then
    printf 'failing'
  elif $has_pending; then
    printf 'pending'
  elif $all_ok; then
    printf 'passing'
  else
    printf 'pending'
  fi
}

# check_review_status <repo_path> <pr_number>
#   Queries review decision via gh CLI.
#   Prints: <reviewDecision> (APPROVED | CHANGES_REQUESTED | REVIEW_REQUIRED | NONE)
check_review_status() {
  local repo="${1:?usage: check_review_status <repo_path> <pr_number>}"
  local pr_number="${2:?usage: check_review_status <repo_path> <pr_number>}"

  local json_out
  json_out="$(gh pr view "$pr_number" \
    --repo "$(git -C "$repo" remote get-url origin)" \
    --json "reviews,reviewDecision" 2>/dev/null)" \
    || { printf 'NONE'; return 1; }

  local decision
  decision="$(printf '%s' "$json_out" | jq -r '.reviewDecision // "NONE"')"

  printf '%s' "${decision:-NONE}"
}

# =============================================================================
# UI change detection
# =============================================================================

# detect_ui_change <repo_path> <branch> <base_branch>
#   Checks git diff for UI-related file changes.
#   Returns 0 if UI change detected, 1 otherwise.
detect_ui_change() {
  local repo="${1:?usage: detect_ui_change <repo_path> <branch> <base_branch>}"
  local branch="${2:?}"
  local base_branch="${3:?}"

  local diff_files
  diff_files="$(git -C "$repo" diff --name-only "origin/${base_branch}...${branch}" 2>/dev/null)" || true

  [[ -z "$diff_files" ]] && return 1

  local file ext lowered
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue

    # Check extension
    ext=".${file##*.}"
    ext="${ext,,}"  # lowercase
    for ui_ext in $UI_EXTENSIONS; do
      if [[ "$ext" == "$ui_ext" ]]; then
        return 0
      fi
    done

    # Check path hints
    lowered="/${file,,}"
    for hint in $UI_PATH_HINTS; do
      if [[ "$lowered" == *"$hint"* ]]; then
        return 0
      fi
    done
  done <<< "$diff_files"

  return 1
}

# =============================================================================
# Cleanup operations
# =============================================================================

# cleanup_task_artifacts <repo_path> <task_id> <tmux_session> <worktree_path> <branch>
#   Removes worktree, kills tmux session, deletes branch.
cleanup_task_artifacts() {
  local repo="${1:?usage: cleanup_task_artifacts <repo_path> <task_id> <session> <worktree> <branch>}"
  local task_id="${2:?}"
  local session="${3:-}"
  local worktree="${4:-}"
  local branch="${5:-}"

  # Kill tmux session if alive
  if [[ -n "$session" ]] && tmux has-session -t "$session" 2>/dev/null; then
    tmux kill-session -t "$session" 2>/dev/null || true
  fi

  # Remove worktree
  if [[ -n "$worktree" ]]; then
    remove_worktree "$repo" "$worktree"
  fi

  # Delete branch
  if [[ -n "$branch" ]]; then
    git -C "$repo" branch -D "$branch" 2>/dev/null || true
  fi
}

# cmd_cleanup [--repo <path>] [--legacy]
#   Cleanup command handler. Removes artifacts for terminal tasks.
cmd_cleanup() {
  local repo="" legacy=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo)   repo="${2:?--repo requires a value}"; shift 2 ;;
      --legacy) legacy=true; shift ;;
      *)        die "Unknown flag: $1" ;;
    esac
  done

  [[ -n "$repo" ]] || die "Missing required --repo flag"
  repo="$(ensure_repo "$repo")"
  ensure_db "$repo"

  # -- Legacy cleanup: remove old seeded scripts from .openclaw/ --
  if $legacy; then
    local oc
    oc="$(openclaw_dir "$repo")"
    local removed=0
    for target in $LEGACY_SCRIPTS; do
      if [[ -e "${oc}/${target}" ]]; then
        rm -f "${oc}/${target}"
        (( removed++ ))
      fi
    done
    printf 'repo: %s\nlegacy_removed: %d\n' "$repo" "$removed"
    return 0
  fi

  # -- Normal cleanup: process terminal tasks with cleaned_at IS NULL --
  local rows
  rows="$(sql "$repo" \
    "SELECT id, tmux_session, worktree_path, branch, status FROM tasks WHERE status IN ('${STATUS_MERGED}','${STATUS_ABANDONED}') AND cleaned_at IS NULL ORDER BY datetime(updated_at) ASC")"

  local cleaned=0

  if [[ -n "$rows" ]]; then
    local task_id session worktree branch status
    while IFS=$'\t' read -r task_id session worktree branch status; do
      [[ -z "$task_id" ]] && continue

      cleanup_task_artifacts "$repo" "$task_id" "$session" "$worktree" "$branch"

      local now
      now="$(now_iso)"
      sql "$repo" \
        "UPDATE tasks SET cleaned_at = '${now}', updated_at = '${now}' WHERE id = '${task_id}'"
      sql "$repo" \
        "INSERT INTO task_events(task_id, event_type, old_status, new_status, message, created_at) VALUES('${task_id}', 'cleaned', '${status}', '${status}', 'Cleanup completed', '${now}')"

      (( cleaned++ ))
    done <<< "$rows"
  fi

  printf 'repo: %s\ncleaned: %d\n' "$repo" "$cleaned"
}
