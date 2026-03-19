-- =============================================================================
-- schema.sql — OpenClaw delivery task state schema
-- =============================================================================
-- [INPUT]:  SQLite3 runtime via common.sh ensure_db()
-- [OUTPUT]: 7 tables + 7 indexes for delivery task lifecycle
-- [POS]:   Static DDL consumed by common.sh; byte-compatible with legacy swarm.db
-- [PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
-- =============================================================================

PRAGMA journal_mode=WAL;
PRAGMA foreign_keys=ON;

CREATE TABLE IF NOT EXISTS tasks (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  status TEXT NOT NULL,
  priority TEXT NOT NULL DEFAULT 'medium',
  driver TEXT NOT NULL,
  model TEXT NOT NULL,
  repo_path TEXT NOT NULL,
  base_branch TEXT NOT NULL,
  branch TEXT,
  worktree_path TEXT,
  tmux_session TEXT,
  log_path TEXT,
  prompt_text TEXT NOT NULL,
  attempt_count INTEGER NOT NULL DEFAULT 0,
  max_attempts INTEGER NOT NULL DEFAULT 3,
  notify_on_ready INTEGER NOT NULL DEFAULT 1,
  notify_channel TEXT,
  notify_target TEXT,
  notify_account TEXT,
  source_session_key TEXT,
  progress_notify_enabled INTEGER NOT NULL DEFAULT 1,
  progress_notify_interval_minutes INTEGER NOT NULL DEFAULT 5,
  last_progress_notified_at TEXT,
  ci_status TEXT,
  pr_number INTEGER,
  pr_url TEXT,
  mergeable INTEGER,
  ui_change_detected INTEGER,
  cleaned_at TEXT,
  last_error_code TEXT,
  last_error_reason TEXT,
  last_error_evidence TEXT,
  created_at TEXT NOT NULL,
  started_at TEXT,
  completed_at TEXT,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS task_attempts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  task_id TEXT NOT NULL,
  attempt_no INTEGER NOT NULL,
  driver TEXT NOT NULL,
  model TEXT NOT NULL,
  tmux_session TEXT,
  prompt_snapshot TEXT NOT NULL,
  started_at TEXT NOT NULL,
  ended_at TEXT,
  exit_code INTEGER,
  reason TEXT,
  FOREIGN KEY(task_id) REFERENCES tasks(id)
);

CREATE TABLE IF NOT EXISTS task_checks (
  task_id TEXT PRIMARY KEY,
  pr_created INTEGER NOT NULL DEFAULT 0,
  branch_mergeable INTEGER NOT NULL DEFAULT 0,
  ci_passed INTEGER NOT NULL DEFAULT 0,
  review_codex_passed INTEGER NOT NULL DEFAULT 0,
  review_claude_passed INTEGER NOT NULL DEFAULT 0,
  review_gemini_passed INTEGER NOT NULL DEFAULT 0,
  ui_screenshot_present INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL,
  FOREIGN KEY(task_id) REFERENCES tasks(id)
);

CREATE TABLE IF NOT EXISTS task_artifacts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  task_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  path TEXT,
  value TEXT,
  created_at TEXT NOT NULL,
  FOREIGN KEY(task_id) REFERENCES tasks(id)
);

CREATE TABLE IF NOT EXISTS task_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  task_id TEXT NOT NULL,
  event_type TEXT NOT NULL,
  old_status TEXT,
  new_status TEXT,
  message TEXT,
  payload TEXT,
  created_at TEXT NOT NULL,
  FOREIGN KEY(task_id) REFERENCES tasks(id)
);

CREATE TABLE IF NOT EXISTS task_notifications (
  task_id TEXT NOT NULL,
  status TEXT NOT NULL,
  channel TEXT NOT NULL,
  target TEXT NOT NULL,
  message TEXT NOT NULL,
  result TEXT NOT NULL,
  sent_at TEXT NOT NULL,
  PRIMARY KEY(task_id, status),
  FOREIGN KEY(task_id) REFERENCES tasks(id)
);

CREATE TABLE IF NOT EXISTS task_progress_notifications (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  task_id TEXT NOT NULL,
  status TEXT NOT NULL,
  channel TEXT NOT NULL,
  target TEXT NOT NULL,
  message TEXT NOT NULL,
  result TEXT NOT NULL,
  sent_at TEXT NOT NULL,
  FOREIGN KEY(task_id) REFERENCES tasks(id)
);

CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status);
CREATE INDEX IF NOT EXISTS idx_tasks_updated_at ON tasks(updated_at);
CREATE INDEX IF NOT EXISTS idx_tasks_branch ON tasks(branch);
CREATE INDEX IF NOT EXISTS idx_attempts_task_id ON task_attempts(task_id);
CREATE INDEX IF NOT EXISTS idx_events_task_id ON task_events(task_id);
CREATE INDEX IF NOT EXISTS idx_notifications_task_id ON task_notifications(task_id);
CREATE INDEX IF NOT EXISTS idx_progress_notifications_task_id ON task_progress_notifications(task_id);
