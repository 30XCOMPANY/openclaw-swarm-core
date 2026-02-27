#!/usr/bin/env python3
"""
[INPUT]: CLI commands, repository path, project-level config, and available local coding tools.
[OUTPUT]: Deterministic swarm orchestration actions (seed/spawn/monitor/cleanup/status) persisted in SQLite plus active-tasks JSON projection.
[POS]: swarm-core control plane entrypoint; enforces task state machine and driver contract across projects.
[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import shutil
import sqlite3
import subprocess
import sys
import textwrap
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple

import tomllib

from drivers import DRIVER_REGISTRY
from drivers.base import DriverContext, DriverError

STATUS_QUEUED = "queued"
STATUS_RUNNING = "running"
STATUS_PR_CREATED = "pr_created"
STATUS_CI_FAILED = "ci_failed"
STATUS_CI_PASSED = "ci_passed"
STATUS_REVIEW_CHANGES = "review_changes_requested"
STATUS_READY = "ready_to_merge"
STATUS_MERGED = "merged"
STATUS_FAILED = "failed"
STATUS_ABANDONED = "abandoned"

TERMINAL_STATUSES = {STATUS_MERGED, STATUS_ABANDONED}
RETRYABLE_STATUSES = {STATUS_FAILED, STATUS_CI_FAILED, STATUS_REVIEW_CHANGES}
ACTIVE_STATUSES = {
    STATUS_RUNNING,
    STATUS_PR_CREATED,
    STATUS_CI_FAILED,
    STATUS_CI_PASSED,
    STATUS_REVIEW_CHANGES,
    STATUS_READY,
}

STATE_TRANSITIONS: Dict[str, set[str]] = {
    STATUS_QUEUED: {STATUS_RUNNING, STATUS_ABANDONED},
    STATUS_RUNNING: {STATUS_PR_CREATED, STATUS_FAILED, STATUS_ABANDONED},
    STATUS_PR_CREATED: {STATUS_CI_FAILED, STATUS_CI_PASSED, STATUS_REVIEW_CHANGES, STATUS_READY, STATUS_MERGED, STATUS_ABANDONED},
    STATUS_CI_FAILED: {STATUS_RUNNING, STATUS_ABANDONED},
    STATUS_CI_PASSED: {STATUS_REVIEW_CHANGES, STATUS_READY, STATUS_MERGED, STATUS_CI_FAILED, STATUS_ABANDONED},
    STATUS_REVIEW_CHANGES: {STATUS_RUNNING, STATUS_READY, STATUS_ABANDONED},
    STATUS_READY: {STATUS_MERGED, STATUS_REVIEW_CHANGES, STATUS_CI_FAILED, STATUS_ABANDONED},
    STATUS_FAILED: {STATUS_RUNNING, STATUS_ABANDONED},
    STATUS_MERGED: set(),
    STATUS_ABANDONED: set(),
}

UI_EXTENSIONS = {
    ".tsx",
    ".jsx",
    ".css",
    ".scss",
    ".sass",
    ".less",
    ".html",
    ".vue",
    ".svelte",
}
UI_PATH_HINTS = (
    "/client/",
    "/web/",
    "/frontend/",
    "/ui/",
    "/components/",
    "/pages/",
    "/styles/",
)


@dataclass(slots=True)
class ProjectConfig:
    repo_path: str
    base_branch: str
    worktree_base: str
    default_driver: str
    max_attempts: int
    notify_on_ready: bool
    required_reviews: List[str]
    models: Dict[str, str]
    reasoning: Dict[str, str]
    driver_enabled: Dict[str, bool]
    notify_provider: str
    notify_enabled: bool
    notify_channel: str
    notify_target: str
    notify_account: str
    notify_events: List[str]
    notify_silent: bool
    notify_dry_run: bool


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def iso_to_epoch_ms(value: Optional[str]) -> int:
    if not value:
        return int(datetime.now(timezone.utc).timestamp() * 1000)
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    return int(parsed.timestamp() * 1000)


def die(message: str, code: int = 1) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(code)


def run(cmd: List[str], cwd: Optional[str] = None, check: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        cmd,
        cwd=cwd,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if check and result.returncode != 0:
        joined = " ".join(shlex.quote(part) for part in cmd)
        die(f"Command failed ({result.returncode}): {joined}\n{result.stderr.strip()}")
    return result


def ensure_repo(repo: str) -> str:
    path = Path(repo).expanduser().resolve()
    if not path.exists() or not path.is_dir():
        die(f"Repo path not found: {path}")
    git_dir = path / ".git"
    if not git_dir.exists():
        die(f"Not a git repository: {path}")
    return str(path)


def openclaw_dir(repo_path: str) -> Path:
    return Path(repo_path) / ".openclaw"


def db_path(repo_path: str) -> Path:
    return openclaw_dir(repo_path) / "swarm.db"


def project_toml_path(repo_path: str) -> Path:
    return openclaw_dir(repo_path) / "project.toml"


def ensure_layout(repo_path: str) -> None:
    oc = openclaw_dir(repo_path)
    oc.mkdir(parents=True, exist_ok=True)
    (oc / "logs").mkdir(parents=True, exist_ok=True)
    active = oc / "active-tasks.json"
    if not active.exists():
        active.write_text("[]\n", encoding="utf-8")


def templates_dir() -> Path:
    return Path(__file__).resolve().parent / "templates"


def swarm_bin_path() -> str:
    return str((Path(__file__).resolve().parent / "swarm").resolve())


def render_template(name: str, replacements: Dict[str, str]) -> str:
    source = templates_dir() / name
    if not source.exists():
        die(f"Missing template: {source}")
    content = source.read_text(encoding="utf-8")
    for key, value in replacements.items():
        content = content.replace(key, value)
    return content


def seed_project_wrappers(repo_path: str) -> List[str]:
    oc = openclaw_dir(repo_path)
    replacements = {
        "__SWARM_BIN__": swarm_bin_path(),
        "__REPO_ROOT__": repo_path,
    }
    generated: List[str] = []

    file_map: List[Tuple[str, str, bool]] = [
        ("setup.sh.tmpl", "setup.sh", True),
        ("spawn-agent.sh.tmpl", "spawn-agent.sh", True),
        ("redirect-agent.sh.tmpl", "redirect-agent.sh", True),
        ("kill-agent.sh.tmpl", "kill-agent.sh", True),
        ("check-agents.sh.tmpl", "check-agents.sh", True),
        ("cleanup.sh.tmpl", "cleanup.sh", True),
        ("status.sh.tmpl", "status.sh", True),
        ("run-agent.sh.tmpl", "run-agent.sh", True),
        ("AGENTS.md.tmpl", "AGENTS.md", False),
    ]

    for template_name, target_name, executable in file_map:
        target = oc / target_name
        rendered = render_template(template_name, replacements)
        target.write_text(rendered, encoding="utf-8")
        if executable:
            target.chmod(0o755)
        generated.append(str(target))

    return generated


def seed_repo_agents_doc(repo_path: str) -> Optional[str]:
    repo = Path(repo_path)
    target = repo / "AGENTS.md"
    if target.exists():
        return None

    visible_dirs: List[str] = []
    visible_files: List[str] = []
    ignored_dirs = {".git", ".openclaw", "node_modules", "dist", "build", ".next", ".cache"}

    for child in sorted(repo.iterdir(), key=lambda item: item.name.lower()):
        name = child.name
        if child.is_dir():
            if name in ignored_dirs:
                continue
            visible_dirs.append(name)
        elif child.is_file() and name not in {"AGENTS.md"}:
            visible_files.append(name)

    dir_lines = ["<directory>"]
    dir_lines.append(".openclaw/ - Project thin control plane (seeded wrappers + SQLite state + compatibility projection)")
    for name in visible_dirs[:10]:
        dir_lines.append(f"{name}/ - Project module")
    dir_lines.append("</directory>")

    cfg_lines = ["<config>"]
    for name in visible_files[:10]:
        cfg_lines.append(f"{name} - Project file")
    if len(cfg_lines) == 1:
        cfg_lines.append("No top-level config files detected during seed.")
    cfg_lines.append("</config>")

    content = "\n".join(
        [
            f"# {repo.name} - 30X Swarm Seeded Project",
            "",
            "This repository is managed by 30X Swarm seeding (OpenClaw orchestration) for reusable multi-agent delivery workflows.",
            "",
            *dir_lines,
            "",
            *cfg_lines,
            "",
            "Rules",
            "- Keep project-specific behavior in code; keep orchestration behavior in `.openclaw/` wrappers and `swarm-core`.",
            "- Treat `.openclaw/swarm.db` as task truth source and `active-tasks.json` as compatibility projection only.",
            "",
            "[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md",
            "",
        ]
    )
    target.write_text(content, encoding="utf-8")
    return str(target)


def ensure_gitignore_entries(repo_path: str) -> Optional[str]:
    target = Path(repo_path) / ".gitignore"
    required = [
        ".openclaw/swarm.db",
        ".openclaw/active-tasks.json",
        ".openclaw/logs/",
    ]

    if target.exists():
        existing = target.read_text(encoding="utf-8").splitlines()
    else:
        existing = []

    missing = [entry for entry in required if entry not in existing]
    if not missing:
        return None

    lines = existing[:]
    if lines and lines[-1] != "":
        lines.append("")
    lines.append("# 30X Swarm runtime")
    lines.extend(missing)
    lines.append("")

    target.write_text("\n".join(lines), encoding="utf-8")
    return str(target)


def detect_base_branch(repo_path: str) -> str:
    result = run(
        ["git", "-C", repo_path, "symbolic-ref", "refs/remotes/origin/HEAD"],
        check=False,
    )
    if result.returncode == 0 and result.stdout.strip().startswith("refs/remotes/origin/"):
        return result.stdout.strip().replace("refs/remotes/origin/", "", 1)
    return "main"


def openclaw_state_dir() -> Path:
    custom_config = os.getenv("OPENCLAW_CONFIG_PATH")
    if custom_config:
        return Path(custom_config).expanduser().resolve().parent
    return Path.home() / ".openclaw"


def discover_openclaw_notification_defaults() -> Tuple[str, str]:
    state_dir = openclaw_state_dir()
    config_path = state_dir / "openclaw.json"
    commands_log_path = state_dir / "logs" / "commands.log"

    account = ""
    target = ""

    try:
        if config_path.exists():
            parsed = json.loads(config_path.read_text(encoding="utf-8"))
            bindings = parsed.get("bindings") if isinstance(parsed.get("bindings"), list) else []
            for item in bindings:
                if not isinstance(item, dict):
                    continue
                if str(item.get("agentId") or "") != "main":
                    continue
                match = item.get("match") if isinstance(item.get("match"), dict) else {}
                if str(match.get("channel") or "") != "discord":
                    continue
                account_id = str(match.get("accountId") or "").strip()
                if account_id:
                    account = account_id
                    break
    except Exception:
        account = ""

    try:
        if commands_log_path.exists():
            lines = commands_log_path.read_text(encoding="utf-8").splitlines()
            for line in reversed(lines):
                if not line.strip():
                    continue
                try:
                    event = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if str(event.get("source") or "") != "discord":
                    continue
                session_key = str(event.get("sessionKey") or "")
                match = re.search(r":discord:channel:(\d+)", session_key)
                if match:
                    target = f"channel:{match.group(1)}"
                    break
    except Exception:
        target = ""

    return account, target


def default_project_toml(repo_path: str) -> str:
    repo = Path(repo_path)
    repo_name = repo.name
    worktree_base = Path.home() / "code-worktrees" / repo_name
    base_branch = detect_base_branch(repo_path)
    notify_account, notify_target = discover_openclaw_notification_defaults()
    notify_enabled = "true" if notify_target else "false"

    return textwrap.dedent(
        f"""
        repo_path = "{repo_path}"
        base_branch = "{base_branch}"
        worktree_base = "{worktree_base}"
        default_driver = "codex"
        max_attempts = 3
        notify_on_ready = true
        required_reviews = ["codex", "claude"]

        [notifications]
        provider = "openclaw"
        enabled = {notify_enabled}
        channel = "discord"
        target = "{notify_target}"
        account = "{notify_account}"
        silent = false
        dry_run = false
        events = ["ready_to_merge", "merged", "abandoned"]

        [drivers.codex]
        # Optional. Leave unset to use Codex CLI default model.
        reasoning = "high"

        [drivers.claudecode]
        # Optional. Leave unset to use Claude Code CLI default model.
        reasoning = "high"

        [drivers.opencode]
        # Optional. Leave unset to use OpenCode's own configured default model.
        reasoning = "high"

        [drivers.gemini-cli]
        # Optional. Leave unset to use Gemini CLI default model.
        reasoning = "high"
        enabled = true
        """
    ).strip() + "\n"


def normalize_model_for_driver(driver_name: str, model: str) -> str:
    value = (model or "").strip()
    if not value:
        return value

    name = driver_name.strip().lower()
    if name in {"codex", "claudecode", "gemini-cli"}:
        # These CLIs expect plain model IDs, not provider/model.
        if "/" in value:
            return value.split("/", 1)[1]
        return value

    if name == "opencode":
        # OpenCode expects provider/model format.
        if "/" not in value:
            return f"default/{value}"
        if value == "openai/gpt-5.3-codex":
            return "default/gpt-5.3-codex"
        return value

    return value


def load_project_config(repo_path: str) -> ProjectConfig:
    ensure_layout(repo_path)
    config_file = project_toml_path(repo_path)
    if not config_file.exists():
        config_file.write_text(default_project_toml(repo_path), encoding="utf-8")

    parsed = tomllib.loads(config_file.read_text(encoding="utf-8"))

    base_branch = str(parsed.get("base_branch") or detect_base_branch(repo_path))
    worktree_base = str(parsed.get("worktree_base") or (Path.home() / "code-worktrees" / Path(repo_path).name))
    default_driver = str(parsed.get("default_driver") or "codex")
    max_attempts = int(parsed.get("max_attempts") or 3)
    notify_on_ready = bool(parsed.get("notify_on_ready") if parsed.get("notify_on_ready") is not None else True)

    required_reviews_raw = parsed.get("required_reviews") or ["codex", "claude"]
    required_reviews = [str(item).lower() for item in required_reviews_raw]

    notifications = parsed.get("notifications") if isinstance(parsed.get("notifications"), dict) else {}
    notify_provider = str(notifications.get("provider") or "openclaw").strip().lower()
    notify_enabled = bool(notifications.get("enabled") if notifications.get("enabled") is not None else False)
    notify_channel = str(notifications.get("channel") or "discord").strip()
    notify_target = str(notifications.get("target") or "").strip()
    notify_account = str(notifications.get("account") or "").strip()
    notify_silent = bool(notifications.get("silent") if notifications.get("silent") is not None else False)
    notify_dry_run = bool(notifications.get("dry_run") if notifications.get("dry_run") is not None else False)
    notify_events_raw = notifications.get("events") if isinstance(notifications.get("events"), list) else [
        "ready_to_merge",
        "merged",
        "abandoned",
    ]
    notify_events = [str(item).strip() for item in notify_events_raw if str(item).strip()]

    models: Dict[str, str] = {
        "codex": "",
        "claudecode": "",
        "opencode": "",
        "gemini-cli": "",
    }
    reasoning: Dict[str, str] = {
        "codex": "high",
        "claudecode": "high",
        "opencode": "high",
        "gemini-cli": "high",
    }
    driver_enabled: Dict[str, bool] = {
        "codex": True,
        "claudecode": True,
        "opencode": True,
        "gemini-cli": True,
    }

    drivers = parsed.get("drivers") if isinstance(parsed.get("drivers"), dict) else {}
    for key, value in drivers.items():
        if not isinstance(value, dict):
            continue
        name = str(key)
        model = value.get("model")
        effort = value.get("reasoning")
        if isinstance(model, str) and model.strip():
            models[name] = normalize_model_for_driver(name, model.strip())
        if isinstance(effort, str) and effort.strip():
            reasoning[name] = effort.strip()
        enabled = value.get("enabled")
        if isinstance(enabled, bool):
            driver_enabled[name] = enabled

    return ProjectConfig(
        repo_path=repo_path,
        base_branch=base_branch,
        worktree_base=worktree_base,
        default_driver=default_driver,
        max_attempts=max_attempts,
        notify_on_ready=notify_on_ready,
        required_reviews=required_reviews,
        models=models,
        reasoning=reasoning,
        driver_enabled=driver_enabled,
        notify_provider=notify_provider,
        notify_enabled=notify_enabled,
        notify_channel=notify_channel,
        notify_target=notify_target,
        notify_account=notify_account,
        notify_events=notify_events,
        notify_silent=notify_silent,
        notify_dry_run=notify_dry_run,
    )


def connect(repo_path: str) -> sqlite3.Connection:
    conn = sqlite3.connect(db_path(repo_path))
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    init_schema(conn)
    return conn


def init_schema(conn: sqlite3.Connection) -> None:
    conn.executescript(
        """
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

        CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status);
        CREATE INDEX IF NOT EXISTS idx_tasks_updated_at ON tasks(updated_at);
        CREATE INDEX IF NOT EXISTS idx_tasks_branch ON tasks(branch);
        CREATE INDEX IF NOT EXISTS idx_attempts_task_id ON task_attempts(task_id);
        CREATE INDEX IF NOT EXISTS idx_events_task_id ON task_events(task_id);
        CREATE INDEX IF NOT EXISTS idx_notifications_task_id ON task_notifications(task_id);
        """
    )


def to_projection_status(status: str) -> str:
    return status


def write_projection(conn: sqlite3.Connection, repo_path: str) -> None:
    rows = conn.execute(
        """
        SELECT t.*, c.pr_created, c.branch_mergeable, c.ci_passed,
               c.review_codex_passed, c.review_claude_passed,
               c.review_gemini_passed, c.ui_screenshot_present
        FROM tasks t
        LEFT JOIN task_checks c ON c.task_id = t.id
        WHERE t.cleaned_at IS NULL AND t.status NOT IN (?, ?)
        ORDER BY datetime(t.created_at) ASC
        """,
        (STATUS_MERGED, STATUS_ABANDONED),
    ).fetchall()

    payload: List[Dict[str, Any]] = []
    for row in rows:
        payload.append(
            {
                "id": row["id"],
                "tmuxSession": row["tmux_session"],
                "agent": row["driver"],
                "model": row["model"],
                "description": row["description"],
                "repo": row["repo_path"],
                "worktree": row["worktree_path"],
                "branch": row["branch"],
                "startedAt": iso_to_epoch_ms(row["started_at"] or row["created_at"]),
                "status": to_projection_status(row["status"]),
                "attempts": int(row["attempt_count"]),
                "maxAttempts": int(row["max_attempts"]),
                "notifyOnComplete": bool(row["notify_on_ready"]),
                "pr": row["pr_number"],
                "checks": {
                    "prCreated": bool(row["pr_created"]),
                    "branchMergeable": bool(row["branch_mergeable"]),
                    "ciPassed": bool(row["ci_passed"]),
                    "codexReviewPassed": bool(row["review_codex_passed"]),
                    "claudeReviewPassed": bool(row["review_claude_passed"]),
                    "geminiReviewPassed": bool(row["review_gemini_passed"]),
                    "uiScreenshotPresent": bool(row["ui_screenshot_present"]),
                },
                "note": row["last_error_reason"] or "",
            }
        )

    projection_file = openclaw_dir(repo_path) / "active-tasks.json"
    projection_file.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def event(conn: sqlite3.Connection, task_id: str, event_type: str, old: Optional[str], new: Optional[str], message: str = "", payload: Optional[Dict[str, Any]] = None) -> None:
    conn.execute(
        """
        INSERT INTO task_events(task_id, event_type, old_status, new_status, message, payload, created_at)
        VALUES(?, ?, ?, ?, ?, ?, ?)
        """,
        (
            task_id,
            event_type,
            old,
            new,
            message,
            json.dumps(payload, ensure_ascii=False) if payload else None,
            now_iso(),
        ),
    )


def check_transition(old_status: str, new_status: str) -> None:
    if old_status == new_status:
        return
    if new_status not in STATE_TRANSITIONS.get(old_status, set()):
        die(f"Illegal state transition: {old_status} -> {new_status}")


def normalized_notify_events(config: ProjectConfig) -> List[str]:
    values = [item.strip().lower() for item in config.notify_events if item.strip()]
    if values:
        return values
    return [STATUS_READY, STATUS_MERGED, STATUS_ABANDONED]


def should_send_notification(config: Optional[ProjectConfig], row: sqlite3.Row, status: str) -> bool:
    if config is None:
        return False
    if not config.notify_enabled:
        return False
    if config.notify_provider != "openclaw":
        return False
    if not config.notify_channel or not config.notify_target:
        return False

    enabled_events = set(normalized_notify_events(config))
    if status.lower() not in enabled_events:
        return False

    if status == STATUS_READY and not bool(row["notify_on_ready"]):
        return False

    return True


def notification_sent(conn: sqlite3.Connection, task_id: str, status: str) -> bool:
    row = conn.execute(
        "SELECT 1 FROM task_notifications WHERE task_id = ? AND status = ?",
        (task_id, status),
    ).fetchone()
    return row is not None


def truncate_text(value: str, limit: int) -> str:
    text = value.strip()
    if len(text) <= limit:
        return text
    return text[: max(0, limit - 3)] + "..."


def build_notification_message(row: sqlite3.Row, status: str, detail: str = "") -> str:
    repo_name = Path(str(row["repo_path"] or "")).name or str(row["repo_path"] or "-")
    lines = [
        f"[swarm] {repo_name}",
        f"task={row['id']} status={status}",
        f"driver={row['driver']} model={row['model']} attempt={row['attempt_count']}/{row['max_attempts']}",
    ]

    branch = str(row["branch"] or "")
    if branch:
        lines.append(f"branch={branch}")

    pr_url = str(row["pr_url"] or "")
    if pr_url:
        lines.append(f"pr={pr_url}")
    elif row["pr_number"] is not None:
        lines.append(f"pr=#{row['pr_number']}")

    note = detail.strip() or str(row["last_error_reason"] or "").strip()
    if note:
        lines.append(f"note={note}")

    return truncate_text("\n".join(lines), 1800)


def dispatch_openclaw_notification(config: ProjectConfig, message: str) -> Tuple[bool, str]:
    cmd = [
        "openclaw",
        "message",
        "send",
        "--channel",
        config.notify_channel,
        "--target",
        config.notify_target,
        "--message",
        message,
        "--json",
    ]
    if config.notify_account:
        cmd.extend(["--account", config.notify_account])
    if config.notify_silent:
        cmd.append("--silent")
    if config.notify_dry_run:
        cmd.append("--dry-run")

    try:
        result = run(cmd, check=False)
    except FileNotFoundError:
        return False, json.dumps({"code": "openclaw_not_found"}, ensure_ascii=False)
    except Exception as error:  # defensive: do not block state progression on notify failure
        return False, json.dumps({"code": "notify_exec_error", "reason": str(error)}, ensure_ascii=False)

    payload = {
        "returncode": result.returncode,
        "stdout": truncate_text(result.stdout or "", 3000),
        "stderr": truncate_text(result.stderr or "", 2000),
    }
    return result.returncode == 0, json.dumps(payload, ensure_ascii=False)


def send_status_notification(
    conn: sqlite3.Connection,
    config: Optional[ProjectConfig],
    row: sqlite3.Row,
    status: str,
    detail: str = "",
) -> bool:
    task_id = str(row["id"])
    if not should_send_notification(config, row, status):
        return False
    if notification_sent(conn, task_id, status):
        return False

    assert config is not None
    message = build_notification_message(row, status, detail)
    ok, result = dispatch_openclaw_notification(config, message)
    if not ok:
        event(
            conn,
            task_id,
            "notification_failed",
            status,
            status,
            f"notify failed: {status}",
            {
                "provider": config.notify_provider,
                "channel": config.notify_channel,
                "target": config.notify_target,
                "result": result,
            },
        )
        return False

    conn.execute(
        """
        INSERT OR IGNORE INTO task_notifications(task_id, status, channel, target, message, result, sent_at)
        VALUES(?, ?, ?, ?, ?, ?, ?)
        """,
        (
            task_id,
            status,
            config.notify_channel,
            config.notify_target,
            message,
            result,
            now_iso(),
        ),
    )
    event(
        conn,
        task_id,
        "notification_sent",
        status,
        status,
        f"notified: {status}",
        {
            "provider": config.notify_provider,
            "channel": config.notify_channel,
            "target": config.notify_target,
        },
    )
    return True


def flush_pending_notifications(conn: sqlite3.Connection, config: Optional[ProjectConfig], task_id: Optional[str] = None) -> int:
    if config is None:
        return 0
    if not config.notify_enabled or config.notify_provider != "openclaw" or not config.notify_target:
        return 0

    statuses = normalized_notify_events(config)
    if not statuses:
        return 0

    placeholders = ", ".join("?" for _ in statuses)
    params: List[Any] = list(statuses)
    query = textwrap.dedent(
        f"""
        SELECT t.*
        FROM tasks t
        LEFT JOIN task_notifications n
          ON n.task_id = t.id AND n.status = t.status
        WHERE n.task_id IS NULL
          AND t.status IN ({placeholders})
        """
    ).strip()
    if task_id:
        query += " AND t.id = ?"
        params.append(task_id)

    rows = conn.execute(query, params).fetchall()

    sent = 0
    for row in rows:
        status = str(row["status"])
        detail = str(row["last_error_reason"] or "")
        if send_status_notification(conn, config, row, status, detail):
            sent += 1
    return sent


def set_status(
    conn: sqlite3.Connection,
    task_id: str,
    new_status: str,
    message: str = "",
    payload: Optional[Dict[str, Any]] = None,
    config: Optional[ProjectConfig] = None,
) -> None:
    row = conn.execute("SELECT * FROM tasks WHERE id = ?", (task_id,)).fetchone()
    if row is None:
        die(f"Task not found: {task_id}")

    old_status = str(row["status"])
    check_transition(old_status, new_status)

    completed_at = row["completed_at"]
    if new_status in TERMINAL_STATUSES and not completed_at:
        completed_at = now_iso()

    conn.execute(
        "UPDATE tasks SET status = ?, completed_at = ?, updated_at = ? WHERE id = ?",
        (new_status, completed_at, now_iso(), task_id),
    )
    event(conn, task_id, "status_changed", old_status, new_status, message, payload)

    fresh = conn.execute("SELECT * FROM tasks WHERE id = ?", (task_id,)).fetchone()
    if fresh is not None:
        send_status_notification(conn, config, fresh, new_status, message)


def ensure_checks_row(conn: sqlite3.Connection, task_id: str) -> None:
    conn.execute(
        """
        INSERT INTO task_checks(
          task_id, pr_created, branch_mergeable, ci_passed,
          review_codex_passed, review_claude_passed, review_gemini_passed,
          ui_screenshot_present, updated_at
        ) VALUES(?, 0, 0, 0, 0, 0, 0, 0, ?)
        ON CONFLICT(task_id) DO NOTHING
        """,
        (task_id, now_iso()),
    )


def update_checks(conn: sqlite3.Connection, task_id: str, updates: Dict[str, int]) -> None:
    if not updates:
        return
    allowed = {
        "pr_created",
        "branch_mergeable",
        "ci_passed",
        "review_codex_passed",
        "review_claude_passed",
        "review_gemini_passed",
        "ui_screenshot_present",
    }
    parts: List[str] = []
    values: List[Any] = []
    for key, value in updates.items():
        if key not in allowed:
            continue
        parts.append(f"{key} = ?")
        values.append(1 if value else 0)

    if not parts:
        return

    parts.append("updated_at = ?")
    values.append(now_iso())
    values.append(task_id)

    conn.execute(
        f"UPDATE task_checks SET {', '.join(parts)} WHERE task_id = ?",
        values,
    )


def read_task(conn: sqlite3.Connection, task_id: str) -> sqlite3.Row:
    row = conn.execute("SELECT * FROM tasks WHERE id = ?", (task_id,)).fetchone()
    if row is None:
        die(f"Task not found: {task_id}")
    return row


def sanitize_token(value: str, max_len: int = 56) -> str:
    token = re.sub(r"[^a-zA-Z0-9_.-]", "-", value).strip("-")
    token = re.sub(r"-+", "-", token)
    return token[:max_len] or "task"


def build_prompt(prompt: str, task_id: str, branch: str, base_branch: str) -> str:
    return textwrap.dedent(
        f"""
        {prompt.strip()}

        IMPORTANT - Definition of Done:
        1. Implement the task with minimal, correct changes.
        2. Run project-relevant checks for changed scope.
        3. Commit your changes with clear message.
        4. Push branch: git push origin {branch}
        5. Create PR to {base_branch}: gh pr create --base {base_branch} --head {branch} --fill
        6. If UI changed, include screenshot markdown in PR body.
        7. Print: AGENT_DONE TASK_ID={task_id}

        If blocked, print: AGENT_STUCK TASK_ID={task_id} REASON=<short reason>
        """
    ).strip()


def is_driver_enabled(config: ProjectConfig, driver_name: str) -> bool:
    return bool(config.driver_enabled.get(driver_name, True))


def resolve_driver(config: ProjectConfig, requested: str, prompt_text: str) -> str:
    requested = requested.strip().lower()
    if requested == "claude":
        requested = "claudecode"

    if requested != "auto":
        if requested not in DRIVER_REGISTRY:
            die(f"Unsupported driver: {requested}")
        if not is_driver_enabled(config, requested):
            die(f"Driver disabled in project.toml: {requested}")
        return requested

    lower = prompt_text.lower()
    if any(word in lower for word in ("frontend", "ui", "css", "tailwind", "component", "layout")):
        preferred = "claudecode"
    else:
        preferred = config.default_driver

    fallback_order = [preferred, "codex", "opencode", "claudecode", "gemini-cli"]
    seen: set[str] = set()
    for name in fallback_order:
        if name in seen:
            continue
        seen.add(name)
        if not is_driver_enabled(config, name):
            continue
        driver = DRIVER_REGISTRY.get(name)
        if driver is None:
            continue
        preflight = driver.preflight()
        if preflight.get("available"):
            return name

    die("No available driver found for auto selection")
    return "codex"


def worktree_path_for(config: ProjectConfig, task_id: str) -> str:
    base = Path(config.worktree_base).expanduser().resolve()
    base.mkdir(parents=True, exist_ok=True)
    return str(base / sanitize_token(task_id, 96))


def branch_for(task_id: str) -> str:
    return f"swarm/{sanitize_token(task_id, 72)}"


def session_for(repo_path: str, task_id: str) -> str:
    repo = sanitize_token(Path(repo_path).name, 20)
    task = sanitize_token(task_id, 28)
    return sanitize_token(f"swarm-{repo}-{task}", 60)


def remove_worktree(repo_path: str, worktree: str) -> None:
    if Path(worktree).exists():
        run(["git", "-C", repo_path, "worktree", "remove", worktree, "--force"], check=False)
        if Path(worktree).exists():
            shutil.rmtree(worktree, ignore_errors=True)


def delete_branch(repo_path: str, branch: str) -> None:
    run(["git", "-C", repo_path, "branch", "-D", branch], check=False)


def create_worktree(repo_path: str, base_branch: str, branch: str, worktree: str) -> None:
    run(["git", "-C", repo_path, "fetch", "origin", base_branch], check=False)
    remove_worktree(repo_path, worktree)
    delete_branch(repo_path, branch)

    created = run(
        ["git", "-C", repo_path, "worktree", "add", "-b", branch, worktree, f"origin/{base_branch}"],
        check=False,
    )
    if created.returncode != 0:
        fallback = run(
            ["git", "-C", repo_path, "worktree", "add", "-b", branch, worktree, base_branch],
            check=False,
        )
        if fallback.returncode != 0:
            die(f"Failed to create worktree: {fallback.stderr.strip() or created.stderr.strip()}")


def tmux_has_session(name: str) -> bool:
    result = run(["tmux", "has-session", "-t", name], check=False)
    return result.returncode == 0


def tmux_kill(name: str) -> None:
    run(["tmux", "kill-session", "-t", name], check=False)


def launch_session(session: str, worktree: str, command: str, log_file: str) -> None:
    tmux_kill(session)
    wrapped = f"bash -lc {shlex.quote(command)}"
    started = run(["tmux", "new-session", "-d", "-s", session, "-c", worktree, wrapped], check=False)
    if started.returncode != 0:
        die(f"Failed to start tmux session {session}: {started.stderr.strip()}")

    Path(log_file).parent.mkdir(parents=True, exist_ok=True)
    Path(log_file).touch(exist_ok=True)
    run(["tmux", "pipe-pane", "-t", session, "-o", f"cat >> {shlex.quote(log_file)}"], check=False)


def insert_attempt(conn: sqlite3.Connection, task_id: str, attempt_no: int, driver: str, model: str, tmux_session: str, prompt: str) -> None:
    conn.execute(
        """
        INSERT INTO task_attempts(task_id, attempt_no, driver, model, tmux_session, prompt_snapshot, started_at)
        VALUES(?, ?, ?, ?, ?, ?, ?)
        """,
        (task_id, attempt_no, driver, model, tmux_session, prompt, now_iso()),
    )


def create_or_replace_task(
    conn: sqlite3.Connection,
    config: ProjectConfig,
    task_id: str,
    driver_name: str,
    model: str,
    prompt_text: str,
    title: str,
    description: str,
    branch: str,
    worktree: str,
    session: str,
    log_file: str,
    attempt_count: int,
) -> None:
    now = now_iso()
    conn.execute(
        """
        INSERT INTO tasks(
          id, title, description, status, priority, driver, model,
          repo_path, base_branch, branch, worktree_path, tmux_session,
          log_path, prompt_text, attempt_count, max_attempts,
          notify_on_ready, ci_status, pr_number, pr_url,
          mergeable, ui_change_detected, last_error_code,
          last_error_reason, last_error_evidence,
          created_at, started_at, completed_at, updated_at
        ) VALUES(?, ?, ?, ?, 'medium', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, ?, ?, NULL, ?)
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
          updated_at = excluded.updated_at
        """,
        (
            task_id,
            title,
            description,
            STATUS_RUNNING,
            driver_name,
            model,
            config.repo_path,
            config.base_branch,
            branch,
            worktree,
            session,
            log_file,
            prompt_text,
            attempt_count,
            config.max_attempts,
            1 if config.notify_on_ready else 0,
            now,
            now,
            now,
        ),
    )


def parse_prompt(path: Optional[str], prompt_text: Optional[str]) -> str:
    if path and prompt_text:
        die("Use either --prompt-file or --prompt, not both")
    if path:
        file = Path(path).expanduser().resolve()
        if not file.exists():
            die(f"Prompt file not found: {file}")
        return file.read_text(encoding="utf-8")
    if prompt_text:
        return prompt_text
    die("Prompt is required (--prompt-file or --prompt)")
    return ""


def cmd_seed(args: argparse.Namespace) -> None:
    repo = ensure_repo(args.repo)
    config = load_project_config(repo)
    gitignore_path = ensure_gitignore_entries(repo)
    root_agents_doc = seed_repo_agents_doc(repo)
    generated = seed_project_wrappers(repo)
    with connect(repo) as conn:
        write_projection(conn, repo)

    print(f"seeded_repo: {repo}")
    print(f"config: {project_toml_path(repo)}")
    print(f"db: {db_path(repo)}")
    print(f"worktree_base: {config.worktree_base}")
    print("wrappers:")
    for path in generated:
        print(f"  - {path}")
    if root_agents_doc:
        print(f"root_agents_doc: {root_agents_doc}")
    if gitignore_path:
        print(f"gitignore_updated: {gitignore_path}")


def cmd_task_spawn(args: argparse.Namespace) -> None:
    repo = ensure_repo(args.repo)
    config = load_project_config(repo)
    raw_prompt = parse_prompt(args.prompt_file, args.prompt)
    driver_name = resolve_driver(config, args.driver, raw_prompt)

    driver = DRIVER_REGISTRY[driver_name]
    preflight = driver.preflight()
    if not preflight.get("available"):
        die(f"Driver '{driver_name}' unavailable: {preflight}")

    task_id = sanitize_token(args.task_id, 80)
    branch = branch_for(task_id)
    worktree = worktree_path_for(config, task_id)
    session = session_for(repo, task_id)
    log_file = str(openclaw_dir(repo) / "logs" / f"{task_id}.log")

    prompt = build_prompt(raw_prompt, task_id=task_id, branch=branch, base_branch=config.base_branch)
    model = config.models.get(driver_name, "")
    model = normalize_model_for_driver(driver_name, model)
    effort = config.reasoning.get(driver_name, "high")

    try:
        launch_result = driver.launch(
            DriverContext(
                repo_path=repo,
                worktree_path=worktree,
                task_id=task_id,
                prompt=prompt,
                model=model,
                reasoning_effort=effort,
            )
        )
    except DriverError as error:
        detail = error.result
        die(f"Driver launch failed [{detail.code}]: {detail.reason}")

    create_worktree(repo, config.base_branch, branch, worktree)
    launch_session(session=session, worktree=worktree, command=launch_result.command, log_file=log_file)

    title = f"Task {task_id}"
    description = raw_prompt.strip().splitlines()[0] if raw_prompt.strip() else task_id

    with connect(repo) as conn:
        row = conn.execute("SELECT attempt_count FROM tasks WHERE id = ?", (task_id,)).fetchone()
        attempts = int(row["attempt_count"]) + 1 if row else 1

        create_or_replace_task(
            conn=conn,
            config=config,
            task_id=task_id,
            driver_name=driver_name,
            model=launch_result.model,
            prompt_text=raw_prompt,
            title=title,
            description=description,
            branch=branch,
            worktree=worktree,
            session=session,
            log_file=log_file,
            attempt_count=attempts,
        )
        ensure_checks_row(conn, task_id)
        insert_attempt(conn, task_id, attempts, driver_name, launch_result.model, session, raw_prompt)
        event(conn, task_id, "spawned", STATUS_QUEUED, STATUS_RUNNING, "Task spawned", {"driver": driver_name})
        write_projection(conn, repo)

    print(f"task_id: {task_id}")
    print(f"driver: {driver_name}")
    print(f"model: {launch_result.model or '<driver-default>'}")
    print(f"session: {session}")
    print(f"branch: {branch}")
    print(f"worktree: {worktree}")
    print(f"log: {log_file}")
    print(f"status: {STATUS_RUNNING}")


def cmd_task_redirect(args: argparse.Namespace) -> None:
    repo = ensure_repo(args.repo)
    task_id = sanitize_token(args.task_id, 80)
    with connect(repo) as conn:
        row = read_task(conn, task_id)
        session = row["tmux_session"]
        if not session:
            die(f"Task {task_id} has no tmux session")
        if not tmux_has_session(str(session)):
            die(f"tmux session not found: {session}")
        run(["tmux", "send-keys", "-t", str(session), args.message, "Enter"], check=True)
        event(conn, task_id, "redirect", row["status"], row["status"], args.message)
        write_projection(conn, repo)

    print(f"task_id: {task_id}")
    print("redirect: ok")


def cmd_task_kill(args: argparse.Namespace) -> None:
    repo = ensure_repo(args.repo)
    config = load_project_config(repo)
    task_id = sanitize_token(args.task_id, 80)
    with connect(repo) as conn:
        row = read_task(conn, task_id)
        session = row["tmux_session"]
        if session and tmux_has_session(str(session)):
            tmux_kill(str(session))

        old_status = str(row["status"])
        if old_status not in {STATUS_MERGED, STATUS_ABANDONED}:
            if old_status == STATUS_RUNNING:
                set_status(conn, task_id, STATUS_FAILED, "Task killed manually", config=config)
            elif old_status in {STATUS_PR_CREATED, STATUS_CI_FAILED, STATUS_CI_PASSED, STATUS_REVIEW_CHANGES, STATUS_READY}:
                set_status(conn, task_id, STATUS_ABANDONED, "Task killed after PR stage", config=config)
            else:
                set_status(conn, task_id, STATUS_ABANDONED, "Task killed manually", config=config)

        conn.execute(
            "UPDATE tasks SET last_error_code = ?, last_error_reason = ?, updated_at = ? WHERE id = ?",
            ("killed", "Manually terminated", now_iso(), task_id),
        )
        event(conn, task_id, "killed", old_status, old_status, "Manual kill")
        flush_pending_notifications(conn, config, task_id=task_id)
        write_projection(conn, repo)

    print(f"task_id: {task_id}")
    print("killed: ok")


def gh_json(repo_path: str, args: List[str]) -> Optional[Any]:
    result = run(args, cwd=repo_path, check=False)
    if result.returncode != 0:
        return None
    text = result.stdout.strip()
    if not text:
        return None
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return None


def detect_ui_change(files: List[Dict[str, Any]]) -> bool:
    for file in files:
        path = str(file.get("path") or "")
        if not path:
            continue
        suffix = Path(path).suffix.lower()
        if suffix in UI_EXTENSIONS:
            return True
        lowered = f"/{path.lower()}"
        if any(hint in lowered for hint in UI_PATH_HINTS):
            return True
    return False


def screenshot_present(pr_body: str) -> bool:
    if not pr_body:
        return False
    if re.search(r"!\[[^\]]*\]\([^\)]+\)", pr_body):
        return True
    return "screenshot" in pr_body.lower()


def check_ci(repo_path: str, pr_number: int) -> Tuple[str, Dict[str, Any]]:
    data = gh_json(
        repo_path,
        ["gh", "pr", "checks", str(pr_number), "--json", "state,name"],
    )
    if not isinstance(data, list) or not data:
        return ("pending", {"states": []})

    states = [str(item.get("state", "")).upper() for item in data]
    if any(state in {"FAILURE", "ERROR", "CANCELLED", "ACTION_REQUIRED", "TIMED_OUT"} for state in states):
        return ("failing", {"states": states})
    if any(state in {"PENDING", "QUEUED", "WAITING", "IN_PROGRESS", "REQUESTED"} for state in states):
        return ("pending", {"states": states})
    if all(state in {"SUCCESS", "SKIPPED", "NEUTRAL"} for state in states):
        return ("passing", {"states": states})
    return ("pending", {"states": states})


def read_log_tail(log_path: str, max_bytes: int = 12000) -> str:
    if not log_path:
        return ""
    path = Path(log_path)
    if not path.exists() or not path.is_file():
        return ""
    try:
        size = path.stat().st_size
        with path.open("rb") as handle:
            if size > max_bytes:
                handle.seek(-max_bytes, os.SEEK_END)
            data = handle.read()
        return data.decode("utf-8", errors="ignore")
    except Exception:
        return ""


def classify_non_retryable_failure(log_tail: str) -> Optional[Tuple[str, str]]:
    text = (log_tail or "").lower()
    if not text:
        return None

    if "agent_stuck" in text and "origin_not_github_remote" in text:
        return ("non_retryable_remote", "Origin remote is not GitHub; cannot create PR")
    if "gh pr create" in text and ("not github host" in text or "local path" in text):
        return ("non_retryable_remote", "Repository remote is not PR-capable for gh CLI")
    if "please set an auth method" in text and "gemini" in text:
        return ("non_retryable_auth_missing", "Gemini auth is missing")
    if "model not found" in text or "providermodelnotfounderror" in text:
        return ("non_retryable_model_not_found", "Configured model is unavailable for this driver/provider")
    return None


def review_gates(review_data: Dict[str, Any], required_reviews: List[str]) -> Tuple[Dict[str, int], bool]:
    reviews = review_data.get("reviews") if isinstance(review_data.get("reviews"), list) else []
    decision = str(review_data.get("reviewDecision") or "").upper()
    changes_requested = decision == "CHANGES_REQUESTED"

    gates = {
        "review_codex_passed": 0,
        "review_claude_passed": 0,
        "review_gemini_passed": 0,
    }

    generic_approval = decision == "APPROVED"

    for item in reviews:
        if not isinstance(item, dict):
            continue
        state = str(item.get("state") or "").upper()
        if state != "APPROVED":
            continue
        author = item.get("author") if isinstance(item.get("author"), dict) else {}
        login = str(author.get("login") or "").lower()
        if any(token in login for token in ("codex", "openai")):
            gates["review_codex_passed"] = 1
        if any(token in login for token in ("claude", "anthropic")):
            gates["review_claude_passed"] = 1
        if any(token in login for token in ("gemini", "google")):
            gates["review_gemini_passed"] = 1

    if generic_approval:
        if "codex" in required_reviews and gates["review_codex_passed"] == 0:
            gates["review_codex_passed"] = 1
        if "claude" in required_reviews and gates["review_claude_passed"] == 0:
            gates["review_claude_passed"] = 1
        if "gemini" in required_reviews and gates["review_gemini_passed"] == 0:
            gates["review_gemini_passed"] = 1

    return gates, changes_requested


def all_gates_pass(row: sqlite3.Row, checks: sqlite3.Row, required_reviews: List[str]) -> bool:
    if not checks:
        return False
    if not bool(checks["pr_created"]):
        return False
    if not bool(checks["branch_mergeable"]):
        return False
    if not bool(checks["ci_passed"]):
        return False
    if "codex" in required_reviews and not bool(checks["review_codex_passed"]):
        return False
    if "claude" in required_reviews and not bool(checks["review_claude_passed"]):
        return False
    if "gemini" in required_reviews and not bool(checks["review_gemini_passed"]):
        return False

    ui_change = bool(row["ui_change_detected"])
    if ui_change and not bool(checks["ui_screenshot_present"]):
        return False
    return True


def spawn_retry(conn: sqlite3.Connection, config: ProjectConfig, row: sqlite3.Row, evidence: str) -> None:
    task_id = str(row["id"])
    driver_name = str(row["driver"])
    driver = DRIVER_REGISTRY.get(driver_name)
    if driver is None:
        conn.execute(
            "UPDATE tasks SET last_error_code = ?, last_error_reason = ?, updated_at = ? WHERE id = ?",
            ("retry_driver_missing", f"Driver not found: {driver_name}", now_iso(), task_id),
        )
        return

    preflight = driver.preflight()
    if not preflight.get("available"):
        conn.execute(
            "UPDATE tasks SET last_error_code = ?, last_error_reason = ?, updated_at = ? WHERE id = ?",
            ("retry_driver_unavailable", f"Driver unavailable: {driver_name}", now_iso(), task_id),
        )
        return

    attempts = int(row["attempt_count"])
    last_error_code = str(row["last_error_code"] or "")
    if last_error_code.startswith("non_retryable_"):
        set_status(conn, task_id, STATUS_ABANDONED, f"Non-retryable failure: {row['last_error_reason']}", config=config)
        return

    if attempts >= int(row["max_attempts"]):
        set_status(conn, task_id, STATUS_ABANDONED, "Max retries exceeded", config=config)
        conn.execute(
            "UPDATE tasks SET last_error_code = ?, last_error_reason = ?, updated_at = ? WHERE id = ?",
            ("max_retries_exceeded", "Max retries exceeded", now_iso(), task_id),
        )
        return

    branch = str(row["branch"] or branch_for(task_id))
    worktree = str(row["worktree_path"] or worktree_path_for(config, task_id))
    session = str(row["tmux_session"] or session_for(config.repo_path, task_id))
    log_file = str(row["log_path"] or (openclaw_dir(config.repo_path) / "logs" / f"{task_id}.log"))

    original_prompt = str(row["prompt_text"] or "")
    retry_prompt = textwrap.dedent(
        f"""
        {original_prompt}

        RETRY_CONTEXT:
        Previous attempt failed with evidence:
        {evidence[:1800]}

        Focus only on files relevant to this failure and complete DoD.
        """
    ).strip()

    model = normalize_model_for_driver(driver_name, str(row["model"]))
    effort = config.reasoning.get(driver_name, "high")
    try:
        launch = driver.launch(
            DriverContext(
                repo_path=config.repo_path,
                worktree_path=worktree,
                task_id=task_id,
                prompt=build_prompt(retry_prompt, task_id=task_id, branch=branch, base_branch=config.base_branch),
                model=model,
                reasoning_effort=effort,
            )
        )
    except DriverError as error:
        detail = error.result
        conn.execute(
            "UPDATE tasks SET last_error_code = ?, last_error_reason = ?, last_error_evidence = ?, updated_at = ? WHERE id = ?",
            (detail.code, detail.reason, detail.evidence, now_iso(), task_id),
        )
        set_status(conn, task_id, STATUS_FAILED, f"Retry launch failed: {detail.reason}", config=config)
        return

    if session and tmux_has_session(session):
        tmux_kill(session)
    remove_worktree(config.repo_path, worktree)
    delete_branch(config.repo_path, branch)
    create_worktree(config.repo_path, config.base_branch, branch, worktree)

    launch_session(session=session, worktree=worktree, command=launch.command, log_file=log_file)

    next_attempt = attempts + 1
    conn.execute(
        """
        UPDATE tasks
        SET status = ?, attempt_count = ?, model = ?, prompt_text = ?, started_at = ?, completed_at = NULL,
            branch = ?, worktree_path = ?, tmux_session = ?, log_path = ?,
            last_error_code = NULL, last_error_reason = NULL, last_error_evidence = NULL,
            updated_at = ?
        WHERE id = ?
        """,
        (
            STATUS_RUNNING,
            next_attempt,
            launch.model,
            retry_prompt,
            now_iso(),
            branch,
            worktree,
            session,
            log_file,
            now_iso(),
            task_id,
        ),
    )
    insert_attempt(conn, task_id, next_attempt, driver_name, launch.model, session, retry_prompt)
    event(conn, task_id, "retry_spawned", str(row["status"]), STATUS_RUNNING, "Automatic retry launched")


def monitor_one(conn: sqlite3.Connection, config: ProjectConfig, row: sqlite3.Row) -> None:
    task_id = str(row["id"])
    status = str(row["status"])

    session = str(row["tmux_session"] or "")
    tmux_alive = tmux_has_session(session) if session else False

    branch = str(row["branch"] or "")
    pr_list = None
    if branch:
        pr_list = gh_json(
            config.repo_path,
            [
                "gh",
                "pr",
                "list",
                "--state",
                "all",
                "--head",
                branch,
                "--json",
                "number,url,state",
            ],
        )

    pr = pr_list[0] if isinstance(pr_list, list) and pr_list else None

    if pr is None:
        if status == STATUS_RUNNING and not tmux_alive:
            log_tail = read_log_tail(str(row["log_path"] or ""))
            non_retryable = classify_non_retryable_failure(log_tail)
            if non_retryable is not None:
                code, reason = non_retryable
                conn.execute(
                    "UPDATE tasks SET last_error_code = ?, last_error_reason = ?, last_error_evidence = ?, updated_at = ? WHERE id = ?",
                    (code, reason, truncate_text(log_tail, 4000), now_iso(), task_id),
                )
                set_status(conn, task_id, STATUS_ABANDONED, reason, config=config)
                return
            conn.execute(
                "UPDATE tasks SET last_error_code = ?, last_error_reason = ?, updated_at = ? WHERE id = ?",
                ("session_exited_no_pr", "Session exited before PR creation", now_iso(), task_id),
            )
            set_status(conn, task_id, STATUS_FAILED, "Session exited before PR creation", config=config)
        return

    pr_number = int(pr.get("number"))
    pr_url = str(pr.get("url"))
    pr_state = str(pr.get("state") or "").upper()

    conn.execute(
        "UPDATE tasks SET pr_number = ?, pr_url = ?, updated_at = ? WHERE id = ?",
        (pr_number, pr_url, now_iso(), task_id),
    )
    update_checks(conn, task_id, {"pr_created": 1})

    details = gh_json(
        config.repo_path,
        [
            "gh",
            "pr",
            "view",
            str(pr_number),
            "--json",
            "state,mergeable,mergeStateStatus,reviewDecision,reviews,body,files,url",
        ],
    )

    if not isinstance(details, dict):
        details = {}

    if pr_state == "MERGED":
        if status != STATUS_MERGED:
            if status != STATUS_READY:
                # allow direct merge from PR stage
                conn.execute(
                    "UPDATE tasks SET status = ?, completed_at = ?, updated_at = ? WHERE id = ?",
                    (STATUS_MERGED, now_iso(), now_iso(), task_id),
                )
                event(conn, task_id, "status_changed", status, STATUS_MERGED, "PR merged")
            else:
                set_status(conn, task_id, STATUS_MERGED, "PR merged", config=config)
        return

    if pr_state == "CLOSED":
        if status != STATUS_ABANDONED:
            if status in {STATUS_PR_CREATED, STATUS_CI_FAILED, STATUS_CI_PASSED, STATUS_REVIEW_CHANGES, STATUS_READY, STATUS_RUNNING, STATUS_FAILED, STATUS_QUEUED}:
                set_status(conn, task_id, STATUS_ABANDONED, "PR closed", config=config)
        return

    mergeable = str(details.get("mergeable") or "").upper() == "MERGEABLE"
    merge_state = str(details.get("mergeStateStatus") or "").upper()
    branch_mergeable = 1 if mergeable or merge_state in {"CLEAN", "HAS_HOOKS", "UNSTABLE"} else 0

    ci_status, ci_payload = check_ci(config.repo_path, pr_number)
    ci_passed = 1 if ci_status == "passing" else 0

    files = details.get("files") if isinstance(details.get("files"), list) else []
    ui_changed = detect_ui_change(files)
    body = str(details.get("body") or "")
    ui_screenshot = 1 if (not ui_changed or screenshot_present(body)) else 0

    review_flags, changes_requested = review_gates(details, config.required_reviews)

    conn.execute(
        "UPDATE tasks SET ci_status = ?, mergeable = ?, ui_change_detected = ?, updated_at = ? WHERE id = ?",
        (ci_status, branch_mergeable, 1 if ui_changed else 0, now_iso(), task_id),
    )

    update_checks(
        conn,
        task_id,
        {
            "branch_mergeable": branch_mergeable,
            "ci_passed": ci_passed,
            "review_codex_passed": review_flags["review_codex_passed"],
            "review_claude_passed": review_flags["review_claude_passed"],
            "review_gemini_passed": review_flags["review_gemini_passed"],
            "ui_screenshot_present": ui_screenshot,
        },
    )

    # status progression
    current = str(conn.execute("SELECT status FROM tasks WHERE id = ?", (task_id,)).fetchone()["status"])

    if changes_requested:
        if current != STATUS_REVIEW_CHANGES:
            if current == STATUS_RUNNING:
                set_status(conn, task_id, STATUS_PR_CREATED, "PR detected", config=config)
                current = STATUS_PR_CREATED
            set_status(conn, task_id, STATUS_REVIEW_CHANGES, "Review requested changes", config=config)
        return

    if ci_status == "failing":
        if current == STATUS_RUNNING:
            set_status(conn, task_id, STATUS_PR_CREATED, "PR detected", config=config)
            current = STATUS_PR_CREATED
        if current != STATUS_CI_FAILED:
            set_status(conn, task_id, STATUS_CI_FAILED, "CI failed", ci_payload, config=config)
        conn.execute(
            "UPDATE tasks SET last_error_code = ?, last_error_reason = ?, last_error_evidence = ?, updated_at = ? WHERE id = ?",
            ("ci_failed", "CI checks failed", json.dumps(ci_payload, ensure_ascii=False), now_iso(), task_id),
        )
        return

    if ci_status == "passing":
        if current == STATUS_RUNNING:
            set_status(conn, task_id, STATUS_PR_CREATED, "PR detected", config=config)
            current = STATUS_PR_CREATED
        if current in {STATUS_PR_CREATED, STATUS_CI_FAILED}:
            set_status(conn, task_id, STATUS_CI_PASSED, "CI passed", config=config)

    checks = conn.execute("SELECT * FROM task_checks WHERE task_id = ?", (task_id,)).fetchone()
    row_fresh = conn.execute("SELECT * FROM tasks WHERE id = ?", (task_id,)).fetchone()

    if row_fresh is None or checks is None:
        return

    if all_gates_pass(row_fresh, checks, config.required_reviews):
        current = str(row_fresh["status"])
        if current not in {STATUS_READY, STATUS_MERGED, STATUS_ABANDONED}:
            if current == STATUS_RUNNING:
                set_status(conn, task_id, STATUS_PR_CREATED, "PR detected", config=config)
            set_status(conn, task_id, STATUS_READY, "All gates passed", config=config)


def cmd_monitor_tick(args: argparse.Namespace) -> None:
    repo = ensure_repo(args.repo)
    config = load_project_config(repo)

    monitored = 0
    retries = 0
    notifications_sent = 0

    with connect(repo) as conn:
        rows = conn.execute(
            "SELECT * FROM tasks WHERE status IN (?, ?, ?, ?, ?, ?, ?) ORDER BY datetime(updated_at) ASC",
            (
                STATUS_RUNNING,
                STATUS_PR_CREATED,
                STATUS_CI_FAILED,
                STATUS_CI_PASSED,
                STATUS_REVIEW_CHANGES,
                STATUS_READY,
                STATUS_FAILED,
            ),
        ).fetchall()

        for row in rows:
            monitored += 1
            monitor_one(conn, config, row)

        retry_rows = conn.execute(
            "SELECT * FROM tasks WHERE status IN (?, ?, ?) ORDER BY datetime(updated_at) ASC",
            (STATUS_FAILED, STATUS_CI_FAILED, STATUS_REVIEW_CHANGES),
        ).fetchall()

        for row in retry_rows:
            attempts = int(row["attempt_count"])
            max_attempts = int(row["max_attempts"])
            task_id = str(row["id"])
            if attempts >= max_attempts:
                if str(row["status"]) != STATUS_ABANDONED:
                    set_status(conn, task_id, STATUS_ABANDONED, "Max retries exceeded", config=config)
                    conn.execute(
                        "UPDATE tasks SET last_error_code = ?, last_error_reason = ?, updated_at = ? WHERE id = ?",
                        ("max_retries_exceeded", "Max retries exceeded", now_iso(), task_id),
                    )
                continue

            evidence = str(row["last_error_reason"] or "")
            if not evidence:
                evidence = str(row["last_error_evidence"] or "")
            if not evidence:
                evidence = f"status={row['status']}"
            spawn_retry(conn, config, row, evidence)
            retries += 1

        notifications_sent = flush_pending_notifications(conn, config)
        write_projection(conn, repo)

    print(f"repo: {repo}")
    print(f"monitored: {monitored}")
    print(f"retries_launched: {retries}")
    print(f"notifications_sent: {notifications_sent}")


def cmd_cleanup_tick(args: argparse.Namespace) -> None:
    repo = ensure_repo(args.repo)
    cleaned = 0

    with connect(repo) as conn:
        rows = conn.execute(
            "SELECT * FROM tasks WHERE status IN (?, ?) AND cleaned_at IS NULL ORDER BY datetime(updated_at) ASC",
            (STATUS_MERGED, STATUS_ABANDONED),
        ).fetchall()

        for row in rows:
            task_id = str(row["id"])
            session = str(row["tmux_session"] or "")
            worktree = str(row["worktree_path"] or "")
            branch = str(row["branch"] or "")
            status = str(row["status"])

            if session and tmux_has_session(session):
                tmux_kill(session)

            if worktree:
                remove_worktree(repo, worktree)

            if branch:
                delete_branch(repo, branch)

            conn.execute(
                "UPDATE tasks SET cleaned_at = ?, updated_at = ? WHERE id = ?",
                (now_iso(), now_iso(), task_id),
            )
            event(conn, task_id, "cleaned", status, status, "Cleanup completed")
            cleaned += 1

        write_projection(conn, repo)

    print(f"repo: {repo}")
    print(f"cleaned: {cleaned}")


def cmd_status(args: argparse.Namespace) -> None:
    repo = ensure_repo(args.repo)
    with connect(repo) as conn:
        rows = conn.execute(
            """
            SELECT t.*, c.pr_created, c.branch_mergeable, c.ci_passed,
                   c.review_codex_passed, c.review_claude_passed,
                   c.review_gemini_passed, c.ui_screenshot_present
            FROM tasks t
            LEFT JOIN task_checks c ON c.task_id = t.id
            ORDER BY datetime(t.created_at) DESC
            """
        ).fetchall()

    if args.format == "json":
        payload = [dict(row) for row in rows]
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        return

    print("ID | STATUS | DRIVER | ATTEMPTS | PR | BRANCH")
    print("-" * 96)
    for row in rows:
        print(
            f"{row['id']} | {row['status']} | {row['driver']} | "
            f"{row['attempt_count']}/{row['max_attempts']} | {row['pr_number'] or '-'} | {row['branch'] or '-'}"
        )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="swarm", description="30X Swarm Core CLI")
    sub = parser.add_subparsers(dest="command", required=True)

    seed = sub.add_parser("seed", help="Seed project swarm config and storage")
    seed.add_argument("--repo", required=True, help="Absolute repository path")
    seed.set_defaults(func=cmd_seed)

    task = sub.add_parser("task", help="Task operations")
    task_sub = task.add_subparsers(dest="task_command", required=True)

    spawn = task_sub.add_parser("spawn", help="Spawn a new task")
    spawn.add_argument("--repo", required=True)
    spawn.add_argument("--task-id", required=True)
    spawn.add_argument("--driver", required=True, choices=["auto", "codex", "claudecode", "opencode", "gemini-cli", "claude"])
    spawn.add_argument("--prompt-file", required=False)
    spawn.add_argument("--prompt", required=False)
    spawn.set_defaults(func=cmd_task_spawn)

    redirect = task_sub.add_parser("redirect", help="Redirect running task")
    redirect.add_argument("--repo", required=True)
    redirect.add_argument("--task-id", required=True)
    redirect.add_argument("--message", required=True)
    redirect.set_defaults(func=cmd_task_redirect)

    kill = task_sub.add_parser("kill", help="Kill task")
    kill.add_argument("--repo", required=True)
    kill.add_argument("--task-id", required=True)
    kill.set_defaults(func=cmd_task_kill)

    monitor = sub.add_parser("monitor", help="Monitoring operations")
    monitor_sub = monitor.add_subparsers(dest="monitor_command", required=True)
    tick = monitor_sub.add_parser("tick", help="Run one deterministic monitoring cycle")
    tick.add_argument("--repo", required=True)
    tick.set_defaults(func=cmd_monitor_tick)

    cleanup = sub.add_parser("cleanup", help="Cleanup operations")
    cleanup_sub = cleanup.add_subparsers(dest="cleanup_command", required=True)
    cleanup_tick = cleanup_sub.add_parser("tick", help="Run one cleanup cycle")
    cleanup_tick.add_argument("--repo", required=True)
    cleanup_tick.set_defaults(func=cmd_cleanup_tick)

    status = sub.add_parser("status", help="Show task status")
    status.add_argument("--repo", required=True)
    status.add_argument("--format", choices=["table", "json"], default="table")
    status.set_defaults(func=cmd_status)

    return parser


def main(argv: Optional[List[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    args.func(args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
