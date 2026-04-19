#!/usr/bin/env bash
set -u

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
