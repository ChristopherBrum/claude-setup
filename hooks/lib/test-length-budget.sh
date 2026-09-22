#!/usr/bin/env bash
# Test matrix for length-budget.sh
#
# The bug this exists to prevent: the turn boundary is a literal sentinel because BSD awk
# ignores \xNN in a regex. When the marker stops matching, nothing resets the counter and
# one turn is reported as the whole transcript. That failure is silent and reads as a
# plausible number, so it needs a test that pins the boundary, not just the arithmetic.
HOOK="${HOOK:-$HOME/.claude/hooks/length-budget.sh}"
pass=0; fail=0

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

say() { printf '{"type":"assistant","message":{"content":[{"type":"text","text":"%s"}]}}\n' "$1"; }
ask() { printf '{"type":"user","message":{"content":"%s"}}\n' "$1"; }
meta() { printf '{"type":"user","isMeta":true,"message":{"content":"%s"}}\n' "$1"; }
result() { printf '{"type":"user","message":{"content":[{"type":"tool_result","content":"%s"}]}}\n' "$1"; }
tooluse() { printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{}}]}}\n'; }

measure() {                       # measure <transcript-file> -> words logged
  local t="$1" log="$TMP/out.tsv"
  : > "$log"
  jq -n --arg p "$t" '{transcript_path:$p}' \
    | LENGTH_BUDGET_LOG="$log" "$HOOK" --measure >/dev/null 2>&1
  awk -F'\t' 'END{print ($2==""?0:$2)}' "$log"
}

check() {                         # check <want> <desc> <got>
  local want="$1" desc="$2" got="$3"
  if [ "$got" = "$want" ]; then
    pass=$((pass+1)); printf '  ok   %-6s %s\n' "$got" "$desc"
  else
    fail=$((fail+1)); printf '  FAIL want=%s got=%s :: %s\n' "$want" "$got" "$desc"
  fi
}

echo "== WORD COUNTING =="
T="$TMP/t1.jsonl"; { ask q; say "one two three"; } > "$T"
check 3 "counts prose in one assistant message" "$(measure "$T")"

T="$TMP/t2.jsonl"; { ask q; say "a b c"; say "d e"; } > "$T"
check 5 "sums consecutive assistant messages in the same turn" "$(measure "$T")"

echo "== TURN BOUNDARY (the silent-failure case) =="
T="$TMP/t3.jsonl"; { ask q1; say "a b c d e f"; ask q2; say "one two"; } > "$T"
check 2 "a real user message resets the count" "$(measure "$T")"

T="$TMP/t4.jsonl"; { ask q1; say "a b c"; result "rows"; say "d e"; } > "$T"
check 5 "a tool_result does NOT reset the count" "$(measure "$T")"

T="$TMP/t5.jsonl"; { ask q1; say "a b c"; meta "reminder"; say "d e"; } > "$T"
check 5 "an isMeta message does NOT reset the count" "$(measure "$T")"

echo "== WHAT DOES NOT COUNT =="
T="$TMP/t6.jsonl"; { ask q; tooluse; say "one two"; } > "$T"
check 2 "tool_use blocks are excluded" "$(measure "$T")"

T="$TMP/t7.jsonl"; { ask q; tooluse; } > "$T"
check 0 "a turn with no prose logs nothing" "$(measure "$T")"

echo "== REMIND: silent unless there is evidence =="
remind() { local log="$1"; printf '' | LENGTH_BUDGET_LOG="$log" "$HOOK" --remind 2>&1; }

L="$TMP/short.tsv"; for w in 900 900 900; do printf 'ts\t%s\n' "$w" >> "$L"; done
[ -z "$(remind "$L")" ] && { pass=$((pass+1)); echo "  ok   silent    under 5 samples, even when way over"; } \
                        || { fail=$((fail+1)); echo "  FAIL nudged on fewer than 5 samples"; }

L="$TMP/ok.tsv"; for w in 40 50 60 70 80 90; do printf 'ts\t%s\n' "$w" >> "$L"; done
[ -z "$(remind "$L")" ] && { pass=$((pass+1)); echo "  ok   silent    average inside budget"; } \
                        || { fail=$((fail+1)); echo "  FAIL nudged while inside budget"; }

L="$TMP/over.tsv"; for w in 300 400 500 600 700 800; do printf 'ts\t%s\n' "$w" >> "$L"; done
out=$(remind "$L")
case "$out" in
  *"<length-budget>"*"averaged 550 words"*"longest 800"*) pass=$((pass+1)); echo "  ok   nudge     reports avg, max and sample count" ;;
  *) fail=$((fail+1)); printf '  FAIL over-budget nudge wrong: %s\n' "${out:-<empty>}" ;;
esac

echo "== NEVER BLOCKS =="
printf '' | LENGTH_BUDGET_LOG="$TMP/x.tsv" "$HOOK" --measure >/dev/null 2>&1
check 0 "empty payload exits clean" "$?"
jq -n '{transcript_path:"/nope/missing.jsonl"}' | LENGTH_BUDGET_LOG="$TMP/x.tsv" "$HOOK" --measure >/dev/null 2>&1
check 0 "missing transcript exits clean" "$?"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
