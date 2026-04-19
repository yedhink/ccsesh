# ccsesh

Fuzzy-search every Claude Code session on your machine and resume the one you pick.

![demo](docs/demo.gif)

## Why

`claude --resume` only lists sessions for the current directory. `ccsesh` reads the global session store at `~/.claude/projects/` and shows every session across every project, sorted by recency, with a preview pane and resume-on-Enter.

## Install

```bash
git clone https://github.com/yedhink/ccsesh.git
cd ccsesh
./install.sh
```

The installer symlinks `bin/ccsesh` into `~/.local/bin/` so `git pull` will keep you up to date. It will install `jq` and `fzf` via your package manager if they are missing.

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
- `Ctrl-O` — print `<sessionId><TAB><cwd>` and exit (for scripting).
- `Esc` — quit.

## Search syntax

The fzf query box supports two kinds of input combined freely: **filter tokens** and **free text**. Filters narrow the list; free text then fuzzy-matches the remainder.

**Filter tokens (GitHub-style):**

| Token | Effect |
|---|---|
| `repo:NAME`    | Keep only sessions whose project directory basename contains `NAME` (case-insensitive substring). |
| `since:7d`     | Keep only sessions newer than 7 days. Also accepts `Nh` (hours) and `Nm` (minutes). |

**Free-text matching (fzf native, case-insensitive):**

| Syntax | Meaning |
|---|---|
| `foo bar`      | Both terms must match (space = AND). |
| `'foo`         | Exact substring match for `foo`. |
| `^foo`         | `foo` must be at the start of the line. |
| `foo$`         | `foo` must be at the end. |
| `!foo`         | `foo` must NOT appear (negation). |

**Examples:**

```text
transcript                          # any session mentioning transcript
transcript repo:claude-skills       # narrow to that repo, then search
since:7d !bugwatch                  # recent sessions, excluding bugwatch
^2026-04-17 repo:neeto-products     # that day, in that repo
```

Free text matches against the visible display field, which includes the short summary plus the first ~500 chars of user-authored content from the session (dimmed in the list, fully visible in the preview pane).

## How it works

Claude Code writes one directory per project under `~/.claude/projects/<encoded-path>/`, with one `<session-id>.jsonl` per session. Those encoded path names are lossy (they replace `/` with `-`, which collides with hyphens in real directory names), so `ccsesh` ignores them and reads each session's `cwd` field directly out of the `.jsonl`. Summaries prefer `~/.claude/history.jsonl`'s `display` field (the exact text you typed), falling back to the first non-meta user message in the transcript. The store layout is reverse-engineered and may change; open an issue if something drifts.

## Uninstall

```bash
./uninstall.sh
```

`jq` and `fzf` are left installed.

## Contributing

PRs welcome. The tool is pure bash + `jq` + `fzf`, targets macOS and Linux, and stays compatible with stock macOS bash 3.2.

## License

MIT — see `LICENSE`.
