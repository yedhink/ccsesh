# ccsesh shell integration for fish.
#
# Source this file from your fish config so that after `ccsesh` resumes a
# session, the parent shell ends up in the session's project directory:
#
#   echo 'source /Users/you/dev/ccsesh/shell/ccsesh.fish' >> ~/.config/fish/config.fish
#
# Pass --dont-cd to keep your current cwd unchanged after resume.

function ccsesh
    # Non-interactive modes don't need the eval dance.
    for arg in $argv
        switch $arg
            case --list --help -h --version -v
                command ccsesh $argv
                return $status
        end
    end

    # Interactive: capture stdout (shell command to eval), let stderr pass
    # through so fzf errors / ctrl-o box / debug messages still show.
    set -l _cmd (CCSESH_SHELL_MODE=1 command ccsesh $argv)
    set -l _rc $status
    if test -n "$_cmd"
        # fish's eval works on one command at a time. Our output is always a
        # single statement (`cd -- /path && claude --resume sid` or the
        # subshell form), so eval it as a single string.
        eval $_cmd
    end
    return $_rc
end
