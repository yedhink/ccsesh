#!/usr/bin/env bash
set -u

_SESSIONS_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$_SESSIONS_DIR/util.sh"

# Resolve the Claude home dir. Callers may override with $CCSESH_CLAUDE_HOME.
ccsesh_home() {
  printf '%s\n' "${CCSESH_CLAUDE_HOME:-$HOME/.claude}"
}

# Emit one absolute .jsonl path per line. Candidates are exactly:
#   <claude_home>/projects/<any-dir>/<uuid>.jsonl
# where <uuid> matches the 36-char 8-4-4-4-12 shape. Nothing deeper.
#
# Silent skip (exit 0, no rows) if projects/ does not exist.
ccsesh_sessions_discover() {
  local home; home="$(ccsesh_home)"
  local projects="$home/projects"
  [ -d "$projects" ] || return 0
  local uuid_re='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jsonl$'
  local d f base
  for d in "$projects"/*/; do
    [ -d "$d" ] || continue
    for f in "$d"*.jsonl; do
      [ -f "$f" ] || continue
      base="$(basename "$f")"
      if printf '%s' "$base" | grep -Eq "$uuid_re"; then
        printf '%s\n' "$f"
      fi
    done
  done
}

# Print the .cwd field of the first parseable record in a session .jsonl.
# Silent (empty stdout, non-zero return) if no record has a .cwd.
ccsesh_session_cwd() {
  local f="$1"
  [ -r "$f" ] || return 1
  local out
  out="$(jq -Rr 'fromjson? | .cwd // empty' < "$f" 2>/dev/null | head -n 1)"
  [ -n "$out" ] || return 1
  printf '%s\n' "$out"
}

# Print the .display field of the most recent history.jsonl row with a
# matching sessionId. Non-zero exit if no match or file missing.
ccsesh_history_display() {
  local sid="$1"
  local hist; hist="$(ccsesh_home)/history.jsonl"
  [ -r "$hist" ] || return 1
  local out
  out="$(jq -Rr --arg sid "$sid" '
    fromjson?
    | select(.sessionId == $sid and (.display // "") != "")
    | [(.timestamp // 0), .display]
    | @tsv
  ' < "$hist" 2>/dev/null | sort -rn | head -n 1 | cut -f2-)"
  [ -n "$out" ] || return 1
  printf '%s\n' "$out"
}

# Internal: extract best candidate user-authored text from a .jsonl.
# Priority within the file:
#   1. First non-meta user record where .message.content is a string and
#      does not begin with <command-, <local-command-, or <system-reminder>.
#   2. First non-meta user record with array content: first element whose
#      .type == "text" and .text doesn't start with those wrappers.
# Emits nothing (and returns non-zero) if no candidate is found.
_ccsesh_extract_user_text() {
  local f="$1"
  local out
  out="$(jq -Rr '
    fromjson?
    | select(.type == "user" and ((.isMeta // false) | not))
    | .message.content as $c
    | if ($c | type) == "string" then
        if ($c | test("^<(command-|local-command-|system-reminder)")) then empty else $c end
      elif ($c | type) == "array" then
        ( [ $c[]
            | select(.type == "text" and (.text // "") != "")
            | select(.text | test("^<(command-|local-command-|system-reminder)") | not)
            | .text ][0] // empty )
      else empty end
  ' < "$f" 2>/dev/null | head -n 1)"
  [ -n "$out" ] || return 1
  printf '%s' "$out"
}

# Public: resolve display summary for a session. Always prints exactly one
# line; never fails (falls through to "<no prompt yet>").
ccsesh_session_summary() {
  local f="$1" sid="$2"
  local raw
  if raw="$(ccsesh_history_display "$sid")"; then :; else
    if raw="$(_ccsesh_extract_user_text "$f")"; then :; else
      raw="<no prompt yet>"
    fi
  fi
  printf '%s' "$raw" \
    | ccsesh_strip_controls \
    | ccsesh_flatten \
    | ccsesh_truncate 80
  printf '\n'
}

# Print max event .timestamp (as epoch seconds) across a session file.
# Uses the last 200 lines which is more than enough to find the max assuming
# timestamps are monotonically non-decreasing. Falls back to file mtime.
ccsesh_session_recency() {
  local f="$1"
  local iso
  iso="$(tail -n 200 "$f" 2>/dev/null | jq -Rr 'fromjson? | .timestamp // empty' 2>/dev/null | sort | tail -n 1)"
  if [ -n "$iso" ]; then
    local epoch
    epoch="$(ccsesh_iso_to_epoch "$iso")"
    if [ -n "$epoch" ]; then printf '%s\n' "$epoch"; return 0; fi
  fi
  ccsesh_stat_mtime "$f"
}

# Print count of records where .type is "user" or "assistant" and
# .isMeta is not true.
ccsesh_session_count() {
  local f="$1"
  jq -Rr '
    fromjson?
    | select((.type == "user" or .type == "assistant") and ((.isMeta // false) | not))
    | 1
  ' < "$f" 2>/dev/null | wc -l | tr -d ' '
}

ccsesh_session_version() {
  local f="$1"
  jq -Rr 'fromjson? | .version // empty' < "$f" 2>/dev/null | head -n 1
}

ccsesh_session_id() {
  local f="$1"
  jq -Rr 'fromjson? | .sessionId // empty' < "$f" 2>/dev/null | head -n 1
}

# Format an epoch as ISO 8601 with numeric offset (e.g. 2026-04-18T19:07:42+0530).
_ccsesh_epoch_to_iso_offset() {
  local e="$1"
  case "$(ccsesh_os)" in
    darwin) date -r "$e" '+%Y-%m-%dT%H:%M:%S%z' ;;
    linux)  date -d "@$e" '+%Y-%m-%dT%H:%M:%S%z' ;;
  esac
}

# Parse --since spec (Nd|Nh|Nm). Prints delta seconds on stdout, returns
# non-zero (and emits error to stderr) on invalid input.
_ccsesh_since_to_seconds() {
  local spec="$1"
  if ! printf '%s' "$spec" | grep -Eq '^[0-9]+[dhm]$'; then
    printf 'ccsesh: invalid --since %q (expected Nd, Nh, or Nm)\n' "$spec" >&2
    return 2
  fi
  local n unit
  n="${spec%[dhm]}"
  unit="${spec: -1}"
  case "$unit" in
    d) printf '%s\n' "$((n * 86400))" ;;
    h) printf '%s\n' "$((n * 3600))" ;;
    m) printf '%s\n' "$((n * 60))" ;;
  esac
}

# Normalize a path for --project comparison: use $PWD-style canonicalization
# when the dir exists, else keep the raw input.
_ccsesh_normalize_path() {
  local p="$1"
  if [ -d "$p" ]; then ( cd -P -- "$p" && pwd -P )
  else printf '%s\n' "$p"; fi
}

# Internal: raw 8-field pipeline — epoch \t sid \t cwd \t iso_ts \t count \t ver \t summary \t extended.
# Sorted desc by epoch. Used by both the public --list wrapper (which drops
# epoch + extended) and by the UI layer (which drops only epoch).
#
# Accepts the same --project / --since flags as the public list.
_ccsesh_sessions_list_raw() {
  local project="" since_sec=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --project)
        [ $# -ge 2 ] || { echo "ccsesh: --project requires a value" >&2; return 2; }
        project="$(_ccsesh_normalize_path "$2")"; shift 2 ;;
      --since)
        [ $# -ge 2 ] || { echo "ccsesh: --since requires a value" >&2; return 2; }
        since_sec="$(_ccsesh_since_to_seconds "$2")" || return 2
        shift 2 ;;
      *) printf 'ccsesh: unknown list arg %q\n' "$1" >&2; return 2 ;;
    esac
  done
  local cutoff=""
  [ -n "$since_sec" ] && cutoff="$(( $(date +%s) - since_sec ))"

  _ccsesh_debug "list: project=${project:-(any)} since_sec=${since_sec:-(none)}"

  local hist_map
  hist_map="$(mktemp -t ccsesh.XXXXXX)"
  _ccsesh_debug "list: scanning history.jsonl"
  _ccsesh_history_map > "$hist_map"
  _ccsesh_debug "list: history map has $(grep -c '' "$hist_map") entries"

  local f raw sid cwd raw_ts count ver summary extended epoch hist_display ts_final
  local emitted=0
  _ccsesh_debug "list: starting per-session loop"
  while IFS= read -r f; do
    raw="$(_ccsesh_row_extract "$f")" || continue
    IFS=$'\t' read -r sid cwd raw_ts count ver summary extended <<<"$raw"
    [ -n "$sid" ] || continue

    if [ -n "$project" ] && [ "$cwd" != "$project" ]; then continue; fi

    epoch=""
    if [ -n "$raw_ts" ]; then epoch="$(ccsesh_iso_to_epoch "$raw_ts")"; fi
    if [ -z "$epoch" ]; then epoch="$(ccsesh_stat_mtime "$f" 2>/dev/null)" || epoch=""; fi
    [ -n "$epoch" ] || continue

    if [ -n "$cutoff" ] && [ "$epoch" -lt "$cutoff" ]; then continue; fi

    # History display override.
    hist_display="$(awk -F'\t' -v sid="$sid" '$1==sid { print $2; exit }' "$hist_map")"
    [ -n "$hist_display" ] && summary="$hist_display"
    [ -n "$summary" ] || summary="<no prompt yet>"

    # Sanitize.
    summary="$(printf '%s' "$summary" | ccsesh_strip_controls | ccsesh_flatten | ccsesh_truncate 80)"
    extended="$(printf '%s' "$extended" | ccsesh_strip_controls | ccsesh_flatten | ccsesh_truncate 500)"

    ts_final="$(_ccsesh_epoch_to_iso_offset "$epoch")"

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$epoch" "$sid" "$cwd" "$ts_final" "$count" "$ver" "$summary" "$extended"
    emitted=$((emitted+1))
  done < <(ccsesh_sessions_discover) \
    | sort -t $'\t' -k1,1rn

  rm -f "$hist_map"
  _ccsesh_debug "list: done, emitted=$emitted"
}

# Public: human-facing 6-field TSV. Same contract as before.
ccsesh_sessions_list() {
  local _rc=0
  (set -o pipefail; _ccsesh_sessions_list_raw "$@" | cut -f 2-7) || _rc=$?
  return $_rc
}

# Internal: extract all per-session fields in ONE jq pass.
# Prints: raw_sid \t raw_cwd \t raw_iso_ts \t raw_count \t raw_version \t raw_summary \t raw_extended
# Fields are NOT sanitized — caller must strip controls/flatten/truncate before use.
# Returns non-zero if the file can't be read or yields no sessionId.
_ccsesh_row_extract() {
  local f="$1"
  [ -r "$f" ] || return 1
  local out
  out="$(jq -Rsr '
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

    (split("\n") | map(fromjson?) | map(select(. != null))) as $R
    | ([$R[] | select(.sessionId != null) | .sessionId] | first // "") as $sid
    | ([$R[] | select(.cwd != null) | .cwd] | first // "") as $cwd
    | ([$R[] | select(.version != null) | .version] | first // "") as $ver
    | ([ $R[]
       | select(.type == "user" and ((.isMeta // false) | not))
       | (.message.content | user_text)
       | select(. != "")
       ]) as $texts
    | [
        $sid,
        $cwd,
        ([$R[] | .timestamp // empty] | max // ""),
        ([$R[] | select((.type == "user" or .type == "assistant") and ((.isMeta // false) | not))] | length | tostring),
        $ver,
        ($texts[0] // ""),
        ($texts | join(" ") | .[0:500])
      ]
    | @tsv
  ' < "$f" 2>/dev/null)"
  [ -n "$out" ] || return 1
  # Guard: must have a non-empty sessionId in field 1.
  case "$out" in $'\t'*) return 1 ;; esac
  printf '%s\n' "$out"
}

# Internal: print sid\tdisplay lines for every unique sessionId in
# history.jsonl, keeping the most recent display per sessionId.
# Silent (no output) if history.jsonl is missing.
_ccsesh_history_map() {
  local hist; hist="$(ccsesh_home)/history.jsonl"
  [ -r "$hist" ] || return 0
  jq -Rr '
    fromjson?
    | select(.sessionId != null and (.display // "") != "")
    | [(.timestamp // 0), .sessionId, .display] | @tsv
  ' < "$hist" 2>/dev/null \
    | sort -k1,1rn -t $'\t' \
    | awk -F'\t' '!seen[$2]++ { print $2 "\t" $3 }'
}

# Emit a single TSV row for a session .jsonl.
ccsesh_session_row() {
  local f="$1"
  local sid cwd rec_ts count ver summary ts_iso
  sid="$(ccsesh_session_id "$f")"
  [ -n "$sid" ] || return 1
  cwd="$(ccsesh_session_cwd "$f")" || cwd=""
  rec_ts="$(ccsesh_session_recency "$f")"
  ts_iso="$(_ccsesh_epoch_to_iso_offset "$rec_ts")"
  count="$(ccsesh_session_count "$f")"
  ver="$(ccsesh_session_version "$f")"
  summary="$(ccsesh_session_summary "$f" "$sid")"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$sid" "$cwd" "$ts_iso" "$count" "$ver" "$summary"
}
