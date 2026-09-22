#!/usr/bin/env bash
# PreToolUse (Bash) guard for SUBAGENTS: auto-allow safe commands, deny dangerous ones.
#
# Goal: agents shouldn't prompt for trivial, non-dangerous shell commands. This hook
# runs only for subagents (detected via agent_id). For them it:
#   1. DENIES a dangerous set for ALL agents: pushing, dependency installs, outbound
#      network, `rm -rf`, and reading secret files (.env*, master.key, credentials*).
#   2. For READ-ONLY agents, additionally DENIES repo/system-mutating shell (redirection,
#      tee, mv, cp, rm, dd, truncate, sed -i) so they stay read-only — EXCEPT writes to
#      their own `agent-notes/` (how they persist facts) and scratch in /tmp or /dev/null.
#   3. AUTO-ALLOWS everything else, so agents run trivial commands without a prompt.
#
# The main thread (no agent_id) is never touched — it keeps default prompting. Deny from
# the separate git-history hook still applies (deny wins over this hook's allow).
#
# Best-effort by design: shell parsing via regex can't be exhaustive. It fails toward a
# prompt/deny, not toward silently running something dangerous.
set -euo pipefail

input=$(cat)
agent_id=$(printf '%s' "$input" | jq -r '.agent_id // empty')
# Main thread (no agent_id) -> do nothing, default behavior applies.
[ -z "$agent_id" ] && exit 0

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
[ -z "$cmd" ] && exit 0
agent_type=$(printf '%s' "$input" | jq -r '.agent_type // "subagent"')

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}
allow() {
  jq -n '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "allow"}}'
  exit 0
}
has() { printf '%s' "$cmd" | grep -Eq "$1"; }

# --- 0. Destructive-command guard: same rules as block-destructive-commands.sh ----------
# Evaluated BEFORE the write-agent auto-allow in section 2, so that allow can never
# cover a data-destroying command. Risky-but-recoverable commands fall through to a
# prompt instead of being auto-allowed.
# shellcheck source=lib/destructive-patterns.sh
. "${HOME}/.claude/hooks/lib/destructive-patterns.sh"
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
if reason=$(destructive_reason "$cmd" "$cwd"); then
  deny "Blocked for subagent ($agent_type): $reason. Do not work around it — report the command to the user and let them decide."
fi
risky=""
if reason=$(risky_reason "$cmd"); then
  risky="$reason"
fi

# --- 1. Dangerous set: denied for EVERY subagent ---------------------------------------
if has 'git[[:space:]]+push'; then
  deny "Blocked for subagent ($agent_type): pushing is not allowed. Leave your changes for review; the user lands them."
fi
if has 'git[[:space:]]+(commit|merge|cherry-pick|revert)'; then
  deny "Blocked for subagent ($agent_type): committing/merging is not allowed. Leave your edits as uncommitted working-tree changes; the user reviews the diff and commits."
fi
if has '(bundle[[:space:]]+(install|update)|gem[[:space:]]+install|yarn[[:space:]]+(add|install|global)|npm[[:space:]]+(install|i|add|ci)|pnpm[[:space:]]+(add|install)|pip[0-9]?[[:space:]]+install|brew[[:space:]]+(install|upgrade))'; then
  deny "Blocked for subagent ($agent_type): installing dependencies is not allowed. Report a needed dependency as a follow-up instead."
fi
if has '(^|[^[:alnum:]])(curl|wget|nc|ncat|telnet|ssh|scp|rsync)([[:space:]]|$)'; then
  deny "Blocked for subagent ($agent_type): outbound network / remote commands are not allowed. Use the WebFetch/WebSearch tools if needed."
fi
if has 'rm[[:space:]]+-[[:alnum:]]*r[[:alnum:]]*f|rm[[:space:]]+-[[:alnum:]]*f[[:alnum:]]*r'; then
  deny "Blocked for subagent ($agent_type): 'rm -rf' is not allowed."
fi
# Secret files: deny any command that references them (covers cat/grep/etc.).
if has '(^|[^[:alnum:]_])\.env([^[:alnum:]]|$)' || has 'config/master\.key' || has 'config/credentials'; then
  deny "Blocked for subagent ($agent_type): secret/credential files are off-limits. Secrets are fetched at runtime via Secret.fetch, never read through the shell."
fi

# --- 2. Write agents: allow everything else (they mutate the shared main working tree) --
# A risky command exits without a decision so normal prompting applies instead.
case " rails-engineer java-engineer frontend-engineer " in
  *" $agent_type "*) [ -n "$risky" ] && exit 0; allow ;;
esac

# --- 3. Read-only agents: block repo/system mutation, allow notes + scratch ------------
# Exempt writes to the agent's own notes dir and to scratch locations. `agent-notes` covers
# the per-repo personal layer (~/.claude/repos/<repo>/agent-notes, symlinked into the repo);
if [ -z "$risky" ] && { has 'agent-notes' || has '/dev/null' \
  || has '(^|[[:space:]])/tmp/'; }; then
  allow
fi
# Mutating shell -> deny (keeps read-only agents read-only).
if has '(^|[^[:alnum:]])(rm|mv|cp|dd|tee|truncate)([[:space:]]|$)' \
  || has 'sed[[:space:]].*(-i|--in-place)' \
  || has '(^|[[:space:]])>>?[[:space:]]*[^&|>[:space:]]'; then
  deny "Blocked for read-only subagent ($agent_type): writing/mutating files via the shell is not allowed. Read-only agents report findings; only their .claude/agent-notes/ dir is writable."
fi

# --- 4. Everything else -> allow (no prompt), unless flagged risky above ----------------
[ -n "$risky" ] && exit 0
allow
