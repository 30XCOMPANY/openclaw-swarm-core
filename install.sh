#!/usr/bin/env bash
# [INPUT]: This repository checkout and optional flags (--target/--yes/--link-bin).
# [OUTPUT]: Installed skills under ~/.openclaw/skills/ plus optional ~/.local/bin/delivery symlink.
# [POS]: Distribution installer for 30X Swarm skills-first package.
# [PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_SKILLS="$ROOT_DIR/skills"
TARGET_DIR="$HOME/.openclaw/skills"
ASSUME_YES=0
LINK_BIN=0

# -- Usage -------------------------------------------------------------------

usage() {
  cat <<'USAGE'
Usage:
  ./install.sh [--target <path>] [--yes] [--link-bin]

Options:
  --target <path>  Install destination (default: ~/.openclaw/skills)
  --yes            Skip confirmation prompt
  --link-bin       Create/update ~/.local/bin/delivery symlink
USAGE
}

# -- Flag parsing ------------------------------------------------------------

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      TARGET_DIR="${2:-}"
      shift 2
      ;;
    --yes)
      ASSUME_YES=1
      shift
      ;;
    --link-bin)
      LINK_BIN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

# -- Validate source ---------------------------------------------------------

for skill in coding delivery; do
  if [[ ! -d "$SRC_SKILLS/$skill" ]]; then
    echo "ERROR: missing source dir: $SRC_SKILLS/$skill" >&2
    exit 1
  fi
done

TARGET_DIR="$(eval echo "$TARGET_DIR")"

# -- Confirm -----------------------------------------------------------------

if [[ $ASSUME_YES -ne 1 ]]; then
  echo "Install skills to: $TARGET_DIR"
  read -r -p "Continue? [y/N] " answer
  if [[ ! "$answer" =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
  fi
fi

# -- Backup existing install -------------------------------------------------

if [[ -e "$TARGET_DIR" ]]; then
  BACKUP_PATH="${TARGET_DIR}.bak.$(date +%Y%m%d%H%M%S)"
  mv "$TARGET_DIR" "$BACKUP_PATH"
  echo "Backup created: $BACKUP_PATH"
fi

# -- Copy skills -------------------------------------------------------------

mkdir -p "$TARGET_DIR"
cp -R "$SRC_SKILLS/coding"  "$TARGET_DIR/coding"
cp -R "$SRC_SKILLS/delivery" "$TARGET_DIR/delivery"

# -- Set permissions ---------------------------------------------------------

chmod +x "$TARGET_DIR/delivery/bin/delivery"
find "$TARGET_DIR/delivery/bin/lib" -type f -name '*.sh' -exec chmod +x {} \;

# -- Link CLI ----------------------------------------------------------------

if [[ $LINK_BIN -eq 1 ]]; then
  mkdir -p "$HOME/.local/bin"
  ln -sf "$TARGET_DIR/delivery/bin/delivery" "$HOME/.local/bin/delivery"
  echo "Linked: $HOME/.local/bin/delivery -> $TARGET_DIR/delivery/bin/delivery"
fi

# -- Done --------------------------------------------------------------------

cat <<DONE
Install complete.
- skills: $TARGET_DIR/coding, $TARGET_DIR/delivery
- command: delivery --help
DONE
