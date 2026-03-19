#!/usr/bin/env python3
"""
[INPUT]: DriverContext from swarm_core runtime, shell environment with installed coding CLIs.
[OUTPUT]: BaseDriver protocol and DriverLaunchResult used by concrete CLI drivers.
[POS]: swarm-core/drivers protocol layer; isolates tool-specific launch semantics from orchestration state machine.
[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Dict, Optional


@dataclass(slots=True)
class DriverContext:
    repo_path: str
    worktree_path: str
    task_id: str
    prompt: str
    model: str
    reasoning_effort: str


@dataclass(slots=True)
class DriverLaunchResult:
    command: str
    model: str


@dataclass(slots=True)
class DriverErrorResult:
    code: str
    reason: str
    evidence: str


class DriverError(RuntimeError):
    def __init__(self, code: str, reason: str, evidence: str = "") -> None:
        super().__init__(reason)
        self.result = DriverErrorResult(code=code, reason=reason, evidence=evidence)


class BaseDriver:
    name: str = "base"

    def preflight(self) -> Dict[str, object]:
        raise NotImplementedError

    def launch(self, ctx: DriverContext) -> DriverLaunchResult:
        raise NotImplementedError

    def normalize_error(self, raw: str) -> DriverErrorResult:
        text = (raw or "").strip()
        if not text:
            return DriverErrorResult(code="unknown", reason="Unknown execution error", evidence="")
        return DriverErrorResult(code="exec_failed", reason="Driver execution failed", evidence=text[:2000])
