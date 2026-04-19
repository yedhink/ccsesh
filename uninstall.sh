#!/usr/bin/env bash
set -u

TARGET="$HOME/.local/bin/ccsesh"
SOURCE="${BASH_SOURCE[0]}"
CCSESH_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
BIN_SRC="$CCSESH_DIR/bin/ccsesh"

if [ -L "$TARGET" ]; then
  current="$(readlink "$TARGET")"
  if [ "$current" = "$BIN_SRC" ]; then
    rm -- "$TARGET"
    echo "✓ removed $TARGET"
  else
    echo "refusing to remove $TARGET: points at $current (not this repo)" >&2
    exit 1
  fi
elif [ -e "$TARGET" ]; then
  echo "$TARGET exists but is not a symlink; refusing to touch it" >&2
  exit 1
else
  echo "nothing to uninstall; $TARGET does not exist"
fi

echo "note: jq and fzf are left installed."
