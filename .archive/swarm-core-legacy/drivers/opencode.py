#!/usr/bin/env python3
"""
[INPUT]: OpenCode CLI availability and DriverContext with prompt/model/variant settings.
[OUTPUT]: Launch command for OpenCode run mode and capability report.
[POS]: swarm-core OpenCode driver; execution adapter for opencode run workflows.
[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
"""

from __future__ import annotations

import shutil
import shlex
from typing import Dict

from .base import BaseDriver, DriverContext, DriverError, DriverLaunchResult


class OpenCodeDriver(BaseDriver):
    name = "opencode"

    def preflight(self) -> Dict[str, object]:
        path = shutil.which("opencode")
        return {
            "available": bool(path),
            "binary": path,
            "supportsRedirect": True,
        }

    def launch(self, ctx: DriverContext) -> DriverLaunchResult:
        if not shutil.which("opencode"):
            raise DriverError(
                code="driver_unavailable",
                reason="opencode CLI is not installed or not in PATH",
            )

        variant = ctx.reasoning_effort or "high"
        model_arg = f"--model {shlex.quote(ctx.model)} " if (ctx.model or "").strip() else ""
        command = (
            "opencode run "
            f"{model_arg}"
            f"--variant {shlex.quote(variant)} "
            f"{shlex.quote(ctx.prompt)}"
        )
        return DriverLaunchResult(command=command, model=ctx.model)
