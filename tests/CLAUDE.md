# tests/
> L2 | Parent: AGENTS.md

Bats integration tests for the delivery CLI. Exercises lib modules and CLI binary in isolation.

## Members

- `test_common.bats`: Tests common.sh — now_iso, ensure_repo, load_config, db_path
- `test_drivers.bats`: Tests drivers.sh — build_driver_command, normalize_model, resolve_driver
- `test_state.bats`: Tests state.sh — check_transition, cmd_init, cmd_status, transition map completeness
- `test_integration.bats`: E2E tests — delivery CLI binary dispatch (init, status, help, error paths)

## Run

```bash
bats tests/
```

## Rules

- No tests that require tmux, real driver CLIs, or network access
- Each test file sources lib modules directly; integration tests invoke the delivery binary
- Tests create temp git repos in setup() and clean up in teardown()

[PROTOCOL]: Update this header on change, then check CLAUDE.md
