#!/usr/bin/env python3
"""
[INPUT]: Gemini CLI availability and DriverContext with prompt/model metadata.
[OUTPUT]: Launch command for Gemini CLI headless execution and capability report.
[POS]: swarm-core Gemini CLI driver; execution adapter for Gemini-based coding tasks.
[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
"""

from __future__ import annotations

import shutil
import shlex
from typing import Dict

from .base import BaseDriver, DriverContext, DriverError, DriverLaunchResult


class GeminiCliDriver(BaseDriver):
    name = "gemini-cli"

    def preflight(self) -> Dict[str, object]:
        path = shutil.which("gemini")
        return {
            "available": bool(path),
            "binary": path,
            "supportsRedirect": True,
        }

    def launch(self, ctx: DriverContext) -> DriverLaunchResult:
        if not shutil.which("gemini"):
            raise DriverError(
                code="driver_unavailable",
                reason="gemini CLI is not installed or not in PATH",
            )

        command = (
            "gemini "
            f"--model {shlex.quote(ctx.model)} "
            "--approval-mode yolo "
            f"--prompt {shlex.quote(ctx.prompt)}"
        )
        return DriverLaunchResult(command=command, model=ctx.model)
