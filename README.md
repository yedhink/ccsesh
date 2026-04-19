# ccsesh

Fuzzy-search every Claude Code session on your machine and resume the one you pick.

![demo](docs/demo.gif)

## Why

You jump between projects all day. Claude Code keeps per-project session history, which is great — until you want to get back into a session. `claude --resume` only lists sessions for **the directory you're currently in**. So when you think "what was that debugging conversation last Wednesday?", you first have to remember which project it was in, `cd` there, run `--resume`, then squint at a blurry list of "first few words" to find it. If you guess the wrong project, you get nothing.

`ccsesh` cuts that out. One command, anywhere on your machine, and you see every Claude Code session you've ever had — sorted by recency, searchable by content, with a live preview of the conversation on the right. Narrow by project (`repo:foo`), by recency (`since:7d`), by the name you gave the session (`name:...`), or just type what you remember from the conversation. Hit Enter and you're back in the session, in the right directory, resumed.

## Install

### Prompt for an AI agent to install on your behalf

The fastest path: paste the block below into your coding assistant (Claude Code, Cursor, Windsurf, Codex, Aider, etc.) and let it handle everything — clone, dependencies, PATH setup, and an optional interactive step where it configures the Enter action for your terminal (new WezTerm / Ghostty tab, new tmux window, your own script, or leave as the default).

<details>
<summary><b>Show the prompt</b></summary>

````text
Install ccsesh, a CLI that fuzzy-searches and resumes Claude Code sessions
across every project on this machine. Repo: https://github.com/yedhink/ccsesh

Context: Claude Code's built-in `claude --resume` only lists sessions for
the current directory. ccsesh reads the global session store at
~/.claude/projects/ and surfaces every session in one fzf picker.

Execute the steps below in order. Surface errors verbatim. Steps 1 and 6
ASK the user questions — you MUST ask them and wait, do not pick on
their behalf.

1. Ask the user where to clone the ccsesh repo.
   This location is PERSISTENT — future `git pull` runs there to fetch
   updates, and the installer creates a symlink
   ~/.local/bin/ccsesh -> <clone-path>/bin/ccsesh that points into it.
   Ask this question verbatim and WAIT for the user's answer:

   > "Where should I clone the ccsesh repo?
   >   (a) Home directory: ~/ccsesh
   >   (b) /tmp/ccsesh  (throwaway — /tmp is typically wiped on reboot,
   >       so pick this only if you're just trying ccsesh out; future
   >       `git pull` updates will break after the tmp directory is
   >       cleared)
   >   (c) Somewhere else (tell me the path)"

   Do NOT guess a location like ~/dev/ccsesh without asking. If the user
   picks (c), confirm the expanded path back to them before cloning.

2. Verify prerequisites.
   - `claude --version` must succeed. If it does not, ccsesh is useless
     without Claude Code — stop; do not try to install it.
   - Note whether `git`, `jq`, and `fzf` are on PATH. Do not install
     jq/fzf yourself; the installer handles those.

3. Clone the repo.
   - `git clone git@github.com:yedhink/ccsesh.git <chosen-path>`
     (the repo is private, so SSH-over-port-22 is the only working clone
     URL; HTTPS cloning will prompt for credentials and fail under an
     AI agent's non-interactive shell)
   - If the path already exists as a ccsesh checkout, run
     `git -C <chosen-path> pull` instead. If it exists and is NOT a
     ccsesh checkout, stop and ask.

4. Run the installer.
   - `cd <chosen-path> && ./install.sh`
   The installer:
     * detects OS (macOS/Linux — aborts on anything else)
     * installs jq and fzf via brew / apt / dnf / pacman if missing
     * symlinks ~/.local/bin/ccsesh -> <repo>/bin/ccsesh (idempotent)
     * copies <repo>/config.example.jsonc to ~/.config/ccsesh/
     * prints PATH advice for the detected shell if ~/.local/bin is
       not already on PATH
   Relay installer output. If it exits non-zero, stop — don't retry blindly.

5. Verify the basic install.
   - `which ccsesh` resolves to ~/.local/bin/ccsesh (or wherever the
     installer reported). If not, apply the PATH-setup line from step 4
     and tell the user which rc file to add it to.
   - `ccsesh --version` prints `ccsesh <semver>`.
   - `ccsesh --list | head -3` prints up to 3 TSV rows. Zero rows is fine
     and just means the user has no Claude sessions yet (or
     ~/.claude/projects/ is empty). Note it, don't treat it as an error.

6. Ask the user about the Enter action.
   By default, pressing Enter on a session replaces the current shell
   with `claude --resume <sid>` — so ccsesh exits when you hit Enter.
   Many users prefer opening the resume in a new tab/window so ccsesh
   stays up for the next pick. Ask the user this question verbatim and
   WAIT for their answer:

   > "Pressing Enter on a session — what should happen?
   >   (a) Replace my current shell with claude --resume (the default)
   >   (b) Open the session in a new tab of my current terminal
   >   (c) Open the session in a new tmux window (only if you use tmux)
   >   (d) Run a custom command I'll describe
   >   (e) I'll configure it later myself"

   If the user chose (a) or (e): skip to step 8. No config needed.

7. Configure the chosen Enter action.

   For (b) "new tab in current terminal":
     Detect which terminal the user is running right now:
       - $WEZTERM_PANE is set           → WezTerm
       - $TERM_PROGRAM == "ghostty"     → Ghostty (needs 1.3+)
       - $TERM_PROGRAM == "iTerm.app"   → iTerm2
       - otherwise                      → ask the user which terminal
     Copy the matching helper from the repo:
       cp <repo>/examples/wezterm-new-tab ~/.local/bin/
       # or ghostty-new-tab, or iterm2-new-tab
       chmod +x ~/.local/bin/<helper>
     For terminals without a ready-made helper: point the user at the
     inline recipe in ~/.config/ccsesh/config.example.jsonc and warn
     them about the PATH-strip gotcha (tell them to resolve `claude`
     to an absolute path if the inline form fails).

   For (c) "new tmux window": no helper script needed; use the inline
   recipe below.

   For (d) "custom command": ask the user for the script path OR the
   exact shell command. Explain the contract: the script receives sid
   as $1 and cwd as $2; or the command may use {sid} / {cwd} as
   placeholders (both auto shell-escaped by ccsesh).

   Then write ~/.config/ccsesh/config.json with exactly ONE of the
   following (pick the one matching the user's choice):

     # (b) WezTerm
     { "enter": { "command": "~/.local/bin/wezterm-new-tab {sid} {cwd}" } }

     # (b) Ghostty
     { "enter": { "command": "~/.local/bin/ghostty-new-tab {sid} {cwd}" } }

     # (b) iTerm2
     { "enter": { "command": "~/.local/bin/iterm2-new-tab {sid} {cwd}" } }

     # (c) tmux
     { "enter": { "command": "tmux new-window -c {cwd} -- claude --resume {sid}" } }

     # (d) user's script
     { "enter": { "command": "<user-path-or-command> {sid} {cwd}" } }

   Use mkdir -p first:
     mkdir -p ~/.config/ccsesh
     cat > ~/.config/ccsesh/config.json <<'JSON'
     <the chosen block on one line>
     JSON

   Verify the expansion looks right. No env var setup is required —
   ccsesh reads ~/.config/ccsesh/config.json by default:
     bash -c 'source <repo>/lib/util.sh
              source <repo>/lib/ui.sh
              _ccsesh_ui_enter_expand "test-sid" "/tmp"'
   This should print the command that ccsesh will exec on Enter.

   Do NOT tell the user to add any ccsesh env var to their shell rc
   files. There isn't one. The config file at the path above is all
   ccsesh needs.

8. Report back. Include:
   - install location
   - `which ccsesh` and `ccsesh --version` output
   - number of sessions ccsesh can see (`ccsesh --list | wc -l`)
   - any PATH step the user still needs to apply manually
   - which Enter-action recipe (if any) was configured

Rules:
- Do NOT edit the user's shell rc file automatically. Print the line and
  tell the user which file to add it to.
- Do NOT use sudo. The installer avoids it by design.
- Do NOT switch branches, pick a fork, or pin a tag. Use the default
  branch of yedhink/ccsesh.
- Do NOT skip step 1's or step 6's question. Both require the user's
  answer; do not pick on their behalf or assume a default location.
- Do NOT proceed past a failing step. Surface the error and ask.

Troubleshooting cheatsheet:
- `command not found: brew` on macOS → direct the user to https://brew.sh
  and stop; the installer can't complete without it.
- `permission denied` creating the symlink → ensure ~/.local/bin is
  user-writable; do not sudo.
- `ccsesh: missing jq` / `missing fzf` at runtime → re-run ./install.sh;
  the user may have declined the package install earlier.
- `No conversation found with session ID` after resume → ccsesh cd's
  into the original project dir; if that dir was deleted, ccsesh prints
  a clear error without launching claude.
- `bash: line 0: exec: claude: not found` when using a custom tab-opener
  → the terminal is exec'ing the command via a PATH-stripped login
  shell. The ready-made helpers in <repo>/examples/ already resolve
  `claude`'s absolute path to sidestep this; custom scripts need to do
  the same.
````

</details>

<details>
<summary><b>Prefer to install manually?</b></summary>

```bash
git clone git@github.com:yedhink/ccsesh.git
cd ccsesh
./install.sh
```

The installer symlinks `bin/ccsesh` into `~/.local/bin/` so `git pull` keeps you up to date, installs `jq` and `fzf` via your package manager if missing, and copies `~/.config/ccsesh/config.example.jsonc` with annotated recipes for the Enter action.

To configure a custom Enter action after install:
1. Pick a recipe from `~/.config/ccsesh/config.example.jsonc` (WezTerm, Ghostty, iTerm2, tmux, or your own script).
2. Most terminal "new tab" recipes need a helper script — copy the matching one from the repo's [`examples/`](./examples) directory into `~/.local/bin/` and `chmod +x`.
3. Create `~/.config/ccsesh/config.json` with the block from the chosen recipe (strip the `// ` comments).

See the [Custom Enter action](#custom-enter-action) section below for details on placeholders and stay-in-picker behavior.

</details>

## Usage

```bash
ccsesh                               # interactive picker (default)
ccsesh --list                        # print all sessions as TSV
ccsesh --project ~/dev/some-repo     # restrict to one project's cwd
ccsesh --since 7d                    # only sessions newer than 7 days
ccsesh --help
ccsesh --version
```

Keybindings inside the picker:
- `Enter` — `cd` into the session's original project dir and run `claude --resume <id>`.
- `Ctrl-O` — print a labeled summary of the selected session and exit. The box
  auto-sizes to its content; the `Name:` row is omitted when the session has
  no custom title.
  ```
  ╭─ Session ──────────────────────────────────────────────────────────────────╮
  │  Session ID:  <sessionId>                                                  │
  │  Repo:        <repo-name>                                                  │
  │  Name:        <custom-title>                                               │
  │  Path:        <cwd>                                                        │
  │                                                                            │
  │  Resume (cwd-scoped):                                                      │
  │    cd -- <cwd> && claude --resume <sessionId>                              │
  ╰────────────────────────────────────────────────────────────────────────────╯
  ```
  Colors drop when stdout is not a TTY (safe for piping into other scripts).
- `Esc` — quit.

The preview pane on the right shows a labeled header block (`Name`, `ID`, `Repo`, `Path`, `Last`, and a 2-sentence "Session started with:" snippet) followed by the conversation body. User messages appear with a plain `> ` prefix; Claude's replies are prefixed with a cyan `⏺ ` and the whole reply is tinted cyan, so you can scan who said what at a glance. When your query matches something, the body scrolls to the first matching user line and highlights matches — only on user lines, mirroring the filter scope.

### Custom Enter action

By default, Enter runs `cd <cwd> && claude --resume <sid>` in the current tab. If you'd rather open a new tab, split a tmux window, or delegate to your own script, drop a file at `~/.config/ccsesh/config.json` with an `enter.command` template:

```json
{ "enter": { "command": "wezterm cli spawn --cwd {cwd} -- claude --resume {sid}" } }
```

Placeholders `{sid}` and `{cwd}` are substituted into the command, both shell-escaped — do not wrap them in quotes yourself. The config file is strict JSON (no comments, no trailing commas).

**Stay-in-picker behavior.** When a custom `enter.command` is configured, Enter fires the action and **leaves you in the picker** so you can line up more sessions (e.g. open three Ghostty tabs in a row). Press `Esc` to quit ccsesh. Without a custom command, Enter keeps its classic behavior: replace the terminal with `claude --resume` and exit.

The installer ships `~/.config/ccsesh/config.example.jsonc` with ready-made recipes for WezTerm, iTerm2, Ghostty 1.3+, tmux, and a delegate-to-script pattern. Copy any one block into `config.json` and strip the `// ` comments.

For recipes that need a helper script (e.g. Ghostty, which execs through a stripped-down login shell where `claude` may not be on `PATH`), see the [`examples/`](./examples) directory — each helper takes `{sid}` and `{cwd}` as positional args and can be dropped into `~/.local/bin/` directly.

## Search syntax

The fzf query box supports two kinds of input combined freely: **filter tokens** and **free text**. Filters narrow the list; free-text terms then substring-match (case-insensitive) against the visible field of whatever survived the filters.

**Filter tokens (GitHub-style):**

| Token | Effect |
|---|---|
| `repo:NAME`    | Keep only sessions whose project directory basename contains `NAME` (case-insensitive substring). |
| `since:7d`     | Keep only sessions newer than 7 days. Also accepts `Nh` (hours) and `Nm` (minutes). |
| `name:NAME`    | Keep only sessions whose custom title contains `NAME` (case-insensitive substring). Sessions without a custom title are excluded. |

**Free-text matching (fzf, always case-insensitive, exact/substring by default):**

| Syntax | Meaning |
|---|---|
| `foo bar`      | Both terms must match (space = AND). Each term is exact substring. |
| `^foo`         | `foo` must be at the start of the line. |
| `foo$`         | `foo` must be at the end. |
| `!foo`         | `foo` must NOT appear (negation). |
| `'foo`         | Fuzzy match for `foo` (letters can appear scattered in order). Opt-in override of the default substring behavior. |

**Examples:**

```text
transcript                          # any session mentioning transcript
transcript repo:claude-skills       # narrow to that repo, then search
since:7d !bugwatch                  # recent sessions, excluding bugwatch
name:bugwatch                       # only sessions you renamed with "bugwatch" in the title
^2026-04-17 repo:neeto-products     # that day, in that repo
```

Free text matches against the visible display field, which includes the custom title (if any), the short summary, and the first ~500 chars of **user-authored** content from the session (dimmed in the list). Assistant replies show up in the preview pane for context, but the filter deliberately ignores them — searching for a phrase Claude said won't surface the session. Sessions you have renamed in Claude Code show a green `[title]` badge at the start of the row.

**Editing the query (fzf readline bindings):**

| Key | Action |
|---|---|
| `Ctrl-U`        | clear the whole query |
| `Ctrl-W`        | delete word before cursor |
| `Alt-Backspace` | delete word before cursor |
| `Ctrl-K`        | delete from cursor to end of line |
| `Ctrl-A` / `Ctrl-E` | jump to start / end of line |
| `Backspace`     | delete single char |

See the [fzf man page](https://github.com/junegunn/fzf/blob/master/man/man1/fzf.1) for the full list of key bindings and search-mode options.

## How it works

Claude Code writes one directory per project under `~/.claude/projects/<encoded-path>/`, with one `<session-id>.jsonl` per session. Those encoded path names are lossy (they replace `/` with `-`, which collides with hyphens in real directory names), so `ccsesh` ignores them and reads each session's `cwd` field directly out of the `.jsonl`. Summaries prefer `~/.claude/history.jsonl`'s `display` field (the exact text you typed), falling back to the first non-meta user message in the transcript. Custom titles set via Claude Code's rename feature are picked up from the `custom-title` record in the transcript and shown as the green `[title]` badge in the list (and `Name:` in the preview header). The store layout is reverse-engineered and may change; open an issue if something drifts.

## Uninstall

```bash
./uninstall.sh
```

`jq` and `fzf` are left installed.

## Contributing

PRs welcome. The tool is pure bash + `jq` + `fzf`, targets macOS and Linux, and stays compatible with stock macOS bash 3.2.

## License

MIT — see `LICENSE`.
