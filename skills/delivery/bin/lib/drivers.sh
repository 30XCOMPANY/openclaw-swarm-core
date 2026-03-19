#!/usr/bin/env bash
# =============================================================================
# drivers.sh — Driver selection, command building, model normalization
# =============================================================================
# [INPUT]:  common.sh config vars (CONF_DRIVER_*), CLI binary availability
# [OUTPUT]: check_driver_available, normalize_model, build_driver_command,
#           resolve_driver — four functions replacing legacy Python driver classes
# [POS]:   Driver abstraction layer; consumed by spawn/run modules to dispatch
#          tasks to codex, claude, opencode, or gemini CLIs
# [PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
# =============================================================================

# -- Guard against double-source --
[[ -n "${_DRIVERS_SH_LOADED:-}" ]] && return 0
readonly _DRIVERS_SH_LOADED=1

# =============================================================================
# Constants
# =============================================================================

readonly KNOWN_DRIVERS="codex claudecode opencode gemini-cli"
readonly FRONTEND_KEYWORDS="frontend|ui|css|tailwind|component|layout|style"

# =============================================================================
# check_driver_available — test whether a driver's CLI binary is in PATH
# =============================================================================

check_driver_available() {
  case "$1" in
    codex)      command -v codex    >/dev/null 2>&1 ;;
    claudecode) command -v claude   >/dev/null 2>&1 ;;
    opencode)   command -v opencode >/dev/null 2>&1 ;;
    gemini-cli) command -v gemini   >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

# =============================================================================
# normalize_model — adapt model string to the CLI's expected format
#   codex, claudecode, gemini-cli: strip provider/ prefix
#   opencode: ensure provider/ prefix (default "default/")
# =============================================================================

normalize_model() {
  local driver="${1:?usage: normalize_model <driver> <model>}"
  local model="${2:-}"

  [[ -z "$model" ]] && return 0

  case "$driver" in
    codex|claudecode|gemini-cli)
      # Strip provider prefix — these CLIs want bare model IDs
      if [[ "$model" == */* ]]; then
        printf '%s' "${model#*/}"
      else
        printf '%s' "$model"
      fi
      ;;
    opencode)
      # OpenCode expects provider/model format
      if [[ "$model" == "openai/gpt-5.3-codex" ]]; then
        printf '%s' "default/gpt-5.3-codex"
      elif [[ "$model" != */* ]]; then
        printf '%s' "default/${model}"
      else
        printf '%s' "$model"
      fi
      ;;
    *)
      printf '%s' "$model"
      ;;
  esac
}

# =============================================================================
# build_driver_command — assemble the exact CLI invocation string
#   Args: driver, prompt, model (optional), reasoning (optional)
# =============================================================================

build_driver_command() {
  local driver="${1:?usage: build_driver_command <driver> <prompt> [model] [reasoning]}"
  local prompt="${2:?usage: build_driver_command <driver> <prompt> [model] [reasoning]}"
  local model="${3:-}"
  local reasoning="${4:-}"

  local model_arg=""
  local q_prompt
  q_prompt="$(printf '%q' "$prompt")"

  case "$driver" in
    codex)
      [[ -n "$model" ]] && model_arg="--model $(printf '%q' "$model") "
      local effort="${reasoning:-high}"
      printf '%s' "codex exec ${model_arg}-c $(printf '%q' "model_reasoning_effort=${effort}") --dangerously-bypass-approvals-and-sandbox ${q_prompt}"
      ;;
    claudecode)
      [[ -n "$model" ]] && model_arg="--model $(printf '%q' "$model") "
      printf '%s' "claude ${model_arg}--dangerously-skip-permissions -p ${q_prompt}"
      ;;
    opencode)
      [[ -n "$model" ]] && model_arg="--model $(printf '%q' "$model") "
      local variant="${reasoning:-high}"
      printf '%s' "opencode run ${model_arg}--variant $(printf '%q' "$variant") ${q_prompt}"
      ;;
    gemini-cli)
      [[ -n "$model" ]] && model_arg="--model $(printf '%q' "$model") "
      printf '%s' "gemini ${model_arg}--approval-mode yolo --prompt ${q_prompt}"
      ;;
    *)
      die "Unknown driver: $driver"
      ;;
  esac
}

# =============================================================================
# _is_driver_enabled — check config flag for a driver
# =============================================================================

_is_driver_enabled() {
  local driver="$1"
  case "$driver" in
    codex)      [[ "${CONF_DRIVER_CODEX_ENABLED:-true}"      == "true" ]] ;;
    claudecode) [[ "${CONF_DRIVER_CLAUDECODE_ENABLED:-true}"  == "true" ]] ;;
    opencode)   [[ "${CONF_DRIVER_OPENCODE_ENABLED:-true}"    == "true" ]] ;;
    gemini-cli) [[ "${CONF_DRIVER_GEMINI_CLI_ENABLED:-true}"  == "true" ]] ;;
    *) return 1 ;;
  esac
}

# =============================================================================
# resolve_driver — auto-select or validate a requested driver
#   Args: requested_driver, prompt_text
#   Uses: CONF_DEFAULT_DRIVER, CONF_DRIVER_*_ENABLED
#   Prints: resolved driver name
# =============================================================================

resolve_driver() {
  local requested="${1:?usage: resolve_driver <driver> <prompt_text>}"
  local prompt_text="${2:-}"

  requested="$(printf '%s' "$requested" | tr '[:upper:]' '[:lower:]')"

  # Alias
  [[ "$requested" == "claude" ]] && requested="claudecode"

  # -- Explicit driver --
  if [[ "$requested" != "auto" ]]; then
    local known=false
    for d in $KNOWN_DRIVERS; do
      [[ "$d" == "$requested" ]] && known=true && break
    done
    [[ "$known" == "true" ]] || die "Unsupported driver: $requested"
    _is_driver_enabled "$requested" || die "Driver disabled in config: $requested"
    check_driver_available "$requested" || die "Driver not installed: $requested"
    printf '%s' "$requested"
    return 0
  fi

  # -- Auto selection --
  local preferred="${CONF_DEFAULT_DRIVER:-codex}"
  local lower_prompt
  lower_prompt="$(printf '%s' "$prompt_text" | tr '[:upper:]' '[:lower:]')"

  if printf '%s' "$lower_prompt" | grep -qE "$FRONTEND_KEYWORDS"; then
    preferred="claudecode"
  fi

  # Fallback order: preferred first, then codex > opencode > claudecode > gemini-cli
  local candidate
  local seen=""
  for candidate in "$preferred" codex opencode claudecode gemini-cli; do
    # Deduplicate
    case " $seen " in
      *" $candidate "*) continue ;;
    esac
    seen="$seen $candidate"

    _is_driver_enabled "$candidate" || continue
    check_driver_available "$candidate" || continue
    printf '%s' "$candidate"
    return 0
  done

  die "No available driver found for auto selection"
}
