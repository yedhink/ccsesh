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

  # Session D: newest. Has a custom-title record; user AND assistant both
  # mention "webhook" (for highlight-scope tests). Assistant mentions
  # "signature" which the user does NOT — used to verify filter ignores
  # assistant text. Opening user message has 3 sentences (to exercise the
  # 2-sentence truncation + "…" ellipsis in the preview header snippet).
  local d="$root/projects/-Users-ikigai-dev-neeto-products/dddddddd-dddd-4ddd-dddd-dddddddddddd.jsonl"
  {
    printf '%s\n' '{"type":"user","sessionId":"dddddddd-dddd-4ddd-dddd-dddddddddddd","cwd":"/Users/ikigai/dev/neeto-products","gitBranch":"main","version":"2.1.90","timestamp":"2026-04-18T11:00:00.000Z","message":{"role":"user","content":"Debug the webhook handler. The validation seems off on some events. I see timeouts too."}}'
    printf '%s\n' '{"type":"assistant","sessionId":"dddddddd-dddd-4ddd-dddd-dddddddddddd","cwd":"/Users/ikigai/dev/neeto-products","gitBranch":"main","version":"2.1.90","timestamp":"2026-04-18T11:00:05.000Z","message":{"role":"assistant","content":"The webhook handler at webhooks.rb needs signature validation."}}'
    printf '%s\n' '{"type":"custom-title","sessionId":"dddddddd-dddd-4ddd-dddd-dddddddddddd","customTitle":"webhook-debugging"}'
  } > "$d"

  # history.jsonl: one match for session A (display differs from .jsonl prompt to prove we prefer history), no row for B (so .jsonl fallback kicks in), no row for C or D.
  {
    printf '%s\n' '{"display":"Reverse a linked list in Rust please","timestamp":1776470405000,"project":"/Users/ikigai/dev/neeto-products","sessionId":"aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa"}'
    printf '%s\n' '{"display":"some older aaaaaa prompt","timestamp":1776460000000,"project":"/Users/ikigai/dev/neeto-products","sessionId":"aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa"}'
  } > "$root/history.jsonl"

  # Touch mtimes deterministically (seconds-precision) so recency ties break predictably.
  touch -t 202604181000.00 "$a"
  touch -t 202604180900.00 "$b"
  touch -t 202604170800.00 "$c"
  touch -t 202604181100.00 "$d"
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
expected_d="$fixture_root/projects/-Users-ikigai-dev-neeto-products/dddddddd-dddd-4ddd-dddd-dddddddddddd.jsonl"
expected_c="$fixture_root/projects/-tmp-deleted-project/cccccccc-cccc-4ccc-cccc-cccccccccccc.jsonl"

assert_eq "${#got[@]}" "4" "discover finds exactly 4 sessions"
assert_eq "${got[0]}" "$expected_a" "discover[0] is session A"
assert_eq "${got[1]}" "$expected_b" "discover[1] is session B"
assert_eq "${got[2]}" "$expected_d" "discover[2] is session D (same project as A/B)"
assert_eq "${got[3]}" "$expected_c" "discover[3] is session C (different project)"

echo "== sessions.sh cwd =="

got="$(ccsesh_session_cwd "$expected_a")"
assert_eq "$got" "/Users/ikigai/dev/neeto-products" "cwd for session A preserves embedded hyphen"

got="$(ccsesh_session_cwd "$expected_b")"
assert_eq "$got" "/Users/ikigai/dev/neeto-products" "cwd for session B resolves despite trailing truncation"

got="$(ccsesh_session_cwd "$expected_c")"
assert_eq "$got" "/tmp/definitely-does-not-exist-xyz" "cwd for session C preserves path even if dir gone"

echo "== sessions.sh history =="

got="$(ccsesh_history_display 'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa')"
assert_eq "$got" "Reverse a linked list in Rust please" "history_display picks most recent match"

got="$(ccsesh_history_display 'bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb'; echo "[rc=$?]")"
assert_match "$got" '^\[rc=1\]$' "history_display returns non-zero when no match"

echo "== sessions.sh summary =="

got="$(ccsesh_session_summary "$expected_a" 'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa')"
assert_eq "$got" "Reverse a linked list in Rust please" "session A: prefers history.jsonl display"

got="$(ccsesh_session_summary "$expected_b" 'bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb')"
assert_eq "$got" "Refactor the queue consumer to batch acks." "session B: falls back to .jsonl array text block"

got="$(ccsesh_session_summary "$expected_c" 'cccccccc-cccc-4ccc-cccc-cccccccccccc')"
assert_eq "$got" "What happened to this project?" "session C: falls back to .jsonl string content"

# Empty-session fallback
empty="$(mktemp)"; printf '\n' > "$empty"
got="$(ccsesh_session_summary "$empty" 'zzzzzzzz-zzzz-4zzz-zzzz-zzzzzzzzzzzz')"
assert_eq "$got" "<no prompt yet>" "empty session: final fallback"
rm -f "$empty"

echo "== sessions.sh recency + count =="

got="$(ccsesh_session_recency "$expected_a")"
# 2026-04-18T10:00:06Z = 1776506406
assert_eq "$got" "1776506406" "recency A = last event timestamp"

got="$(ccsesh_session_count "$expected_a")"
assert_eq "$got" "2" "count A = 1 user (non-meta) + 1 assistant"

got="$(ccsesh_session_count "$expected_b")"
assert_eq "$got" "2" "count B = 1 user (array, non-meta) + 1 assistant, truncated line skipped"

echo "== sessions.sh row =="

got="$(ccsesh_session_version "$expected_a")"
assert_eq "$got" "2.1.83" "version A"

row="$(ccsesh_session_row "$expected_a")"
# Expected fields: sid, cwd, ts_iso, count, version, summary
sid_got="$(printf '%s' "$row" | cut -f1)"
cwd_got="$(printf '%s' "$row" | cut -f2)"
count_got="$(printf '%s' "$row" | cut -f4)"
ver_got="$(printf '%s' "$row" | cut -f5)"
sum_got="$(printf '%s' "$row" | cut -f6)"
assert_eq "$sid_got" "aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa" "row A sid"
assert_eq "$cwd_got" "/Users/ikigai/dev/neeto-products" "row A cwd"
assert_eq "$count_got" "2" "row A count"
assert_eq "$ver_got" "2.1.83" "row A version"
assert_eq "$sum_got" "Reverse a linked list in Rust please" "row A summary"
assert_match "$(printf '%s' "$row" | cut -f3)" '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{4}$' "row A timestamp iso 8601 with offset"

echo "== sessions.sh list =="

# Default: all 4 rows, sorted by recency desc. Recency order: D (11:00) > A
# (10:00) > B (09:00) > C (yesterday at 08:00).
rows="$(ccsesh_sessions_list)"
line_count="$(printf '%s' "$rows" | grep -c '')"
assert_eq "$line_count" "4" "list default: 4 rows"
first_sid="$(printf '%s' "$rows" | head -n 1 | cut -f1)"
assert_eq "$first_sid" "dddddddd-dddd-4ddd-dddd-dddddddddddd" "list default: newest first = D"
last_sid="$(printf '%s' "$rows" | tail -n 1 | cut -f1)"
assert_eq "$last_sid" "cccccccc-cccc-4ccc-cccc-cccccccccccc" "list default: oldest last = C"

# --project filter — A, B, D share this cwd.
rows="$(ccsesh_sessions_list --project /Users/ikigai/dev/neeto-products)"
line_count="$(printf '%s' "$rows" | grep -c '')"
assert_eq "$line_count" "3" "list --project filters to matching cwd (A, B, D)"

# --since 2d (from 2026-04-18 00:00 UTC). Session C has ts 2026-04-17 which is within 2d, so all 3.
# --since 1h (relative to now) - on a real run, probably 0. Just ensure command runs.
rows="$(ccsesh_sessions_list --since 1h 2>/dev/null || true)"
# No assertion on count here — wall-clock dependent.

# Invalid --since
rc=0; ccsesh_sessions_list --since bogus >/dev/null 2>&1 || rc=$?
assert_eq "$rc" "2" "list --since bogus exits 2"

echo "== bin/ccsesh arg parsing =="

out="$("$REPO_DIR/bin/ccsesh" --version)"
assert_match "$out" '^ccsesh [0-9]+\.[0-9]+\.[0-9]+$' "--version prints semver"

out="$("$REPO_DIR/bin/ccsesh" --help)"
assert_match "$out" 'Usage:' "--help mentions Usage"
assert_match "$out" '\-\-list' "--help documents --list"

out="$(CCSESH_CLAUDE_HOME="$fixture_root" "$REPO_DIR/bin/ccsesh" --list)"
line_count="$(printf '%s\n' "$out" | grep -c '')"
assert_eq "$line_count" "4" "--list against fixture: 4 rows"

rc=0; "$REPO_DIR/bin/ccsesh" --bogus >/dev/null 2>&1 || rc=$?
assert_eq "$rc" "2" "unknown flag exits 2"

echo "== ui.sh preview =="

. "$REPO_DIR/lib/ui.sh"

preview="$(ccsesh_ui_preview "$expected_a")"
assert_match "$preview" 'Write a function that reverses a linked list' "preview A includes the prompt"
# Meta/<command-name> entry must be excluded
if printf '%s' "$preview" | grep -q '<command-name>'; then
  _failed=$((_failed+1)); echo "  FAIL preview A excludes <command-name>"
else
  _passed=$((_passed+1)); echo "  ok  preview A excludes <command-name>"
fi

preview="$(ccsesh_ui_preview "$expected_b")"
assert_match "$preview" 'Refactor the queue consumer' "preview B pulls array-text block"
if printf '%s' "$preview" | grep -q 'tool_result'; then
  _failed=$((_failed+1)); echo "  FAIL preview B excludes tool_result"
else
  _passed=$((_passed+1)); echo "  ok  preview B excludes tool_result"
fi

echo "== custom-title extraction =="

# Session D has a custom-title record; the raw 9-field pipeline must expose it.
title_d="$(jq -Rsr "$_CCSESH_ROW_JQ" "$expected_d" 2>/dev/null | awk -F'\t' '{print $9}')"
assert_eq "$title_d" "webhook-debugging" "row_extract emits custom-title as field 9"

# Session A has NO custom-title → empty string (not 'null').
title_a="$(jq -Rsr "$_CCSESH_ROW_JQ" "$expected_a" 2>/dev/null | awk -F'\t' '{print $9}')"
assert_eq "$title_a" "" "row_extract emits empty title when session lacks custom-title"

echo "== query regex builder =="

got="$(_ccsesh_ui_query_to_regex 'transcript')"
assert_eq "$got" "transcript" "plain term passes through"

got="$(_ccsesh_ui_query_to_regex 'transcript !neeraj')"
assert_eq "$got" "transcript" "negation term is dropped"

got="$(_ccsesh_ui_query_to_regex '!neeraj')"
assert_eq "$got" "" "only-negation query yields empty regex"

got="$(_ccsesh_ui_query_to_regex '^2026 transcript')"
assert_eq "$got" "2026|transcript" "prefix caret stripped, terms alternated"

got="$(_ccsesh_ui_query_to_regex 'foo$')"
assert_eq "$got" "foo" "suffix dollar stripped"

got="$(_ccsesh_ui_query_to_regex "'foo")"
assert_eq "$got" "foo" "leading apostrophe stripped"

got="$(_ccsesh_ui_query_to_regex 'repo:foo since:7d name:bar baz')"
assert_eq "$got" "baz" "filter tokens dropped"

got="$(_ccsesh_ui_query_to_regex 'a.b c+d')"
assert_eq "$got" 'a\.b|c\+d' "regex metacharacters escaped"

echo "== __fzf_feed filters =="

# Build the UI cache the way ccsesh_ui_run does.
fzf_cache="$(mktemp -t ccsesh.test.XXXXXX)"
_ccsesh_sessions_list_raw | _ccsesh_ui_build_lines > "$fzf_cache"
export CCSESH_UI_CACHE="$fzf_cache"

# Empty query: all 4 rows pass through.
got_n="$("$REPO_DIR/bin/ccsesh" __fzf_feed '' | grep -c '')"
assert_eq "$got_n" "4" "__fzf_feed empty query returns all 4"

# repo: filter narrows on basename(cwd), NOT on the encoded projects-dir
# name. Session C's cwd basename is "definitely-does-not-exist-xyz".
got_n="$("$REPO_DIR/bin/ccsesh" __fzf_feed 'repo:does-not-exist' | grep -c '')"
assert_eq "$got_n" "1" "__fzf_feed repo: matches basename(cwd), not projects-dir name"

got_n="$("$REPO_DIR/bin/ccsesh" __fzf_feed 'repo:neeto-products' | grep -c '')"
assert_eq "$got_n" "3" "__fzf_feed repo:neeto-products matches A, B, D"

# name: filter — only D has a custom-title.
got_n="$("$REPO_DIR/bin/ccsesh" __fzf_feed 'name:webhook' | grep -c '')"
assert_eq "$got_n" "1" "__fzf_feed name:webhook matches only D"

got_n="$("$REPO_DIR/bin/ccsesh" __fzf_feed 'name:nonexistent' | grep -c '')"
assert_eq "$got_n" "0" "__fzf_feed name:nonexistent matches nothing"

# Text search is substring-exact (NOT fuzzy). "wbhk" should not match "webhook"
# even though the letters appear in order.
got_n="$("$REPO_DIR/bin/ccsesh" __fzf_feed 'wbhk' | grep -c '')"
assert_eq "$got_n" "0" "__fzf_feed in exact mode does not do fuzzy matching"

got_n="$("$REPO_DIR/bin/ccsesh" __fzf_feed 'webhook' | grep -c '')"
assert_eq "$got_n" "1" "__fzf_feed 'webhook' substring match hits D"

# Filter scope is user-only — 'signature' appears only in D's assistant
# reply, so D must NOT match.
got_n="$("$REPO_DIR/bin/ccsesh" __fzf_feed 'signature' | grep -c '')"
assert_eq "$got_n" "0" "__fzf_feed ignores assistant-only text"

# Combined filters AND together.
got_n="$("$REPO_DIR/bin/ccsesh" __fzf_feed 'webhook repo:neeto-products' | grep -c '')"
assert_eq "$got_n" "1" "__fzf_feed combines text + repo filters"

rm -f "$fzf_cache"

echo "== preview highlight scope (user-only) =="

# Query 'webhook' matches both user and assistant lines in session D.
# The highlight ANSI (\033[01;31m) must appear only on the user line.
preview_d="$(ccsesh_ui_preview "$expected_d" 'webhook')"

# Extract the line that starts with "> " (user) and the first line that
# starts with the cyan-wrapped "⏺".
user_line="$(printf '%s\n' "$preview_d" | grep -m 1 '^> ')"
if printf '%s' "$user_line" | grep -q $'\033\[01;31m'; then
  _passed=$((_passed+1)); echo "  ok  preview D: user line has red highlight on 'webhook'"
else
  _failed=$((_failed+1)); echo "  FAIL preview D: user line missing red highlight"
  echo "    line: $(printf '%s' "$user_line" | cat)"
fi

# Assistant line: whole line wrapped in cyan \033[36m...\033[0m, no red ANSI inside.
assistant_line="$(printf '%s\n' "$preview_d" | grep -m 1 '⏺')"
if printf '%s' "$assistant_line" | grep -q $'\033\[01;31m'; then
  _failed=$((_failed+1)); echo "  FAIL preview D: assistant line has red highlight (should be cyan only)"
else
  _passed=$((_passed+1)); echo "  ok  preview D: assistant line has no red highlight"
fi
if printf '%s' "$assistant_line" | grep -q $'\033\[36m'; then
  _passed=$((_passed+1)); echo "  ok  preview D: assistant line is cyan-wrapped"
else
  _failed=$((_failed+1)); echo "  FAIL preview D: assistant line missing cyan ANSI"
fi

# Helper: strip ANSI escape sequences from stdin. Used so downstream awk
# patterns can anchor on plain-text markers that would otherwise be hidden
# behind color codes.
strip_ansi() {
  sed -E $'s/\E\\[[0-9;]*[a-zA-Z]//g'
}

# Scroll-to-match scope: a query that matches ONLY an assistant line should
# anchor at the top (first_line=1), not at the assistant's line.
# 'signature' is assistant-only in D. After stripping ANSI, the first line
# after the "────" separator should be the user's "> Debug the webhook ...".
preview_sig="$(ccsesh_ui_preview "$expected_d" 'signature' | strip_ansi)"
first_body_line="$(printf '%s\n' "$preview_sig" | awk '/^────/ { body=1; next } body { print; exit }')"
assert_match "$first_body_line" '^> Debug the webhook' "scroll-to-match ignores assistant-only matches"

echo "== preview header snippet =="

# Session D's opener: "Debug the webhook handler. The validation seems off
# on some events. I see timeouts too." — 3 sentences. We truncate to 2, so
# "I see timeouts too." is dropped and "…" is appended.
preview_d_plain="$(ccsesh_ui_preview "$expected_d" | strip_ansi | awk '/^Session started with:/{flag=1; next} flag {print; exit}')"
assert_match "$preview_d_plain" 'Debug the webhook handler\. The validation seems off on some events\.' "snippet contains first 2 sentences"
assert_match "$preview_d_plain" '…$' "snippet ends with ellipsis when truncated"
if printf '%s' "$preview_d_plain" | grep -q 'I see timeouts too'; then
  _failed=$((_failed+1)); echo "  FAIL snippet leaks 3rd sentence past 2-sentence cap"
else
  _passed=$((_passed+1)); echo "  ok  snippet drops 3rd sentence past 2-sentence cap"
fi

# Session C's opener is ONE sentence and short — no ellipsis expected.
preview_c_plain="$(ccsesh_ui_preview "$expected_c" | strip_ansi | awk '/^Session started with:/{flag=1; next} flag {print; exit}')"
assert_match "$preview_c_plain" 'What happened to this project\?' "short session: full opener shown"
if printf '%s' "$preview_c_plain" | grep -q '…'; then
  _failed=$((_failed+1)); echo "  FAIL short session adds ellipsis (shouldn't)"
else
  _passed=$((_passed+1)); echo "  ok  short session: no ellipsis added"
fi

echo
echo "passed: $_passed  failed: $_failed"
[ "$_failed" -eq 0 ]
