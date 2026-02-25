#!/usr/bin/env python3
"""
[INPUT]: Driver name requested by orchestration runtime.
[OUTPUT]: Instantiated BaseDriver implementations by registered name.
[POS]: swarm-core driver registry and composition root for execution adapters.
[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
"""

from __future__ import annotations

from typing import Dict

from .base import BaseDriver
from .claudecode import ClaudeCodeDriver
from .codex import CodexDriver
from .gemini_cli import GeminiCliDriver
from .opencode import OpenCodeDriver


DRIVER_REGISTRY: Dict[str, BaseDriver] = {
    "codex": CodexDriver(),
    "claudecode": ClaudeCodeDriver(),
    "opencode": OpenCodeDriver(),
    "gemini-cli": GeminiCliDriver(),
}
