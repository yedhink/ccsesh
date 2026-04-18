#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -P "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
. "$REPO_DIR/lib/util.sh"

_passed=0; _failed=0
assert_eq() {
  if [ "$1" = "$2" ]; then _passed=$((_passed+1)); printf '  ok  %s\n' "$3"
  else _failed=$((_failed+1)); printf '  FAIL %s\n    expected: %q\n    got:      %q\n' "$3" "$2" "$1"; fi
}
assert_match() {
  if printf '%s' "$1" | grep -Eq "$2"; then _passed=$((_passed+1)); printf '  ok  %s\n' "$3"
  else _failed=$((_failed+1)); printf '  FAIL %s\n    regex:  %s\n    input:  %q\n' "$3" "$2" "$1"; fi
}

echo "== util.sh =="

# ccsesh_os returns darwin or linux
os="$(ccsesh_os)"
case "$os" in darwin|linux) ok=1 ;; *) ok=0 ;; esac
assert_eq "$ok" "1" "ccsesh_os returns darwin or linux"

# ccsesh_stat_mtime returns integer epoch for an existing file
tmp="$(mktemp)"
mtime="$(ccsesh_stat_mtime "$tmp")"
assert_match "$mtime" '^[0-9]+$' "ccsesh_stat_mtime returns integer"
rm -f "$tmp"

# ccsesh_iso_to_epoch converts ISO 8601 UTC to epoch
# 2026-04-18T00:00:00Z = 1776470400
got="$(ccsesh_iso_to_epoch '2026-04-18T00:00:00Z')"
assert_eq "$got" "1776470400" "ccsesh_iso_to_epoch 2026-04-18T00:00:00Z"

echo "== util.sh sanitizers =="

got="$(printf 'hello\x01world\x7f' | ccsesh_strip_controls)"
assert_eq "$got" "helloworld" "strip_controls drops SOH and DEL"

got="$(printf 'a\tb\nc' | ccsesh_strip_controls)"
assert_eq "$got" "$(printf 'a\tb\nc')" "strip_controls preserves tab and newline"

got="$(printf 'a\tb\nc' | ccsesh_flatten)"
assert_eq "$got" "a b c" "flatten replaces tab/newline with space"

got="$(printf 'abcdefghij' | ccsesh_truncate 5)"
assert_eq "$got" "abcde" "truncate to 5 chars"

got="$(printf 'abc' | ccsesh_truncate 5)"
assert_eq "$got" "abc" "truncate no-op when shorter"

echo
echo "passed: $_passed  failed: $_failed"
[ "$_failed" -eq 0 ]
