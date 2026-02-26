#!/usr/bin/env bash
# [INPUT]: This repository checkout and optional flags (--target/--yes/--link-bin).
# [OUTPUT]: Installed swarm runtime under ~/.openclaw/swarm-core plus optional ~/.local/bin/swarm symlink.
# [POS]: Distribution installer for 30X Swarm private package.
# [PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$ROOT_DIR/swarm-core"
TARGET_DIR="$HOME/.openclaw/swarm-core"
ASSUME_YES=0
LINK_BIN=0

usage() {
  cat <<'USAGE'
Usage:
  ./install.sh [--target <path>] [--yes] [--link-bin]

Options:
  --target <path>  Install destination (default: ~/.openclaw/swarm-core)
  --yes            Skip confirmation prompt
  --link-bin       Create/update ~/.local/bin/swarm symlink
USAGE
}

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

if [[ ! -d "$SRC_DIR" ]]; then
  echo "ERROR: missing source dir: $SRC_DIR" >&2
  exit 1
fi

TARGET_DIR="$(eval echo "$TARGET_DIR")"
BACKUP_PATH="${TARGET_DIR}.bak.$(date +%Y%m%d%H%M%S)"

if [[ $ASSUME_YES -ne 1 ]]; then
  echo "Install swarm-core to: $TARGET_DIR"
  read -r -p "Continue? [y/N] " answer
  if [[ ! "$answer" =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
  fi
fi

mkdir -p "$(dirname "$TARGET_DIR")"
if [[ -e "$TARGET_DIR" ]]; then
  mv "$TARGET_DIR" "$BACKUP_PATH"
  echo "Backup created: $BACKUP_PATH"
fi

rsync -a --delete --exclude '__pycache__' "$SRC_DIR/" "$TARGET_DIR/"
chmod +x "$TARGET_DIR/swarm" "$TARGET_DIR/swarm_cli.py"
find "$TARGET_DIR/drivers" -type f -name '*.py' -exec chmod +x {} \;

if [[ $LINK_BIN -eq 1 ]]; then
  mkdir -p "$HOME/.local/bin"
  ln -sf "$TARGET_DIR/swarm" "$HOME/.local/bin/swarm"
  echo "Linked: $HOME/.local/bin/swarm -> $TARGET_DIR/swarm"
fi

cat <<DONE
Install complete.
- target: $TARGET_DIR
- command: $TARGET_DIR/swarm --help
DONE
