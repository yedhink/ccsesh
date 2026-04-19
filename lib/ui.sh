#!/usr/bin/env bash
set -u

_UI_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$_UI_DIR/util.sh"

# Build a case-insensitive grep regex from an fzf-style query. Steps:
#   - drop filter tokens (repo:, since:, name:)
#   - drop negation tokens (!foo) — they exclude, we don't highlight exclusions
#   - strip leading '  (exact), leading ^ (prefix), trailing $ (suffix)
#   - regex-escape remaining positive terms and join with |
# Prints the alternation regex. Empty stdout means "no highlight applicable".
_ccsesh_ui_query_to_regex() {
  local q="$1"
  local tok parts="" esc
  for tok in $q; do
    case "$tok" in
      repo:*|since:*|name:*) continue ;;
      '!'*) continue ;;
    esac
    tok="${tok#\'}"
    tok="${tok#^}"
    tok="${tok%\$}"
    [ -n "$tok" ] || continue
    esc="$(printf '%s' "$tok" | sed -E 's/[][(){}.+*?^$|\\\/]/\\&/g')"
    parts="${parts:+$parts|}$esc"
  done
  printf '%s' "$parts"
}

# Internal: emit ALL user + assistant preview lines (no head cap). Used by
# ccsesh_ui_preview which slices the output based on whether a query is
# present.
#   - User lines get a "> " prefix (default color).
#   - Assistant lines get a "⏺ " prefix, colored cyan for visual distinction.
# tool_use / tool_result / thinking blocks are dropped — only human-readable
# text content is shown.
#
# Coloring happens AFTER ccsesh_strip_controls (which strips \x1b / ESC). We
# mark assistant lines with a plain "⏺ " prefix in jq, then awk adds ANSI.
_ccsesh_ui_preview_render_raw() {
  local f="$1"
  jq -Rr '
    fromjson?
    | select((.type == "user" or .type == "assistant") and ((.isMeta // false) | not))
    | (if .type == "user" then "> " else "⏺ " end) as $prefix
    | .message.content as $c
    | if ($c | type) == "string" then
        if ($c | test("^<(command-|local-command-|system-reminder)")) then empty else ($prefix + $c) end
      elif ($c | type) == "array" then
        ( [ $c[]
            | select(.type == "text" and (.text // "") != "")
            | select(.text | test("^<(command-|local-command-|system-reminder)") | not)
            | .text ]
          | .[]
          | ($prefix + .)
        )
      else empty end
  ' < "$f" 2>/dev/null \
    | ccsesh_strip_controls \
    | awk '
      # Track the current role so continuation lines of a multi-line
      # assistant message stay cyan. A "> " prefix flips us back to user;
      # a "⏺ " prefix flips to assistant.
      BEGIN { role = "U" }
      /^⏺ / { role = "A"; printf "\033[36m%s\033[0m\n", $0; next }
      /^> / { role = "U"; print; next }
      {
        if (role == "A") printf "\033[36m%s\033[0m\n", $0
        else print
      }
    '
}

# Internal: first 30 preview lines (used when no query is active).
_ccsesh_ui_preview_render() {
  _ccsesh_ui_preview_render_raw "$1" | head -n 30
}

# Extract header metadata for the preview pane in one jq pass. Emits 6 fields
# newline-separated (one per line) to dodge bash's habit of collapsing
# consecutive tabs when IFS=tab. Each field has its own tabs/newlines
# stripped by gsub so the line-based parser can't be confused.
# Order: sid, cwd, custom_title, iso_ts, count, first_snippet.
_ccsesh_ui_preview_header_extract() {
  local f="$1"
  jq -Rsr '
    def user_text:
      . as $c
      | if ($c | type) == "string" then
          (if ($c | test("^<(command-|local-command-|system-reminder)")) then "" else $c end)
        elif ($c | type) == "array" then
          ([ $c[]
            | select(.type == "text" and (.text // "") != "")
            | select(.text | test("^<(command-|local-command-|system-reminder)") | not)
            | .text
          ][0] // "")
        else "" end;
    def one_line: gsub("[\t\n\r]"; " ") | gsub("  +"; " ");

    (split("\n") | map(fromjson?) | map(select(. != null))) as $R
    | ([$R[] | select(.sessionId != null) | .sessionId] | first // "") as $sid
    | ([$R[] | select(.cwd != null) | .cwd] | first // "") as $cwd
    | ([$R[] | select(.type == "custom-title") | .customTitle // empty] | first // "") as $title
    | ([$R[] | .timestamp // empty] | max // "") as $raw_ts
    | (if $raw_ts != "" then ($raw_ts | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601 | strflocaltime("%Y-%m-%d %H:%M %z")) else "" end) as $ts
    | ([$R[] | select((.type == "user" or .type == "assistant") and ((.isMeta // false) | not))] | length) as $count
    | ([$R[] | select(.type == "user" and ((.isMeta // false) | not)) | (.message.content | user_text) | select(. != "")][0] // "") as $raw_snippet
    | ($raw_snippet | one_line) as $flat
    | ($flat
       | . as $s
       | [match("[.!?](\\s|$)"; "g")] as $ms
       | (if ($ms | length) >= 2 then $s[0:($ms[1].offset + 1)] else $s end)
       | .[0:240]
      ) as $trimmed
    | (if ($trimmed | length) < ($flat | length) then (($trimmed | sub("\\s+$"; "")) + " …") else $trimmed end) as $snippet
    | [
        ($sid | one_line),
        ($cwd | one_line),
        ($title | one_line),
        ($ts | one_line),
        ($count | tostring),
        $snippet
      ]
    | .[]
  ' < "$f" 2>/dev/null
}

# Print a styled, annotated header block for the preview. Each row starts
# with a right-aligned 4-char label (dim), then the value in a color that
# matches its role:
#   Name  — custom title (green, only when set)
#    ID   — session id (dim, or bold-cyan if no Name is shown)
#   Repo  — project basename (cyan)
#   Path  — full cwd (dim)
#   Last  — max event timestamp + message count (dim)
#
# Below the labeled rows, a "Session started with:" heading is printed
# followed by the first ~2 sentences of the session's opening user message
# on an indented line (capped at 240 chars for runaway single sentences).
_ccsesh_ui_preview_header_print() {
  local f="$1"
  local sid cwd title ts count snippet proj_base
  {
    IFS= read -r sid || sid=""
    IFS= read -r cwd || cwd=""
    IFS= read -r title || title=""
    IFS= read -r ts || ts=""
    IFS= read -r count || count=""
    IFS= read -r snippet || snippet=""
  } < <(_ccsesh_ui_preview_header_extract "$f")
  [ -n "$sid" ] || return 0
  proj_base="$(basename "$cwd" 2>/dev/null)"
  [ -n "$proj_base" ] || proj_base="(unknown)"

  local lbl rs nm id_c repo dim light
  lbl=$'\033[2;37m'   # dim gray for labels
  rs=$'\033[0m'
  nm=$'\033[1;32m'    # bold green — matches the list's [title] badge
  id_c=$'\033[1;36m'  # bold cyan — used when the session has no title
  repo=$'\033[36m'    # cyan for the project basename
  dim=$'\033[2m'
  light=$'\033[0;37m' # light gray for the opening-snippet excerpt

  # Render one labeled row. $1 = label (will be right-aligned to 5 chars
  # including the trailing colon), $2 = pre-colored value.
  _hdr_row() {
    printf '%s%5s%s  %s\n' "$lbl" "$1" "$rs" "$2"
  }

  if [ -n "$title" ]; then
    _hdr_row 'Name:' "${nm}${title}${rs}"
    _hdr_row 'ID:'   "${dim}${sid}${rs}"
  else
    _hdr_row 'ID:'   "${id_c}${sid}${rs}"
  fi
  _hdr_row 'Repo:' "${repo}${proj_base}${rs}"
  _hdr_row 'Path:' "${dim}${cwd}${rs}"
  _hdr_row 'Last:' "${dim}${ts}  ·  ${count} messages${rs}"
  if [ -n "$snippet" ]; then
    printf '%sSession started with:%s\n' "$lbl" "$rs"
    printf '  %s%s%s\n' "$light" "$snippet" "$rs"
  fi
  printf '%s────────────────────────────────────────%s\n' "$dim" "$rs"
  unset -f _hdr_row
}

# Print a styled preview: colored header block followed by 30 user-authored
# text snippets. When $2 (query) is non-empty, the body is scrolled so the
# first matching line is at the top instead of the start of the transcript
# (the header already carries the truncated-start snippet). If no match is
# found, falls back to the first 30 lines. Matches are highlighted via grep
# --color using the "|$" trick so every line passes but only matches color.
ccsesh_ui_preview() {
  local f="$1"
  local q="${2:-}"
  [ -r "$f" ] || { printf '(session file not readable)\n'; return 0; }

  _ccsesh_ui_preview_header_print "$f"

  # Reduce the query to an alternation regex of positive terms, dropping
  # filter tokens, negation tokens, and fzf operators.
  local q_regex=""
  [ -n "$q" ] && q_regex="$(_ccsesh_ui_query_to_regex "$q")"

  if [ -z "$q_regex" ]; then
    # Nothing to scroll to, nothing to highlight.
    _ccsesh_ui_preview_render "$f"
    return 0
  fi

  local body
  body="$(_ccsesh_ui_preview_render_raw "$f")"
  [ -n "$body" ] || return 0

  # Find line number of first match. If none, anchor at line 1 (top).
  local first_line
  first_line="$(printf '%s\n' "$body" | grep -n -i -m 1 -E -- "$q_regex" 2>/dev/null \
                | head -n 1 | cut -d: -f1)"
  [ -n "$first_line" ] || first_line=1

  printf '%s\n' "$body" \
    | tail -n "+$first_line" \
    | head -n 30 \
    | grep --color=always -iE -- "${q_regex}|$" 2>/dev/null \
    || printf '%s\n' "$body" | tail -n "+$first_line" | head -n 30
}

# Build the fzf input. Consumes the raw 9-field stream from
# _ccsesh_sessions_list_raw (epoch, sid, cwd, ts_iso, count, ver, summary,
# extended, custom_title) and emits 6 tab-delimited fzf fields:
#   1 = sid         (hidden)
#   2 = cwd         (hidden)
#   3 = ts_iso      (hidden)
#   4 = colored display + dimmed extended text (visible via --with-nth=4)
#   5 = epoch       (hidden, carried for since: filtering in __fzf_feed)
#   6 = custom_title (hidden, carried for name: filtering in __fzf_feed)
#
# If the session has a custom title, it is rendered as a bold-green `[title]`
# badge prefixed onto the display field. It stays searchable via free-text
# queries AND can be filtered exactly via `name:X`.
_ccsesh_ui_build_lines() {
  local epoch sid cwd ts_iso count ver summary extended title date_short proj_base badge
  while IFS=$'\t' read -r epoch sid cwd ts_iso count ver summary extended title; do
    date_short="${ts_iso%%T*}"
    proj_base="$(basename "$cwd" 2>/dev/null)"
    [ -n "$proj_base" ] || proj_base="(unknown)"
    if [ -n "$title" ]; then
      badge="$(printf '\033[1;32m[%s]\033[0m  ' "$title")"
    else
      badge=""
    fi
    printf '%s\t%s\t%s\t%b\033[2m%s\033[0m  \033[36m%s\033[0m  %s  \033[2;90m%s\033[0m\t%s\t%s\n' \
      "$sid" "$cwd" "$ts_iso" "$badge" "$date_short" "$proj_base" "$summary" "$extended" "$epoch" "$title"
  done
}

# Launch fzf. Expects filter args same as sessions_list. Builds a cache file
# once at startup; the fzf --bind change:reload pipeline then re-filters the
# cache in place (no jq rebuild per keystroke) using __fzf_feed.
ccsesh_ui_run() {
  local cache
  cache="$(mktemp -t ccsesh.cache.XXXXXX)"
  # shellcheck disable=SC2064
  trap "rm -f '$cache'" EXIT INT TERM

  _ccsesh_debug "ui: building cache at $cache"
  _ccsesh_sessions_list_raw "$@" | _ccsesh_ui_build_lines > "$cache"

  if [ ! -s "$cache" ]; then
    printf 'ccsesh: no sessions found under %s\n' "$(ccsesh_home)" >&2
    return 0
  fi

  export CCSESH_UI_CACHE="$cache"

  # fzf fields: 1=sid, 2=cwd, 3=ts_iso (hidden), 4=colored display + dimmed
  # extended text (visible + searchable), 5=epoch (hidden, used by __fzf_feed).
  #
  # --disabled turns off fzf's internal matcher so the external __fzf_feed
  # subcommand handles ALL filtering (repo:, since:, and text terms). Trade-off:
  # match spans in the list are not highlighted, but the preview pane already
  # highlights query matches in session content.
  # -i is kept for clarity even though --disabled makes fzf ignore it.
  local selection rc
  selection="$(
    fzf \
      --disabled \
      --ansi \
      --no-hscroll \
      --delimiter=$'\t' \
      --with-nth=4 \
      --prompt='ccsesh> ' \
      --header='enter=resume  ctrl-o=print  esc=quit
filters: repo:X  since:Nd|Nh|Nm  name:X
operators: foo bar (AND)  ^foo (prefix)  foo$ (suffix)  !foo (negate)  '\''foo (fuzzy)' \
      --bind "start:reload($CCSESH_DIR/bin/ccsesh __fzf_feed {q})" \
      --bind "change:reload($CCSESH_DIR/bin/ccsesh __fzf_feed {q})" \
      --expect=ctrl-o \
      --preview-window='right,50%,wrap' \
      --preview "$CCSESH_DIR/bin/ccsesh __preview {2} {1} {q} 2>/dev/null" \
      < /dev/null
  )"
  rc=$?
  # rc=130 -> Esc/no selection
  [ "$rc" -eq 130 ] && return 0
  [ "$rc" -ne 0 ] && return "$rc"

  local key line sid cwd title proj_base
  key="$(printf '%s\n' "$selection" | head -n 1)"
  line="$(printf '%s\n' "$selection" | sed -n '2p')"
  [ -n "$line" ] || return 0
  sid="$(printf '%s' "$line" | cut -f1)"
  cwd="$(printf '%s' "$line" | cut -f2)"
  # Field 6 in our fzf input is the raw custom_title (see _ccsesh_ui_build_lines).
  title="$(printf '%s' "$line" | cut -f6)"

  case "$key" in
    ctrl-o)
      proj_base="$(basename "$cwd" 2>/dev/null)"
      [ -n "$proj_base" ] || proj_base="(unknown)"
      local cwd_q
      cwd_q="$(printf '%q' "$cwd")"

      # Build plain content lines (no ANSI) so width math is honest.
      # Two-column fields get a fixed 12-char label column for alignment.
      local -a _lines
      _lines=(
        "  Session ID:  $sid"
        "  Repo:        $proj_base"
      )
      if [ -n "$title" ]; then
        _lines+=("  Name:        $title")
      fi
      _lines+=("  Path:        $cwd")
      _lines+=("")
      _lines+=("  Resume (cwd-scoped):")
      _lines+=("    cd -- $cwd_q && claude --resume $sid")

      # Measure widest line.
      local _max=0 _n _l
      for _l in "${_lines[@]}"; do
        _n=${#_l}
        [ "$_n" -gt "$_max" ] && _max=$_n
      done
      # Inner width gets a bit of right padding before the closing border.
      local _inner=$((_max + 2))

      # Top border: ╭─ Session ─────╮   Bottom: ╰──────────────╯
      local _title_seg="─ Session "
      local _top_dashes_n=$((_inner - ${#_title_seg}))
      [ "$_top_dashes_n" -lt 0 ] && _top_dashes_n=0
      local _top_dashes="" _bot_dashes="" _i
      for (( _i=0; _i<_top_dashes_n; _i++ )); do _top_dashes+="─"; done
      for (( _i=0; _i<_inner; _i++ )); do _bot_dashes+="─"; done

      # Colors (ANSI only when stdout is a TTY).
      local c_border='' c_label='' c_title='' c_cmd='' c_reset=''
      if [ -t 1 ]; then
        c_border=$'\033[36m'
        c_label=$'\033[1m'
        c_title=$'\033[1;32m'
        c_cmd=$'\033[2m'
        c_reset=$'\033[0m'
      fi

      # Render one padded, right-bordered line. $1 = plain content (for width);
      # $2 = colored content (what we actually print). The two should render
      # with the same visible width.
      _print_line() {
        local plain="$1" colored="$2"
        local pad=$((_inner - ${#plain}))
        [ "$pad" -lt 0 ] && pad=0
        local spaces=""
        [ "$pad" -gt 0 ] && spaces="$(printf '%*s' "$pad" '')"
        printf '%s│%s%s%s%s│%s\n' "$c_border" "$c_reset" "$colored" "$spaces" "$c_border" "$c_reset"
      }

      # Top + bottom rules.
      printf '%s╭%s%s╮%s\n' "$c_border" "$_title_seg" "$_top_dashes" "$c_reset"

      # Content.
      _print_line \
        "  Session ID:  $sid" \
        "  $c_label""Session ID:$c_reset  $sid"
      _print_line \
        "  Repo:        $proj_base" \
        "  $c_label""Repo:$c_reset        $proj_base"
      if [ -n "$title" ]; then
        _print_line \
          "  Name:        $title" \
          "  $c_label""Name:$c_reset        $c_title$title$c_reset"
      fi
      _print_line \
        "  Path:        $cwd" \
        "  $c_label""Path:$c_reset        $cwd"
      _print_line "" ""
      _print_line \
        "  Resume (cwd-scoped):" \
        "  $c_label""Resume (cwd-scoped):$c_reset"
      _print_line \
        "    cd -- $cwd_q && claude --resume $sid" \
        "    $c_cmd""cd -- $cwd_q && claude --resume $sid$c_reset"

      printf '%s╰%s╯%s\n' "$c_border" "$_bot_dashes" "$c_reset"
      unset -f _print_line
      return 0 ;;
    *)
      if [ ! -d "$cwd" ]; then
        printf 'ccsesh: original project dir %q no longer exists; cannot resume.\n' "$cwd" >&2
        printf 'ccsesh: session transcript remains on disk.\n' >&2
        return 1
      fi
      command -v claude >/dev/null 2>&1 || { echo "ccsesh: claude not on PATH" >&2; return 127; }
      cd -- "$cwd" && exec claude --resume "$sid"
      ;;
  esac
}
