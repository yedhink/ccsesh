#!/usr/bin/env bash
set -u

SOURCE="${BASH_SOURCE[0]}"
CCSESH_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
BIN_SRC="$CCSESH_DIR/bin/ccsesh"
TARGET_DIR="$HOME/.local/bin"
TARGET="$TARGET_DIR/ccsesh"

detect_os() { case "$(uname -s)" in Darwin) echo darwin ;; Linux) echo linux ;; *) echo unsupported ;; esac; }

OS="$(detect_os)"
case "$OS" in
  darwin|linux) ;;
  *) echo "ccsesh: unsupported OS; macOS or Linux only" >&2; exit 1 ;;
esac

info() { printf '%s\n' "$1"; }
warn() { printf 'warning: %s\n' "$1" >&2; }

check_cmd() { command -v "$1" >/dev/null 2>&1; }

install_deps() {
  local missing=()
  check_cmd jq  || missing+=(jq)
  check_cmd fzf || missing+=(fzf)
  [ "${#missing[@]}" -eq 0 ] && return 0
  info "missing: ${missing[*]}"
  if [ "$OS" = darwin ]; then
    if check_cmd brew; then
      info "installing via brew..."
      brew install "${missing[@]}"
    else
      warn "brew not found. install manually: https://brew.sh then 'brew install ${missing[*]}'"
      return 1
    fi
  else
    if check_cmd apt-get; then sudo apt-get update && sudo apt-get install -y "${missing[@]}"
    elif check_cmd dnf; then sudo dnf install -y "${missing[@]}"
    elif check_cmd pacman; then sudo pacman -S --noconfirm "${missing[@]}"
    else
      warn "no supported package manager. install manually: ${missing[*]}"
      return 1
    fi
  fi
}

install_symlink() {
  mkdir -p "$TARGET_DIR"
  if [ -L "$TARGET" ]; then
    local current; current="$(readlink "$TARGET")"
    if [ "$current" = "$BIN_SRC" ]; then
      info "✓ symlink already points at $BIN_SRC"
      return 0
    fi
    info "existing symlink points at $current"
    printf 'replace it? [y/N] '
    read -r ans
    case "$ans" in y|Y|yes|YES) ln -sf "$BIN_SRC" "$TARGET"; info "✓ replaced" ;;
                  *) info "keeping existing symlink; aborting"; exit 1 ;;
    esac
  elif [ -e "$TARGET" ]; then
    warn "$TARGET exists as a regular file — refusing to overwrite. Remove it manually and re-run."
    exit 1
  else
    ln -s "$BIN_SRC" "$TARGET"
    info "✓ symlinked $TARGET -> $BIN_SRC"
  fi
}

path_advice() {
  case ":$PATH:" in *":$TARGET_DIR:"*) return 0 ;; esac
  local shell_name; shell_name="$(basename "${SHELL:-/bin/sh}")"
  info ""
  info "$TARGET_DIR is not on your PATH. Add this line to your shell config:"
  case "$shell_name" in
    fish) info "  fish_add_path $TARGET_DIR    # in ~/.config/fish/config.fish" ;;
    zsh)  info "  export PATH=\"$TARGET_DIR:\$PATH\"    # in ~/.zshrc" ;;
    bash)
      if [ "$OS" = darwin ]; then info "  export PATH=\"$TARGET_DIR:\$PATH\"    # in ~/.bash_profile"
      else                         info "  export PATH=\"$TARGET_DIR:\$PATH\"    # in ~/.bashrc"
      fi ;;
    *) info "  export PATH=\"$TARGET_DIR:\$PATH\"" ;;
  esac
}

shell_wrapper_advice() {
  local shell_name; shell_name="$(basename "${SHELL:-/bin/sh}")"
  info ""
  info "Optional: have your shell cd into the session's project dir AFTER"
  info "claude exits. Source the wrapper function from your shell config:"
  case "$shell_name" in
    fish) info "  source $CCSESH_DIR/shell/ccsesh.fish    # in ~/.config/fish/config.fish" ;;
    zsh)  info "  source $CCSESH_DIR/shell/ccsesh.bash    # in ~/.zshrc" ;;
    bash)
      if [ "$OS" = darwin ]; then info "  source $CCSESH_DIR/shell/ccsesh.bash    # in ~/.bash_profile"
      else                         info "  source $CCSESH_DIR/shell/ccsesh.bash    # in ~/.bashrc"
      fi ;;
    *) info "  source $CCSESH_DIR/shell/ccsesh.bash" ;;
  esac
  info "Without the wrapper, resume still works — it just doesn't leave your"
  info "shell in the project dir. Pass --dont-cd to suppress the cd even with"
  info "the wrapper in place."
}

main() {
  check_cmd claude || warn "claude not on PATH. ccsesh will install but resume won't work until you install Claude Code."
  install_deps || { warn "dependency install failed; aborting"; exit 1; }
  install_symlink
  path_advice
  shell_wrapper_advice
  info ""
  info "✓ installed — run 'ccsesh' to get started"
}

main "$@"
