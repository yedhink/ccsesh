#!/usr/bin/env bash
set -u

ccsesh_os() {
  case "$(uname -s)" in
    Darwin) echo darwin ;;
    Linux) echo linux ;;
    *) echo unsupported ;;
  esac
}

# Print file mtime as integer epoch seconds. Prints nothing if the file does
# not exist; returns non-zero in that case so the caller can fall back.
ccsesh_stat_mtime() {
  local f="$1"
  [ -e "$f" ] || return 1
  case "$(ccsesh_os)" in
    darwin) stat -f '%m' -- "$f" ;;
    linux)  stat -c '%Y' -- "$f" ;;
    *) return 1 ;;
  esac
}

# Convert an ISO 8601 timestamp (with Z or numeric offset) to integer epoch.
# Accepts forms: 2026-04-18T00:00:00Z, 2026-04-18T00:00:00.123Z,
# 2026-04-18T05:30:00+0530. Prints nothing on failure, returns non-zero.
ccsesh_iso_to_epoch() {
  local ts="$1"
  # Strip fractional seconds — neither macOS nor GNU date parses them cleanly.
  ts="$(printf '%s' "$ts" | sed -E 's/\.[0-9]+//')"
  case "$(ccsesh_os)" in
    darwin)
      # macOS date supports -j -f. Try Z first, then +HHMM.
      if printf '%s' "$ts" | grep -q 'Z$'; then
        TZ=UTC date -j -f '%Y-%m-%dT%H:%M:%SZ' "$ts" '+%s' 2>/dev/null
      else
        date -j -f '%Y-%m-%dT%H:%M:%S%z' "$ts" '+%s' 2>/dev/null
      fi
      ;;
    linux)
      date -d "$ts" '+%s' 2>/dev/null
      ;;
    *) return 1 ;;
  esac
}

# Read stdin, drop C0 controls (0x00-0x08, 0x0b, 0x0c, 0x0e-0x1f) and DEL
# (0x7f). Preserves \t (0x09) and \n (0x0a).
ccsesh_strip_controls() {
  LC_ALL=C tr -d '\000-\010\013\014\016-\037\177'
}

# Read stdin, replace \t and \n with single spaces, squeeze runs of spaces.
ccsesh_flatten() {
  LC_ALL=C tr '\t\n' '  ' | tr -s ' '
}

# Read stdin, emit at most $1 bytes (portable, no bash 4 features).
ccsesh_truncate() {
  local n="$1"
  head -c "$n"
}

# Append a timestamped message to /tmp/ccsesh-debug.log when CCSESH_DEBUG is
# set to a non-empty value. No-op (and cheap) otherwise. Never fails.
_ccsesh_debug() {
  [ -n "${CCSESH_DEBUG:-}" ] || return 0
  local ts
  ts="$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)"
  printf '[%s] %s\n' "$ts" "$*" >> /tmp/ccsesh-debug.log 2>/dev/null || true
}
