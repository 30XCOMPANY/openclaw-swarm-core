# coding/
> L2 | Parent: skills/CLAUDE.md

Pure text skill — tells agents what coding harnesses exist, what each can do, and how to operate them through ACP. No executable scripts.

## Members

- `SKILL.md`: Skill entrypoint with frontmatter, usage protocol, and escalation rules
- `agents/openai.yaml`: OpenAI-compatible agent manifest for /coding invocation
- `references/harness-selection.md`: Four harness positions and recommendation rules
- `references/acp-guide.md`: Complete ACP bridge operations reference (session model, acpx, flags, supported ops)
- `references/harness-capabilities.md`: Per-harness CLI flags, invocation patterns, capability matrix

## Architecture Notes

- This skill contains zero executable code — it is pure guidance for AI agents
- Harness CLI flags are derived from the archived Python drivers in `.archive/swarm-core-legacy/drivers/`
- ACP operations describe the Gateway-backed bridge, not a full ACP-native runtime

[PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
