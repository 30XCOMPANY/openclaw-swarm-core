---
name: coding
description: "Direct coding through ACP-connected coding harnesses. Use when the task is synchronous, conversational, and does not need PR/gate/retry orchestration."
user-invocable: true
argument-hint: "[task and optional harness]"
metadata: {"openclaw":{"primaryEnv":"OPENCLAW_GATEWAY_TOKEN"}}
---

<!--
[INPUT]: User coding request with optional harness preference
[OUTPUT]: Harness selection guidance, ACP operation instructions, execution protocol
[POS]: /coding skill entrypoint; the only user-facing surface for direct coding operations
[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
-->

# /coding

Direct coding through ACP-connected coding harnesses.

## When to Use /coding

Use `/coding` when the task is:
- Synchronous and conversational — you are present in the loop
- Single-shot or iterative within the current session
- Does not require PR gates, CI monitoring, or retry orchestration

## When to Escalate to /delivery

Escalate to `/delivery` when the task needs:
- PR creation with CI/review gates
- Tracked state machine lifecycle (queued -> running -> pr_created -> merged)
- Evidence-driven retry on failure
- Multi-task parallel execution with monitoring
- Notification routing to external channels

If the user asks for "tracked delivery", "PR workflow", "monitored task", or mentions gates/retries, recommend `/delivery` instead.

## Execution Protocol

### 1. Confirm Harness Selection

Before executing, always confirm the harness choice with the user. State:
- Which harness you will use and why
- The model (if overriding the default)
- The working directory / repo context

See [harness-selection.md](references/harness-selection.md) for selection rules.

### 2. Execute via ACP

Route the coding task through the ACP bridge. The agent does not invoke CLIs directly — it sends prompts through ACP session routing.

See [acp-guide.md](references/acp-guide.md) for the complete ACP operations reference.

### 3. Report Results

After execution, report concrete results:
- What files were created, modified, or deleted
- What tests were run and their outcomes
- Any errors encountered and how they were resolved
- A summary of what was accomplished vs what was requested

Do not report "I think it worked" — report evidence.

## Reference Documents

| Document | Purpose |
|----------|---------|
| [harness-selection.md](references/harness-selection.md) | Which harness to pick and when |
| [acp-guide.md](references/acp-guide.md) | ACP bridge operations, session model, CLI flags |
| [harness-capabilities.md](references/harness-capabilities.md) | Per-harness CLI flags, modes, and boundaries |
