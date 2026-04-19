#!/usr/bin/env bash
set -u

_UI_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$_UI_DIR/util.sh"

# Print up to 30 human-authored text snippets from a session .jsonl, each on
# its own line prefixed with "> ". Skips isMeta rows, tool_result, and records
# that start with <command-/<local-command-/<system-reminder>.
ccsesh_ui_preview() {
  local f="$1"
  [ -r "$f" ] || { printf '(session file not readable)\n'; return 0; }
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

# Build the fzf input: hidden field = absolute .jsonl path, display fields =
# pretty date + project basename + summary with ANSI colors.
_ccsesh_ui_build_lines() {
  local row f sid cwd ts_iso count ver summary date_short proj_base line
  while IFS=$'\t' read -r sid cwd ts_iso count ver summary; do
    date_short="${ts_iso%%T*}"
    proj_base="$(basename "$cwd" 2>/dev/null)"
    [ -n "$proj_base" ] || proj_base="(unknown)"
    printf '%s\t%s\t%s\t\033[2m%s\033[0m  \033[36m%s\033[0m  %s\n' \
      "$sid" "$cwd" "$ts_iso" "$date_short" "$proj_base" "$summary"
  done
}

# Launch fzf. Expects filter args same as sessions_list.
ccsesh_ui_run() {
  local lines
  lines="$(ccsesh_sessions_list "$@" | _ccsesh_ui_build_lines)"
  if [ -z "$lines" ]; then
    printf 'ccsesh: no sessions found under %s\n' "$(ccsesh_home)" >&2
    return 0
  fi
  # fzf fields: 1=sid, 2=cwd, 3=ts_iso, 4..=display.
  # --with-nth=4.. hides 1..3 from both display and search — so the user
  # searches only on the display text (good; sid/cwd are noise).
  # --ansi interprets the color codes in the display.
  local selection rc
  selection="$(
    printf '%s\n' "$lines" \
      | fzf \
          --ansi \
          --delimiter=$'\t' \
          --with-nth=4.. \
          --prompt='ccsesh> ' \
          --header='enter=resume  ctrl-o=print  esc=quit' \
          --expect=ctrl-o \
          --preview-window='right:50%:wrap' \
          --preview "$CCSESH_DIR/bin/ccsesh __preview {2} {1} 2>/dev/null"
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
