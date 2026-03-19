#!/usr/bin/env bats
# =============================================================================
# test_state.bats — Unit tests for state.sh state machine
# =============================================================================
# [INPUT]:  common.sh + drivers.sh + git-ops.sh + notify.sh + state.sh
# [OUTPUT]: Validates state transitions, cmd_init, cmd_status, transition map
# [POS]:   State machine tests; exercises check_transition and command handlers
# [PROTOCOL]: Update this header on change, then check CLAUDE.md
# =============================================================================

setup() {
  TEST_DIR="$(mktemp -d)"
  RUNTIME_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../skills/delivery/bin" && pwd)"
  export RUNTIME_DIR

  # Unset all guards for clean re-source
  unset _COMMON_SH_LOADED
  unset _DRIVERS_SH_LOADED
  unset _GIT_OPS_SH_LOADED
  unset _NOTIFY_SH_LOADED
  unset _STATE_SH_LOADED

  SCRIPT_DIR="$RUNTIME_DIR/lib"
  export SCRIPT_DIR

  source "$RUNTIME_DIR/lib/state.sh"

  # Create a temp git repo with initial commit for DB operations
  git -C "$TEST_DIR" init -q
  git -C "$TEST_DIR" commit --allow-empty -m "init" -q
}

teardown() {
  rm -rf "$TEST_DIR"
}

# -- check_transition --------------------------------------------------------

@test "check_transition allows valid transition (queued -> running)" {
  run check_transition "queued" "running"
  [ "$status" -eq 0 ]
}

@test "check_transition rejects invalid transition (queued -> merged)" {
  run check_transition "queued" "merged"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Illegal state transition"* ]]
}

@test "check_transition allows same-state (no-op)" {
  run check_transition "running" "running"
  [ "$status" -eq 0 ]
}

# -- cmd_init ----------------------------------------------------------------

@test "cmd_init creates swarm.db with correct tables" {
  run cmd_init --repo "$TEST_DIR"
  [ "$status" -eq 0 ]

  local db="$TEST_DIR/.openclaw/swarm.db"
  [ -f "$db" ]

  local tables
  tables="$(sqlite3 "$db" ".tables")"
  [[ "$tables" == *"tasks"* ]]
  [[ "$tables" == *"task_events"* ]]
  [[ "$tables" == *"task_checks"* ]]
  [[ "$tables" == *"task_attempts"* ]]
}

# -- cmd_status --------------------------------------------------------------

@test "cmd_status on empty DB returns no tasks" {
  cmd_init --repo "$TEST_DIR"

  run cmd_status --repo "$TEST_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No tasks found"* ]]
}

# -- Transition map completeness ---------------------------------------------

@test "state transition map has all 10 states defined" {
  local expected_states="queued running pr_created ci_failed ci_passed review_changes_requested ready_to_merge merged failed abandoned"
  local count=0
  for state in $expected_states; do
    # _allowed_transitions returns "" for terminal states but still handles them
    # Verify the function recognizes each state (doesn't fall through to *)
    local result
    result="$(_allowed_transitions "$state")"
    # For non-terminal states, result should be non-empty
    # For terminal states (merged, abandoned), result is empty — that's valid
    case "$state" in
      merged|abandoned) true ;; # empty is correct
      *) [ -n "$result" ] ;;    # must have at least one target
    esac
    (( count++ ))
  done
  [ "$count" -eq 10 ]
}
