<!--
[INPUT]: Harness availability on PATH, task characteristics, user preference
[OUTPUT]: Harness recommendation rules and position definitions
[POS]: /coding reference doc; consumed by agents to decide which harness to invoke
[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
-->

# Harness Selection

Four coding harnesses are available. Each occupies a distinct position.

## Harness Positions

### Codex (default)

**Binary:** `codex`
**Position:** Backend, debugging, multi-file reasoning
**When:** General-purpose coding, backend logic, complex debugging, refactoring across multiple files, tasks requiring deep reasoning chains

Codex is the default harness. Use it unless there is a specific reason to choose another.

### Claude Code

**Binary:** `claude`
**Position:** Frontend, UI, rapid iteration
**When:** Frontend components, UI styling, CSS/Tailwind work, rapid iteration cycles, tasks where the user wants fast visual feedback

Use Claude Code when the task involves frontend keywords: `frontend`, `ui`, `css`, `tailwind`, `component`, `layout`, `style`, `design`, `responsive`.

### OpenCode

**Binary:** `opencode`
**Position:** OpenCode-native workflows
**When:** The user explicitly requests OpenCode, or the project is set up with OpenCode-specific configuration

Use OpenCode only when the user prefers OpenCode flows or the project context demands it.

### Gemini CLI

**Binary:** `gemini`
**Position:** Gemini-specific requests
**When:** The user explicitly requests Gemini

Use Gemini CLI only on explicit user request. It is not auto-selected.

## Selection Rules

1. **Explicit request wins.** If the user names a harness, use it.
2. **Frontend signal -> Claude Code.** If the task description contains frontend keywords and Claude Code is available, recommend Claude Code.
3. **Default -> Codex.** For all other tasks, use Codex.
4. **Fallback chain.** If the selected harness is unavailable: `codex` -> `claude` -> `opencode` -> `gemini`. First available wins.
5. **Always confirm.** State your selection and reasoning before executing. Let the user override.

## Boundary: When to Recommend /delivery

If the user's request implies any of these, recommend `/delivery` instead of `/coding`:

- "Create a PR"
- "Track this task"
- "Run CI and wait for it to pass"
- "Retry if it fails"
- "Monitor progress"
- Multi-step orchestration across branches

`/coding` is for direct, synchronous execution. `/delivery` is for tracked, asynchronous delivery with gates and retries.
