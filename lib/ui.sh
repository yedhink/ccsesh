#!/usr/bin/env bash
set -u

_UI_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$_UI_DIR/util.sh"

# Internal render helper for ccsesh_ui_preview.
_ccsesh_ui_preview_render() {
  local f="$1"
  jq -Rr '
    fromjson?
    | select(.type == "user" and ((.isMeta // false) | not))
    | .message.content as $c
    | if ($c | type) == "string" then
        if ($c | test("^<(command-|local-command-|system-reminder)")) then empty else $c end
      elif ($c | type) == "array" then
        ( [ $c[]
            | select(.type == "text" and (.text // "") != "")
            | select(.text | test("^<(command-|local-command-|system-reminder)") | not)
            | .text ] | .[] )
      else empty end
  ' < "$f" 2>/dev/null \
    | head -n 30 \
    | ccsesh_strip_controls \
    | sed 's/^/> /'
}

# Print up to 30 human-authored text snippets from a session .jsonl, each on
# its own line prefixed with "> ". Skips isMeta rows, tool_result, and records
# that start with <command-/<local-command-/<system-reminder>.
# If $2 (query) is non-empty, pipe through grep --color to highlight matches
# without filtering — uses the "|$" trick so every line passes grep but only
# matches are colored.
ccsesh_ui_preview() {
  local f="$1"
  local q="${2:-}"
  [ -r "$f" ] || { printf '(session file not readable)\n'; return 0; }
  if [ -n "$q" ]; then
    # Escape regex metacharacters in the query so users searching for "2+2" etc
    # don't accidentally treat their query as a regex.
    local q_esc
    q_esc="$(printf '%s' "$q" | sed -E 's/[][(){}.+*?^$|\\\/]/\\&/g')"
    _ccsesh_ui_preview_render "$f" | grep --color=always -iE "${q_esc}|$" 2>/dev/null \
      || _ccsesh_ui_preview_render "$f"
  else
    _ccsesh_ui_preview_render "$f"
  fi
}

# Build the fzf input. Consumes the raw 8-field stream from
# _ccsesh_sessions_list_raw (epoch, sid, cwd, ts_iso, count, ver, summary,
# extended) and emits 5 tab-delimited fzf fields:
#   1 = sid    (hidden)
#   2 = cwd    (hidden)
#   3 = ts_iso (hidden)
#   4 = colored display + dimmed extended text (visible via --with-nth=4)
#   5 = epoch  (hidden, carried for since: filtering in __fzf_feed)
#
# Fields 1,2,3,5 are not searched by fzf (--with-nth=4 scopes both display
# and search to field 4), but they are present in the selection output so
# bash can read sid/cwd on Enter and __fzf_feed can filter on epoch.
_ccsesh_ui_build_lines() {
  local epoch sid cwd ts_iso count ver summary extended date_short proj_base
  while IFS=$'\t' read -r epoch sid cwd ts_iso count ver summary extended; do
    date_short="${ts_iso%%T*}"
    proj_base="$(basename "$cwd" 2>/dev/null)"
    [ -n "$proj_base" ] || proj_base="(unknown)"
    printf '%s\t%s\t%s\t\033[2m%s\033[0m  \033[36m%s\033[0m  %s  \033[2;90m%s\033[0m\t%s\n' \
      "$sid" "$cwd" "$ts_iso" "$date_short" "$proj_base" "$summary" "$extended" "$epoch"
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
      --header='enter=resume  ctrl-o=print  esc=quit    filters: repo:X  since:Nd|Nh|Nm' \
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

  local key line sid cwd
  key="$(printf '%s\n' "$selection" | head -n 1)"
  line="$(printf '%s\n' "$selection" | sed -n '2p')"
  [ -n "$line" ] || return 0
  sid="$(printf '%s' "$line" | cut -f1)"
  cwd="$(printf '%s' "$line" | cut -f2)"

  case "$key" in
    ctrl-o)
      printf '%s\t%s\n' "$sid" "$cwd"
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
