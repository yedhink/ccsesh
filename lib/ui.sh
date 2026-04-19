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
