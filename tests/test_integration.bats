#!/usr/bin/env bats
# =============================================================================
# test_integration.bats — End-to-end tests for delivery CLI
# =============================================================================
# [INPUT]:  delivery CLI binary at skills/delivery/bin/delivery
# [OUTPUT]: Validates init, status, help, and error handling through the CLI
# [POS]:   Integration tests; exercises the full binary dispatch path
# [PROTOCOL]: Update this header on change, then check CLAUDE.md
# =============================================================================

setup() {
  TEST_DIR="$(mktemp -d)"
  DELIVERY="$(cd "$(dirname "$BATS_TEST_FILENAME")/../skills/delivery/bin" && pwd)/delivery"

  # Create temp git repo with initial commit
  git -C "$TEST_DIR" init -q
  git -C "$TEST_DIR" commit --allow-empty -m "init" -q
}

teardown() {
  rm -rf "$TEST_DIR"
}

# -- delivery init -----------------------------------------------------------

@test "delivery init --repo creates swarm.db" {
  run "$DELIVERY" init --repo "$TEST_DIR"
  [ "$status" -eq 0 ]
  [ -f "$TEST_DIR/.openclaw/swarm.db" ]
}

# -- delivery status ---------------------------------------------------------

@test "delivery status --repo returns empty on fresh DB" {
  "$DELIVERY" init --repo "$TEST_DIR"

  run "$DELIVERY" status --repo "$TEST_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No tasks found"* ]]
}

@test "delivery status --repo --format json returns empty JSON array" {
  "$DELIVERY" init --repo "$TEST_DIR"

  run "$DELIVERY" status --repo "$TEST_DIR" --format json
  [ "$status" -eq 0 ]
  # sqlite3 -json returns empty string (no output) for zero rows
  [[ -z "$output" || "$output" == "[]" ]]
}

# -- delivery --help ---------------------------------------------------------

@test "delivery --help exits 0" {
  run "$DELIVERY" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage"* ]]
}

# -- delivery with no args ---------------------------------------------------

@test "delivery with no args exits 1" {
  run "$DELIVERY"
  [ "$status" -eq 1 ]
}

# -- delivery init without --repo -------------------------------------------

@test "delivery init without --repo exits with error" {
  run "$DELIVERY" init
  [ "$status" -ne 0 ]
  [[ "$output" == *"Missing required --repo"* ]]
}
