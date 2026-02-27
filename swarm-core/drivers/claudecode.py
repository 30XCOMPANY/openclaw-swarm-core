#!/usr/bin/env python3
"""
[INPUT]: Claude Code CLI availability and DriverContext with prompt/model settings.
[OUTPUT]: Launch command for Claude Code non-interactive execution and preflight report.
[POS]: swarm-core ClaudeCode driver; optimized for frontend and fast iteration workloads.
[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
"""

from __future__ import annotations

import shutil
import shlex
from typing import Dict

from .base import BaseDriver, DriverContext, DriverError, DriverLaunchResult


class ClaudeCodeDriver(BaseDriver):
    name = "claudecode"

    def preflight(self) -> Dict[str, object]:
        path = shutil.which("claude")
        return {
            "available": bool(path),
            "binary": path,
            "supportsRedirect": True,
        }

    def launch(self, ctx: DriverContext) -> DriverLaunchResult:
        if not shutil.which("claude"):
            raise DriverError(
                code="driver_unavailable",
                reason="claude CLI is not installed or not in PATH",
            )

        model_arg = f"--model {shlex.quote(ctx.model)} " if (ctx.model or "").strip() else ""
        command = (
            "claude "
            f"{model_arg}"
            "--dangerously-skip-permissions "
            f"-p {shlex.quote(ctx.prompt)}"
        )
        return DriverLaunchResult(command=command, model=ctx.model)
