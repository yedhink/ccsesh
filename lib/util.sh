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
