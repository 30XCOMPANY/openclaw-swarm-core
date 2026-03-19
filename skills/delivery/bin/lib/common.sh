#!/usr/bin/env bash
# =============================================================================
# common.sh — Shared constants, config loader, and utility functions
# =============================================================================
# [INPUT]:  Shell environment, delivery.conf, SQLite DB, git repo
# [OUTPUT]: State constants, config vars, die/now_iso/sql/ensure_db/etc.
# [POS]:   Foundation library sourced by every delivery subcommand module
# [PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
# =============================================================================

# -- Guard against double-source --
[[ -n "${_COMMON_SH_LOADED:-}" ]] && return 0
readonly _COMMON_SH_LOADED=1

# =============================================================================
# State constants — mirror Python STATUS_* exactly
# =============================================================================

readonly STATUS_QUEUED="queued"
readonly STATUS_RUNNING="running"
readonly STATUS_PR_CREATED="pr_created"
readonly STATUS_CI_FAILED="ci_failed"
readonly STATUS_CI_PASSED="ci_passed"
readonly STATUS_REVIEW_CHANGES="review_changes_requested"
readonly STATUS_READY="ready_to_merge"
readonly STATUS_MERGED="merged"
readonly STATUS_FAILED="failed"
readonly STATUS_ABANDONED="abandoned"

readonly TERMINAL_STATUSES="${STATUS_MERGED}|${STATUS_ABANDONED}"
readonly RETRYABLE_STATUSES="${STATUS_FAILED}|${STATUS_CI_FAILED}|${STATUS_REVIEW_CHANGES}"
readonly ACTIVE_STATUSES="${STATUS_RUNNING}|${STATUS_PR_CREATED}|${STATUS_CI_FAILED}|${STATUS_CI_PASSED}|${STATUS_REVIEW_CHANGES}|${STATUS_READY}"

# =============================================================================
# Default config values — match Python ProjectConfig / default_project_toml()
# =============================================================================

CONF_REPO_PATH=""
CONF_BASE_BRANCH=""
CONF_WORKTREE_BASE=""
CONF_DEFAULT_DRIVER="codex"
CONF_MAX_ATTEMPTS=3
CONF_NOTIFY_ON_READY=true
CONF_REQUIRED_REVIEWS="codex claude"

CONF_NOTIFY_PROVIDER="openclaw"
CONF_NOTIFY_ENABLED=false
CONF_NOTIFY_CHANNEL="discord"
CONF_NOTIFY_TARGET=""
CONF_NOTIFY_ACCOUNT=""
CONF_NOTIFY_SILENT=false
CONF_NOTIFY_DRY_RUN=false
CONF_NOTIFY_EVENTS="ready_to_merge merged"
CONF_NOTIFY_ALLOW_FAILURE_EVENTS=false

CONF_PROGRESS_ENABLED=true
CONF_PROGRESS_INTERVAL_MINUTES=5

CONF_DRIVER_CODEX_ENABLED=true
CONF_DRIVER_CLAUDECODE_ENABLED=true
CONF_DRIVER_OPENCODE_ENABLED=true
CONF_DRIVER_GEMINI_CLI_ENABLED=true

CONF_DRIVER_CODEX_REASONING="high"
CONF_DRIVER_CLAUDECODE_REASONING="high"
CONF_DRIVER_OPENCODE_REASONING="high"
CONF_DRIVER_GEMINI_CLI_REASONING="high"

CONF_DRIVER_CODEX_MODEL=""
CONF_DRIVER_CLAUDECODE_MODEL=""
CONF_DRIVER_OPENCODE_MODEL=""
CONF_DRIVER_GEMINI_CLI_MODEL=""

# =============================================================================
# Core utilities
# =============================================================================

die() {
  local code=1
  if [[ "${1:-}" =~ ^[0-9]+$ ]]; then
    code="$1"; shift
  fi
  printf 'ERROR: %s\n' "$*" >&2
  exit "$code"
}

now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

quote() {
  printf '%q' "$1"
}

# =============================================================================
# Repo / path helpers
# =============================================================================

ensure_repo() {
  local repo="${1:?usage: ensure_repo <path>}"
  local resolved
  resolved="$(cd "$repo" 2>/dev/null && pwd -P)" \
    || die "Repo path not found: $repo"
  [[ -d "$resolved/.git" ]] \
    || die "Not a git repository: $resolved"
  printf '%s' "$resolved"
}

openclaw_dir() {
  local repo="${1:?usage: openclaw_dir <repo_path>}"
  printf '%s/.openclaw' "$repo"
}

db_path() {
  local repo="${1:?usage: db_path <repo_path>}"
  printf '%s/.openclaw/swarm.db' "$repo"
}

detect_base_branch() {
  local repo="${1:?usage: detect_base_branch <repo_path>}"
  local ref
  ref="$(git -C "$repo" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null)" || true
  if [[ "$ref" == refs/remotes/origin/* ]]; then
    printf '%s' "${ref#refs/remotes/origin/}"
  else
    printf 'main'
  fi
}

# =============================================================================
# Config loader — priority: CLI flags > env vars > delivery.conf > defaults
# =============================================================================

load_config() {
  local repo="${1:?usage: load_config <repo_path>}"

  # Resolve repo
  CONF_REPO_PATH="$(ensure_repo "$repo")"
  CONF_BASE_BRANCH="$(detect_base_branch "$CONF_REPO_PATH")"
  CONF_WORKTREE_BASE="${HOME}/code-worktrees/$(basename "$CONF_REPO_PATH")"

  # Source delivery.conf if present (overrides defaults)
  local conf_file
  conf_file="$(openclaw_dir "$CONF_REPO_PATH")/delivery.conf"
  if [[ -f "$conf_file" ]]; then
    # shellcheck source=/dev/null
    source "$conf_file"
  fi

  # Env var overrides (if set)
  CONF_BASE_BRANCH="${DELIVERY_BASE_BRANCH:-$CONF_BASE_BRANCH}"
  CONF_WORKTREE_BASE="${DELIVERY_WORKTREE_BASE:-$CONF_WORKTREE_BASE}"
  CONF_DEFAULT_DRIVER="${DELIVERY_DEFAULT_DRIVER:-$CONF_DEFAULT_DRIVER}"
  CONF_MAX_ATTEMPTS="${DELIVERY_MAX_ATTEMPTS:-$CONF_MAX_ATTEMPTS}"
}

# =============================================================================
# SQLite helpers
# =============================================================================

ensure_db() {
  local repo="${1:?usage: ensure_db <repo_path>}"
  local oc db schema

  oc="$(openclaw_dir "$repo")"
  db="$(db_path "$repo")"
  schema="${RUNTIME_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/schema.sql"

  mkdir -p "$oc" "$oc/logs"

  # Seed active-tasks.json if absent
  [[ -f "$oc/active-tasks.json" ]] || printf '[]\n' > "$oc/active-tasks.json"

  if [[ ! -f "$db" ]]; then
    [[ -f "$schema" ]] || die "Schema file not found: $schema"
    sqlite3 "$db" < "$schema" >/dev/null
  fi
}

sql() {
  local repo="${1:?usage: sql <repo_path> <query> [args...]}"
  shift
  local db
  db="$(db_path "$repo")"
  [[ -f "$db" ]] || die "Database not found: $db"
  sqlite3 -separator $'\t' "$db" "$@"
}

sql_json() {
  local repo="${1:?usage: sql_json <repo_path> <query> [args...]}"
  shift
  local db
  db="$(db_path "$repo")"
  [[ -f "$db" ]] || die "Database not found: $db"
  sqlite3 -json "$db" "$@"
}
