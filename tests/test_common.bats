#!/usr/bin/env bats
# =============================================================================
# test_common.bats — Unit tests for common.sh utilities
# =============================================================================
# [INPUT]:  common.sh functions (now_iso, ensure_repo, load_config, db_path)
# [OUTPUT]: Validates core utility behavior in isolation
# [POS]:   Foundation test suite; exercises the lowest layer of delivery CLI
# [PROTOCOL]: Update this header on change, then check CLAUDE.md
# =============================================================================

setup() {
  TEST_DIR="$(mktemp -d)"
  RUNTIME_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../skills/delivery/bin" && pwd)"

  # Unset guard to allow re-sourcing across tests
  unset _COMMON_SH_LOADED

  source "$RUNTIME_DIR/lib/common.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# -- now_iso -----------------------------------------------------------------

@test "now_iso returns valid ISO timestamp" {
  run now_iso
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]
}

# -- ensure_repo -------------------------------------------------------------

@test "ensure_repo fails on non-git directory" {
  run ensure_repo "$TEST_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Not a git repository"* ]]
}

@test "ensure_repo succeeds on git directory" {
  git -C "$TEST_DIR" init -q
  run ensure_repo "$TEST_DIR"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

# -- load_config -------------------------------------------------------------

@test "load_config sets defaults when no conf file" {
  git -C "$TEST_DIR" init -q
  mkdir -p "$TEST_DIR/.openclaw"

  # Ensure env overrides are unset so defaults flow through
  unset DELIVERY_DEFAULT_DRIVER
  unset DELIVERY_MAX_ATTEMPTS

  load_config "$TEST_DIR"

  [ "$CONF_DEFAULT_DRIVER" = "codex" ]
  [ "$CONF_MAX_ATTEMPTS" = "3" ]
}

@test "load_config overrides from conf file" {
  git -C "$TEST_DIR" init -q
  mkdir -p "$TEST_DIR/.openclaw"
  cat > "$TEST_DIR/.openclaw/delivery.conf" <<'CONF'
CONF_DEFAULT_DRIVER="claudecode"
CONF_MAX_ATTEMPTS=5
CONF

  load_config "$TEST_DIR"

  [ "$CONF_DEFAULT_DRIVER" = "claudecode" ]
  [ "$CONF_MAX_ATTEMPTS" = "5" ]
}

# -- db_path -----------------------------------------------------------------

@test "db_path returns correct path pattern" {
  local result
  result="$(db_path "$TEST_DIR")"
  [[ "$result" == *"/.openclaw/swarm.db" ]]
}
