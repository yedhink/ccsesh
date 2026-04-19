# ccsesh shell integration for bash / zsh.
#
# Source this file from your shell profile so that after `ccsesh` resumes a
# session, the parent shell ends up in the session's project directory:
#
#   echo '. ~/.local/bin/../share/ccsesh/shell/ccsesh.bash' >> ~/.zshrc
#
# Or with the repo checkout directly:
#
#   echo '. /Users/you/dev/ccsesh/shell/ccsesh.bash' >> ~/.zshrc
#
# Pass --dont-cd to keep your current cwd unchanged after resume.

ccsesh() {
  # Non-interactive modes don't need the eval dance.
  local _arg
  for _arg in "$@"; do
    case "$_arg" in
      --list|--help|-h|--version|-v)
        command ccsesh "$@"
        return $?
        ;;
    esac
  done

  # Interactive: capture stdout (shell command to eval), let stderr pass
  # through so fzf errors / ctrl-o box / debug messages still show.
  local _cmd _rc
  _cmd="$(CCSESH_SHELL_MODE=1 command ccsesh "$@")"
  _rc=$?
  [ -n "$_cmd" ] && eval "$_cmd"
  return $_rc
}
