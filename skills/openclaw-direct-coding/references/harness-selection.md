<!--
[INPUT]: 依赖当前支持的 coding harness 与公开定位
[OUTPUT]: 对外提供 harness 推荐口径与选择规则
[POS]: openclaw-direct-coding 的参考规则文件，被 `SKILL.md` 按需引用
[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
-->

# Harness Selection

Use these defaults when the user asks which coding harness to use:

- `Codex`: best default for backend work, debugging, multi-file reasoning, and codebase surgery
- `Claude Code`: strong for frontend, copy-heavy UI edits, and rapid iteration
- `OpenCode`: use when the environment or operator already prefers OpenCode flows
- `Gemini CLI`: use only when Gemini is explicitly requested or that environment is already provisioned

Simple recommendation pattern:

- backend / reasoning-heavy: recommend `Codex`
- frontend / UI polish: recommend `Claude Code`
- existing OpenCode setup: recommend `OpenCode`
- explicit Gemini preference: recommend `Gemini CLI`

If you still lack enough information, ask the user to choose instead of guessing.
