#!/usr/bin/env python3
"""
[INPUT]: Codex CLI availability and DriverContext with prompt/model/reasoning settings.
[OUTPUT]: Launch command for Codex execution mode and preflight capability report.
[POS]: swarm-core Codex driver; primary backend and multi-file execution adapter.
[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
"""

from __future__ import annotations

import shutil
import shlex
from typing import Dict

from .base import BaseDriver, DriverContext, DriverError, DriverLaunchResult


class CodexDriver(BaseDriver):
    name = "codex"

    def preflight(self) -> Dict[str, object]:
        path = shutil.which("codex")
        return {
            "available": bool(path),
            "binary": path,
            "supportsRedirect": True,
        }

    def launch(self, ctx: DriverContext) -> DriverLaunchResult:
        if not shutil.which("codex"):
            raise DriverError(
                code="driver_unavailable",
                reason="codex CLI is not installed or not in PATH",
            )

        model_arg = f"--model {shlex.quote(ctx.model)} " if (ctx.model or "").strip() else ""
        command = (
            "codex exec "
            f"{model_arg}"
            f"-c {shlex.quote(f'model_reasoning_effort={ctx.reasoning_effort}')} "
            "--dangerously-bypass-approvals-and-sandbox "
            f"{shlex.quote(ctx.prompt)}"
        )
        return DriverLaunchResult(command=command, model=ctx.model)
