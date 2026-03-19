#!/usr/bin/env bats
# =============================================================================
# test_drivers.bats — Unit tests for drivers.sh functions
# =============================================================================
# [INPUT]:  common.sh + drivers.sh functions
# [OUTPUT]: Validates driver command building, model normalization, alias resolution
# [POS]:   Driver layer tests; exercises build_driver_command, normalize_model,
#          resolve_driver without requiring actual CLI binaries
# [PROTOCOL]: Update this header on change, then check CLAUDE.md
# =============================================================================

setup() {
  TEST_DIR="$(mktemp -d)"
  RUNTIME_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../skills/delivery/bin" && pwd)"

  # Unset guards to allow re-sourcing
  unset _COMMON_SH_LOADED
  unset _DRIVERS_SH_LOADED

  source "$RUNTIME_DIR/lib/common.sh"
  source "$RUNTIME_DIR/lib/drivers.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# -- build_driver_command ----------------------------------------------------

@test "build_driver_command produces correct command for codex" {
  run build_driver_command codex "fix bug" "gpt-5" "high"
  [ "$status" -eq 0 ]
  [[ "$output" == *"codex exec"* ]]
}

@test "build_driver_command produces correct command for claudecode" {
  run build_driver_command claudecode "fix bug" "sonnet" "high"
  [ "$status" -eq 0 ]
  [[ "$output" == *"claude"* ]]
}

@test "build_driver_command produces correct command for opencode" {
  run build_driver_command opencode "fix bug" "gpt-5" "high"
  [ "$status" -eq 0 ]
  [[ "$output" == *"opencode run"* ]]
}

@test "build_driver_command produces correct command for gemini-cli" {
  run build_driver_command gemini-cli "fix bug" "gemini-pro" "high"
  [ "$status" -eq 0 ]
  [[ "$output" == *"gemini"* ]]
}

@test "build_driver_command omits --model when model is empty" {
  run build_driver_command codex "fix bug" "" "high"
  [ "$status" -eq 0 ]
  [[ "$output" != *"--model"* ]]
}

# -- normalize_model ---------------------------------------------------------

@test "normalize_model strips prefix for codex" {
  run normalize_model codex "openai/gpt-5"
  [ "$status" -eq 0 ]
  [ "$output" = "gpt-5" ]
}

@test "normalize_model adds prefix for opencode" {
  run normalize_model opencode "gpt-5"
  [ "$status" -eq 0 ]
  [ "$output" = "default/gpt-5" ]
}

@test "normalize_model handles opencode special case" {
  run normalize_model opencode "openai/gpt-5.3-codex"
  [ "$status" -eq 0 ]
  # The special case in code: "openai/gpt-5.3-codex" maps to "default/gpt-5.3-codex"
  [ "$output" = "default/gpt-5.3-codex" ]
}

# -- resolve_driver ----------------------------------------------------------

@test "resolve_driver maps claude alias to claudecode" {
  # Override check_driver_available to always succeed
  check_driver_available() { return 0; }
  export -f check_driver_available

  run resolve_driver "claude" "some prompt"
  [ "$status" -eq 0 ]
  [ "$output" = "claudecode" ]
}
