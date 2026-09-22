#!/usr/bin/env bash
# PreToolUse (Bash) guard: block a push of ~/.claude that would publish employer content.
#
# This repo is published to a personal account, so every term that identifies where I
# work has to stay out of it. The terms themselves are derived at runtime from the
# gitignored identity.json, never written here: naming them in this file would leak the
# thing the file exists to prevent.
#
# Scans tracked content at HEAD, which is exactly what a push makes public. Emits a
# PreToolUse "deny" decision (JSON on stdout) on a match; otherwise exits 0 (allow).
set -euo pipefail

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
[ -z "$cmd" ] && exit 0
printf '%s' "$cmd" | grep -Eq 'git([[:space:]]+-[^[:space:]]+)*[[:space:]]+push' || exit 0

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
top=$(git -C "${cwd:-$PWD}" rev-parse --show-toplevel 2>/dev/null) || exit 0
# Resolve both sides through git: on macOS $HOME/.claude and --show-toplevel disagree
# whenever a parent is a symlink (/var vs /private/var), and a string compare misses.
self=$(git -C "$HOME/.claude" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ "$top" = "$self" ] || exit 0

IDENTITY="$HOME/.claude/identity.json"
BLOCKLIST="$HOME/.claude/.publish-blocklist"
[ -f "$IDENTITY" ] || exit 0

# Placeholders from identity.example.json must never become live patterns.
is_placeholder() {
  case "$(printf '%s' "$1" | tr 'A-Z' 'a-z')" in
    your-org|your-org.atlassian.net|abc|xx-abc|""|main|master) return 0 ;;
    *) return 1 ;;
  esac
}

terms=()
add() { is_placeholder "$1" || terms+=("$1"); }

host=$(jq -r '.issue_tracker.host // empty' "$IDENTITY")
add "${host%%.*}"                                             # org label out of the tracker host
add "$(jq -r '.git.owner // empty' "$IDENTITY")"
add "$(jq -r '.git.branch_prefix // empty' "$IDENTITY")"
[ -f "$BLOCKLIST" ] && while IFS= read -r line; do
  [ -n "$line" ] && [ "${line#\#}" = "$line" ] && add "$line"
done < "$BLOCKLIST"

pattern=""
for t in "${terms[@]:-}"; do
  [ -n "$t" ] || continue
  esc=$(printf '%s' "$t" | sed 's/[][\.*^$(){}?+|/]/\\&/g')
  pattern="${pattern:+$pattern|}$esc"
done

# The project key is matched only as a ticket reference. Bare, a short key like "ENG"
# matches "length" and every review would be blocked.
key=$(jq -r '.issue_tracker.project_key // empty' "$IDENTITY")
is_placeholder "$key" || pattern="${pattern:+$pattern|}${key}-[0-9]"

[ -n "$pattern" ] || exit 0

hits=$(git -C "$top" grep -I -i -n -E "$pattern" HEAD -- 2>/dev/null | head -20) || true
[ -n "$hits" ] || exit 0

jq -n --arg h "$(printf '%s' "$hits" | sed 's/^HEAD://')" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: ("Blocked: pushing ~/.claude would publish employer-identifying content to a personal account. Remove or genericise these, then push again. Values belong in identity.json or repos/<project>/, both gitignored.\n\n" + $h)
  }
}'
exit 0
