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

# Build a synthetic Claude home under $1.
ccsesh_fixture_build() {
  local root="$1"
  rm -rf "$root"
  mkdir -p "$root/projects/-Users-ikigai-dev-neeto-products"
  mkdir -p "$root/projects/-Users-ikigai-dev-neeto-products/aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa/subagents"
  mkdir -p "$root/projects/-Users-ikigai-dev-neeto-products/memory"
  mkdir -p "$root/projects/-tmp-deleted-project"
  printf 'MEMORY' > "$root/projects/-Users-ikigai-dev-neeto-products/memory/MEMORY.md"
  printf 'junk\n' > "$root/projects/-Users-ikigai-dev-neeto-products/not-a-session.txt"
  printf 'irrelevant\n' > "$root/projects/-Users-ikigai-dev-neeto-products/aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa/subagents/inner.jsonl"

  # Session A: string content, has a meta row and a real user prompt.
  local a="$root/projects/-Users-ikigai-dev-neeto-products/aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa.jsonl"
  {
    printf '%s\n' '{"type":"user","isMeta":true,"sessionId":"aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa","cwd":"/Users/ikigai/dev/neeto-products","gitBranch":"main","version":"2.1.83","timestamp":"2026-04-18T10:00:00.000Z","message":{"role":"user","content":"<command-name>/model</command-name>"}}'
    printf '%s\n' '{"type":"user","sessionId":"aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa","cwd":"/Users/ikigai/dev/neeto-products","gitBranch":"main","version":"2.1.83","timestamp":"2026-04-18T10:00:05.000Z","message":{"role":"user","content":"Write a function that reverses a linked list."}}'
    printf '%s\n' '{"type":"assistant","sessionId":"aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa","cwd":"/Users/ikigai/dev/neeto-products","gitBranch":"main","version":"2.1.83","timestamp":"2026-04-18T10:00:06.000Z","message":{"role":"assistant","content":"Sure, here it is."}}'
  } > "$a"

  # Session B: only array-shaped content with a text block; trailing truncated line.
  local b="$root/projects/-Users-ikigai-dev-neeto-products/bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb.jsonl"
  {
    printf '%s\n' '{"type":"user","sessionId":"bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb","cwd":"/Users/ikigai/dev/neeto-products","gitBranch":"feat/x","version":"2.1.80","timestamp":"2026-04-18T09:00:00.000Z","message":{"role":"user","content":[{"type":"tool_result","content":"noise"},{"type":"text","text":"Refactor the queue consumer to batch acks."}]}}'
    printf '%s\n' '{"type":"assistant","sessionId":"bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb","cwd":"/Users/ikigai/dev/neeto-products","gitBranch":"feat/x","version":"2.1.80","timestamp":"2026-04-18T09:00:05.000Z","message":{"role":"assistant","content":"OK."}}'
    printf '{"type":"user","sessio'  # truncated — no newline, no closing
  } > "$b"

  # Session C: cwd points at deleted project.
  local c="$root/projects/-tmp-deleted-project/cccccccc-cccc-4ccc-cccc-cccccccccccc.jsonl"
  printf '%s\n' '{"type":"user","sessionId":"cccccccc-cccc-4ccc-cccc-cccccccccccc","cwd":"/tmp/definitely-does-not-exist-xyz","gitBranch":"main","version":"2.1.83","timestamp":"2026-04-17T08:00:00.000Z","message":{"role":"user","content":"What happened to this project?"}}' > "$c"

  # history.jsonl: one match for session A (display differs from .jsonl prompt to prove we prefer history), no row for B (so .jsonl fallback kicks in), no row for C.
  {
    printf '%s\n' '{"display":"Reverse a linked list in Rust please","timestamp":1776470405000,"project":"/Users/ikigai/dev/neeto-products","sessionId":"aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa"}'
    printf '%s\n' '{"display":"some older aaaaaa prompt","timestamp":1776460000000,"project":"/Users/ikigai/dev/neeto-products","sessionId":"aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa"}'
  } > "$root/history.jsonl"

  # Touch mtimes deterministically (seconds-precision) so recency ties break predictably.
  touch -t 202604181000.00 "$a"
  touch -t 202604180900.00 "$b"
  touch -t 202604170800.00 "$c"
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

echo "== sessions.sh discover =="

fixture_root="/tmp/ccsesh-fx-$$"
ccsesh_fixture_build "$fixture_root"
export CCSESH_CLAUDE_HOME="$fixture_root"
. "$REPO_DIR/lib/sessions.sh"

# shellcheck disable=SC2207
got=( $(ccsesh_sessions_discover | LC_ALL=C sort) )
expected_a="$fixture_root/projects/-Users-ikigai-dev-neeto-products/aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa.jsonl"
expected_b="$fixture_root/projects/-Users-ikigai-dev-neeto-products/bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb.jsonl"
expected_c="$fixture_root/projects/-tmp-deleted-project/cccccccc-cccc-4ccc-cccc-cccccccccccc.jsonl"

assert_eq "${#got[@]}" "3" "discover finds exactly 3 sessions"
assert_eq "${got[0]}" "$expected_a" "discover[0] is session A"
assert_eq "${got[1]}" "$expected_b" "discover[1] is session B"
assert_eq "${got[2]}" "$expected_c" "discover[2] is session C"

echo
echo "passed: $_passed  failed: $_failed"
[ "$_failed" -eq 0 ]
