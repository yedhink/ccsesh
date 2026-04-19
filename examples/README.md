# examples

Reference scripts for the **Custom Enter action** hook described in the [main README](../README.md#custom-enter-action).

Each script here is designed to be invoked from `~/.config/ccsesh/config.json` with `{sid}` and `{cwd}` as positional args. `ccsesh` shell-escapes both values before substitution, so the script receives them intact as `$1` and `$2`.

## How to use

1. Copy the script you want into a directory on your `PATH`:

   ```bash
   cp examples/ghostty-new-tab ~/.local/bin/
   chmod +x ~/.local/bin/ghostty-new-tab
   ```

2. Point `~/.config/ccsesh/config.json` at it:

   ```json
   { "enter": { "command": "~/.local/bin/ghostty-new-tab {sid} {cwd}" } }
   ```

3. Run `ccsesh`, pick a session, press `Enter`.

## What's here

### `ghostty-new-tab`

Opens the resumed session in a new [Ghostty](https://ghostty.org) tab at the session's original `cwd`. Requires Ghostty 1.3+ for the native AppleScript API.

Handles one non-obvious gotcha: Ghostty runs the configured `command` via `/bin/bash --noprofile --norc`, which strips PATH of anything added by your shell rc files (Homebrew, nvm, asdf, etc.). The script resolves `claude` to an absolute path in its own shell (where PATH is intact) before handing it to AppleScript, so Homebrew installs of claude work fine.

First invocation will trigger a macOS Automation permission prompt for Ghostty — approve once, subsequent runs are silent.

### `wezterm-new-tab`

Opens the resumed session in a new [WezTerm](https://wezfurlong.org/wezterm) tab at the session's original `cwd`. Uses `wezterm cli spawn` (no AppleScript needed) — the spawned tab lands in the window hosting the ccsesh pane, detected automatically via `$WEZTERM_PANE`.

Same PATH gotcha as `ghostty-new-tab`: `wezterm cli spawn` execs the command directly with WezTerm's GUI-process PATH, which typically lacks Homebrew when WezTerm was launched from Finder. The wrapper resolves `claude`'s absolute path first, sidestepping the issue.

`wezterm cli spawn` normally prints the new pane id to stdout; the wrapper suppresses that so fzf doesn't flash it between picks.

### `iterm2-new-tab`

Opens the resumed session in a new [iTerm2](https://iterm2.com) tab at the session's original `cwd`. Uses AppleScript's two-step form — create a blank tab with the default profile, then `write text` to type `cd … && claude --resume …` into the shell that iTerm2 just started.

Because the command is typed into the new tab's *shell* (not handed to iTerm2's `command` field that replaces the shell), the shell's rc files load normally — `claude` ends up on PATH the usual way. As a side effect, the command is visible in the tab's scrollback. If you'd rather have the command run silently, switch to the `create tab with default profile command "…"` form and resolve `claude`'s absolute path up front like `ghostty-new-tab` does.

First invocation triggers a macOS Automation permission prompt for iTerm — approve once, subsequent runs are silent.

## Contributing a new example

PRs welcome. Guidelines:

- The script must accept `sid` as `$1` and `cwd` as `$2` — this is the ccsesh contract.
- Keep it POSIX-ish or explicit-bash. Target macOS bash 3.2 for broad compatibility.
- Put the PATH/env gotcha (if any) in a leading comment — the next reader should understand *why* the script looks the way it does.
- Update this README with a short entry describing what the script does and which terminal / multiplexer it targets.
