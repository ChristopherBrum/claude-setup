#!/usr/bin/env bash
# PreToolUse (Bash) guard: block commands that destroy data.
#
# Rationale: a local development database was wiped by a shell command that never
# prompted, because both the settings allowlist (`Bash(bundle exec *)`,
# `Bash(bin/rails runner *)`) and restrict-subagent-bash.sh's write-agent
# auto-allow cover destructive commands. Permission rules are opt-in prefixes and
# can't express "anything but this", so the stop has to be a hook.
#
# Applies to the main thread AND every subagent, and is registered FIRST in the
# PreToolUse Bash chain so it is evaluated before any auto-allow.
#
# Rules live in hooks/lib/destructive-patterns.sh, shared with
# restrict-subagent-bash.sh so the two enforce the same set.
set -euo pipefail

# shellcheck source=lib/destructive-patterns.sh
. "${HOME}/.claude/hooks/lib/destructive-patterns.sh"

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
[ -z "$cmd" ] && exit 0
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')

decide() {
  jq -n --arg d "$1" --arg r "$2" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: $d,
      permissionDecisionReason: $r
    }
  }'
  exit 0
}

if reason=$(destructive_reason "$cmd" "$cwd"); then
  decide deny "Blocked: $reason. This is not recoverable, so it never runs automatically. Do NOT try to reach the same result another way. If it is genuinely needed, stop and ask the user to run it themselves by typing '! <command>' in the prompt."
fi

if reason=$(risky_reason "$cmd"); then
  decide ask "Needs explicit confirmation: $reason. Say why it is necessary and what it will touch before the user decides."
fi

exit 0
