#!/usr/bin/env bash
# Length budget enforcement, in two halves.
#
#   --measure   Stop hook. Counts the prose words in the turn that just ended and appends
#               them to a log. Measures only; a Stop hook cannot retract what is already
#               on screen, and blocking there makes the model APPEND a second answer,
#               which is worse than the long one.
#   --remind    UserPromptSubmit hook. Injects the budget plus the measured trailing
#               average into the next turn. This is the half that actually changes
#               behaviour, because it lands before the response instead of after it.
#
# Never blocks and never errors out: a broken budget reminder must not stop work.
set -uo pipefail

LOG="$HOME/.claude/worklogs/response-lengths.tsv"
mkdir -p "$(dirname "$LOG")" 2>/dev/null

payload=$(cat 2>/dev/null)
mode="${1:---remind}"

# Prose words in the current turn: assistant text blocks since the last real user message.
# Tool calls, tool results and command output are excluded, matching what the budget covers.
turn_words() {
  local transcript
  transcript=$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null)
  [ -n "$transcript" ] && [ -f "$transcript" ] || return 1

  # The boundary marker is a literal sentinel, not an escape: BSD awk does not honour
  # \xNN in a regex, so a NUL marker silently never matches and the count becomes the
  # whole transcript instead of one turn.
  jq -rc 'if .type=="user" and ((.isMeta // false)|not) and (((.message.content|tostring)|test("tool_result"))|not)
          then "@@TURN_BOUNDARY@@"
          elif .type=="assistant"
          then ([.message.content[]? | select(.type=="text") | .text] | join(" "))
          else empty end' "$transcript" 2>/dev/null \
  | awk 'BEGIN{w=0} $0=="@@TURN_BOUNDARY@@" {w=0; next} {w+=NF} END{print w}'
}

case "$mode" in
  --measure)
    words=$(turn_words) || exit 0
    [ -z "$words" ] && exit 0
    [ "$words" -eq 0 ] 2>/dev/null && exit 0
    printf '%s\t%s\n' "$(date -u +%FT%TZ)" "$words" >> "$LOG"
    exit 0
    ;;

  --remind)
    # Trailing average over the last 20 turns, so the nudge carries evidence rather than
    # an adjective. Silent until there is enough history to be meaningful.
    [ -f "$LOG" ] || exit 0
    stats=$(tail -20 "$LOG" 2>/dev/null | awk -F'\t' '
      {n++; s+=$2; if ($2>max) max=$2; if ($2>250) over++}
      END{ if (n>=5) printf "%d %d %d %d", s/n, max, over, n }')
    [ -z "$stats" ] && exit 0

    set -- $stats
    avg="$1"; max="$2"; over="$3"; n="$4"
    [ "$avg" -le 250 ] && exit 0   # inside budget; say nothing

    cat <<EOF
<length-budget>
Your last $n turns averaged $avg words of prose (longest $max; $over over 250).
The caps in CLAUDE.md are 100 words for a direct answer, 250 for an explanation, 80 for a
report after doing work. You are over. Cut a whole section rather than compressing sentences,
and do not recap work the user just watched. Code and command output do not count.
</length-budget>
EOF
    exit 0
    ;;

  *) exit 0 ;;
esac
