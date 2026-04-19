# ccsesh

Fuzzy-search every Claude Code session on your machine and resume the one you pick.

![demo](docs/demo.gif)

## Why

You jump between projects all day. Claude Code keeps per-project session history, which is great — until you want to get back into a session. `claude --resume` only lists sessions for **the directory you're currently in**. So when you think "what was that debugging conversation last Wednesday?", you first have to remember which project it was in, `cd` there, run `--resume`, then squint at a blurry list of "first few words" to find it. If you guess the wrong project, you get nothing.

`ccsesh` cuts that out. One command, anywhere on your machine, and you see every Claude Code session you've ever had — sorted by recency, searchable by content, with a live preview of the conversation on the right. Narrow by project (`repo:foo`), by recency (`since:7d`), by the name you gave the session (`name:...`), or just type what you remember from the conversation. Hit Enter and you're back in the session, in the right directory, resumed.

## Install

```bash
git clone https://github.com/yedhink/ccsesh.git
cd ccsesh
./install.sh
```

The installer symlinks `bin/ccsesh` into `~/.local/bin/` so `git pull` will keep you up to date. It will install `jq` and `fzf` via your package manager if they are missing.

<details>
<summary><b>Prompt for an AI agent to install on your behalf</b></summary>

Paste the block below into your coding assistant (Claude Code, Cursor, Windsurf, Codex, Aider, etc.) and let it run the install end to end.

````text
Install ccsesh, a CLI that fuzzy-searches and resumes Claude Code sessions
across every project on this machine. Repo: https://github.com/yedhink/ccsesh

Context: Claude Code's built-in `claude --resume` only lists sessions for
the current directory. ccsesh reads the global session store at
~/.claude/projects/ and surfaces every session in one fzf picker.

Execute the steps below in order. Report progress as you go and surface any
errors verbatim — do not guess around them.

1. Pick an install location.
   Default to ~/dev/ccsesh. If ~/dev does not exist, prefer a sibling of
   whatever directory the user usually clones repos into. Ask the user only
   if neither is obvious.

2. Verify prerequisites.
   - `claude --version` must succeed. If it does not, tell the user ccsesh
     is useless without Claude Code and stop; do not attempt to install it.
   - Note whether `git`, `jq`, and `fzf` are on PATH. Do not install jq/fzf
     yourself — the installer handles those.

3. Clone the repo.
   - Run: `git clone https://github.com/yedhink/ccsesh.git <chosen-path>`
   - If the path already exists as a ccsesh checkout, `git -C <path> pull`
     instead. If it exists and is not a ccsesh checkout, stop and ask.

4. Run the installer.
   - `cd <chosen-path>`
   - `./install.sh`
   The installer will:
     * detect the OS (macOS/Linux — aborts on anything else)
     * install jq and fzf via brew / apt / dnf / pacman if missing
     * create a symlink ~/.local/bin/ccsesh -> <repo>/bin/ccsesh (idempotent;
       re-running is safe)
     * print a PATH-setup line for the user's detected shell if
       ~/.local/bin is not already on PATH
   Read and relay the installer's output to the user. If the installer
   exits non-zero, stop and surface the error — do not retry blindly.

5. Verify the install.
   - `which ccsesh` → should resolve to ~/.local/bin/ccsesh (or the path
     the installer reported). If it does not, the user likely needs to
     apply the PATH-setup line from step 4; point them at the exact line
     and the exact rc file to edit.
   - `ccsesh --version` → should print `ccsesh <semver>`.
   - `ccsesh --list | head -3` → should print up to 3 tab-separated rows.
     Zero rows is fine and means either no sessions exist yet or
     ~/.claude/projects/ is empty; note this rather than treat it as an
     error.

6. Report back. Include:
   - install location
   - output of `which ccsesh` and `ccsesh --version`
   - count of sessions ccsesh can see (`ccsesh --list | wc -l`)
   - any manual PATH step the user still needs to apply

Rules:
- Do NOT edit the user's shell rc file automatically. Print the exact line
  the installer suggested and tell the user which file to add it to.
- Do NOT use sudo. The installer deliberately runs unprivileged; if
  something appears to need root, stop and ask.
- Do NOT switch branches, pick a fork, or pin a tag. Use the default branch
  of yedhink/ccsesh.
- Do NOT proceed past a failing step. Surface the exact error and ask.

Troubleshooting cheatsheet:
- `command not found: brew` on macOS → direct the user to https://brew.sh
  and stop; the installer cannot complete without it.
- `permission denied` creating the symlink → ensure `~/.local/bin` exists
  and is user-writable; do not sudo.
- `ccsesh: missing jq` or `missing fzf` at runtime → re-run ./install.sh;
  the user may have declined the package install earlier.
- `No conversation found with session ID` after resume → ccsesh cds into
  the original project dir before running `claude --resume`; if that dir
  was deleted, ccsesh prints a clear error without launching claude.
````

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

The installer ships `~/.config/ccsesh/config.example.jsonc` with ready-made recipes for WezTerm, iTerm2, Ghostty 1.3+, tmux, and a delegate-to-script pattern. Copy any one block into `config.json` and strip the `// ` comments.

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
